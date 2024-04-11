import Principal "mo:base/Principal";
import Time "mo:base/Time";
import Int "mo:base/Int";
import Result "mo:base/Result";
import Text "mo:base/Text";
import Nat "mo:base/Nat";
import Iter "mo:base/Iter";

import ICRC1 "ICRC1";
import PrincipalSet "PrincipalSet";
import DepositRegistry "DepositRegistry";
import Mapping "Mapping";
import Journal "Journal";
import CreditRegistry "CreditRegistry";

module {
  public type StableData = (
    DepositRegistry.StableData, // depositRegistry
    PrincipalSet.StableData, // backlog
    PrincipalSet.StableData, // dust
    Nat, // fee_
    Nat, // totalConsolidated_
    Nat, // totalWithdrawn_
    Nat, // depositedFunds_
    Nat, // queuedFunds
  );

  /// Manages accounts and funds for users.
  /// Handles deposit, withdrawal, and consolidation operations.
  public class AccountManager(
    icrc1LedgerPrincipal : Principal,
    ownPrincipal : Principal,
    journal : Journal.Journal,
    initialFee : Nat,
    isFrozen : () -> Bool,
    freezeCallback : (text : Text) -> (),
    creditRegistry : CreditRegistry.CreditRegistry,
  ) {

    let icrc1Ledger = actor (Principal.toText(icrc1LedgerPrincipal)) : ICRC1.ICRC1Ledger;

    /// Manages deposit balances for each user.
    let depositRegistry : DepositRegistry.DepositRegistry = DepositRegistry.DepositRegistry(freezeCallback);

    /// Manages set of principals waiting for consolidation.
    let backlog : PrincipalSet.PrincipalSet = PrincipalSet.PrincipalSet();

    /// Manages set of principals with dust deposits.
    let dust : PrincipalSet.PrincipalSet = PrincipalSet.PrincipalSet();

    /// Current fee amount.
    var fee_ : Nat = initialFee;

    /// Total deposited funds across all accounts.
    var depositedFunds_ : Nat = 0;

    /// Total amount consolidated. Accumulated value.
    var totalConsolidated_ : Nat = 0;

    /// Total amount withdrawn. Accumulated value.
    var totalWithdrawn_ : Nat = 0;

    /// Total funds queued for consolidation.
    var queuedFunds : Nat = 0;

    /// Total funds underway for consolidation.
    var underwayFunds : Nat = 0;

    /// Total dust deposits (i.e. those that are less than the fee and insufficient for consolidation).
    var dustFunds : Nat = 0;

    /// Total funds credited within deposit tracking and consolidation.
    /// Accumulated value.
    var totalCredited : Nat = 0;

    /// Total funds debited within deposit tracking and consolidation.
    /// Accumulated value.
    var totalDebited : Nat = 0;

    /// Retrieves the current fee amount.
    public func fee() : Nat = fee_;

    /// Updates the fee amount based on the ICRC1 ledger.
    public func updateFee() : async* Nat {
      let newFee = await icrc1Ledger.icrc1_fee();
      if (fee_ != newFee) {
        journal.push((Time.now(), ownPrincipal, #feeUpdated({ old = fee_; new = newFee })));
        recalculateBacklog(fee_, newFee);
        recalculateDust();
        fee_ := newFee;
      };
      newFee;
    };

    /// Retrieves the sum of all current deposits. This value is nearly the same as backlogFunds(), but includes
    /// entries, which could not be added to backlog, for instance when balance less than fee.
    /// It's always >= backlogFunds()
    public func depositedFunds() : Nat = depositedFunds_;

    /// Retrieves the sum of all successful consolidations.
    public func totalConsolidated() : Nat = totalConsolidated_;

    /// Retrieves the sum of all deductions from the main account.
    public func totalWithdrawn() : Nat = totalWithdrawn_;

    /// Retrieves the calculated balance of the main account.
    public func consolidatedFunds() : Nat = totalConsolidated_ - totalWithdrawn_;

    /// Returns the size of the consolidation backlog.
    public func backlogSize() : Nat = backlog.size();

    /// Returns the sum of all deposits in the backlog.
    public func backlogFunds() : Nat = queuedFunds + underwayFunds;

    /// Retrieves the deposit of a principal.
    public func getDeposit(p : Principal) : Nat = depositRegistry.get(p).deposit;

    /// Notifies of a deposit and schedules backlog processing.
    /// Returns the newly detected deposit if successful.
    public func notify(p : Principal) : async* ?Nat {
      if (isFrozen() or not depositRegistry.lock(p)) return null;

      let latestDeposit = try {
        await* loadDeposit(p);
      } catch (err) {
        depositRegistry.unlock(p);
        throw err;
      };

      depositRegistry.unlock(p);

      let prevDeposit = updateDeposit(p, latestDeposit);

      if (latestDeposit < prevDeposit) freezeCallback("latestDeposit < prevDeposit on notify");

      // precredit deposit funds
      if (latestDeposit > fee_) {
        if (not dust.has(p)) {
          // in case previous deposit is credited
          // then credit incremental difference
          ignore credit(p, latestDeposit - prevDeposit);
          // schedule consolidation for this p
          pushToBacklog(p, latestDeposit, prevDeposit);
        } else {
          ignore credit(p, latestDeposit - fee_);
          // reset dust deposit
          dust.remove(p);
          dustFunds -= prevDeposit;
          // schedule consolidation for this p
          pushToBacklog(p, latestDeposit, 0);
        };

        // schedule a canister self-call to process the backlog
        // we need try-catch so that we don't trap if scheduling fails synchronously
        try ignore processBacklog() catch (_) {};
      } else {
        // update dust when the deposit is not sufficient
        if (not dust.has(p)) {
          pushToDust(p, latestDeposit, 0);
        } else {
          pushToDust(p, latestDeposit, prevDeposit);
        };
      };

      let depositDelta = latestDeposit - prevDeposit : Nat;

      if (depositDelta > 0) journal.push((Time.now(), p, #newDeposit(depositDelta)));

      return ?depositDelta;
    };

    /// Processes the consolidation transfer for a principal.
    func processConsolidationTransfer(p : Principal, deposit : Nat) : async* {
      #Ok : Nat;
      #Err : ICRC1.TransferError or {
        #CallIcrc1LedgerError;
      };
    } {
      let transferAmount : Nat = Int.abs(deposit - fee_);

      let transferResult = try {
        await icrc1Ledger.icrc1_transfer({
          from_subaccount = ?Mapping.toSubaccount(p);
          to = { owner = ownPrincipal; subaccount = null };
          amount = transferAmount;
          fee = ?fee_;
          memo = null;
          created_at_time = null;
        });
      } catch (_) {
        #Err(#CallIcrc1LedgerError);
      };

      switch (transferResult) {
        case (#Ok _) {
          ignore updateDeposit(p, 0);
          totalConsolidated_ += transferAmount;
          journal.push((Time.now(), p, #consolidated({ deducted = deposit; credited = transferAmount })));
        };
        case (#Err err) {
          journal.push((Time.now(), p, #consolidationError(err)));
        };
      };

      transferResult;
    };

    /// Attempts to consolidate the funds for a particular principal.
    func consolidate(p : Principal) : async* () {
      let latestDeposit = try { await* loadDeposit(p) } catch (err) {
        pushToBacklog(p, 0, depositRegistry.get(p).deposit);
        return;
      };

      let prevDeposit = updateDeposit(p, latestDeposit);

      ignore credit(p, latestDeposit - prevDeposit);

      underwayFunds += latestDeposit - prevDeposit;

      let transferResult = await* processConsolidationTransfer(p, latestDeposit);

      switch (transferResult) {
        case (#Err(#BadFee { expected_fee })) {
          ignore debit(p, latestDeposit - fee_);

          journal.push((Time.now(), ownPrincipal, #feeUpdated({ old = fee_; new = expected_fee })));

          recalculateBacklog(fee_, expected_fee);
          recalculateDust();

          fee_ := expected_fee;

          if (latestDeposit <= fee_) {
            underwayFunds -= latestDeposit;
            pushToDust(p, latestDeposit, 0);
            return;
          };

          ignore credit(p, latestDeposit - expected_fee);

          let retryResult = await* processConsolidationTransfer(p, latestDeposit);
          switch (retryResult) {
            case (#Err _) {
              pushToBacklog(p, latestDeposit, prevDeposit);
            };
            case (_) {};
          };
        };
        case (#Err _) {
          pushToBacklog(p, latestDeposit, prevDeposit);
        };
        case (_) {};
      };

      underwayFunds -= latestDeposit;
    };

    /// Processes the backlog by selecting the first encountered principal for consolidation.
    public func processBacklog() : async* () {
      if (isFrozen()) {
        return;
      };

      var p : ?Principal = null;

      label L for (v in backlog.iter()) {
        if (not depositRegistry.isLock(v)) {
          backlog.remove(v);
          p := ?v;
          break L;
        };
      };

      switch (p) {
        case (null) { return };
        case (?p) {
          ignore depositRegistry.lock(p);
          let deposit = depositRegistry.get(p).deposit;
          queuedFunds -= deposit;
          underwayFunds += deposit;
          await* consolidate(p);
          depositRegistry.unlock(p);
          assertIntegrity();
        };
      };
    };

    /// Processes the transfer of funds for withdrawal.
    func processWithdrawTransfer(to : ICRC1.Account, amount : Nat) : async* {
      #Ok : Nat;
      #Err : ICRC1.TransferError or { #CallIcrc1LedgerError; #TooLowQuantity };
    } {
      if (amount <= fee_) return #Err(#TooLowQuantity);

      try {
        await icrc1Ledger.icrc1_transfer({
          from_subaccount = null;
          to = to;
          amount = Int.abs(amount - fee_);
          fee = ?fee_;
          memo = null;
          created_at_time = null;
        });
      } catch (err) {
        #Err(#CallIcrc1LedgerError);
      };
    };

    /// Initiates a withdrawal by transferring tokens to another account.
    /// Returns ICRC1 transaction index and amount of transferred tokens (fee excluded).
    public func withdraw(to : ICRC1.Account, amount : Nat) : async* Result.Result<(transactionIndex : Nat, withdrawnAmount : Nat), ICRC1.TransferError or { #CallIcrc1LedgerError; #TooLowQuantity }> {

      totalWithdrawn_ += amount;

      let callResult = await* processWithdrawTransfer(to, amount);

      switch (callResult) {
        case (#Ok txIdx) {
          journal.push((Time.now(), ownPrincipal, #withdraw({ to = to; amount = amount })));
          #ok(txIdx, amount - fee_);
        };
        case (#Err(#BadFee { expected_fee })) {
          journal.push((Time.now(), ownPrincipal, #feeUpdated({ old = fee_; new = expected_fee })));
          recalculateBacklog(fee_, expected_fee);
          recalculateDust();
          fee_ := expected_fee;
          let retryResult = await* processWithdrawTransfer(to, amount);
          switch (retryResult) {
            case (#Ok txIdx) {
              journal.push((Time.now(), ownPrincipal, #withdraw({ to = to; amount = amount })));
              #ok(txIdx, amount - fee_);
            };
            case (#Err err) {
              totalWithdrawn_ -= amount;
              #err(err);
            };
          };
        };
        case (#Err err) {
          totalWithdrawn_ -= amount;
          #err(err);
        };
      };
    };

    /// Increases the credit amount associated with a specific principal.
    /// For internal use only - within deposit tracking and consolidation.
    func credit(p : Principal, amount : Nat) : Bool {
      totalCredited += amount;
      creditRegistry.credit(p, amount);
    };

    /// Deducts the credit amount associated with a specific principal.
    /// For internal use only - within deposit tracking and consolidation.
    func debit(p : Principal, amount : Nat) : Bool {
      totalDebited += amount;
      creditRegistry.debit(p, amount);
    };

    /// Pushes a principal to the backlog with `dusts` and `queuedFunds` synchronization.
    func pushToBacklog(p : Principal, deposit : Nat, prevQueued : Nat) {
      queuedFunds += deposit - prevQueued;
      backlog.push(p);
      dust.remove(p);
    };

    /// Pushes a principal to the dust with `backlog` and `dustFunds` synchronization.
    func pushToDust(p : Principal, deposit : Nat, prevDust : Nat) {
      dustFunds += deposit - prevDust;
      dust.push(p);
      backlog.remove(p);
    };

    /// Recalculates the backlog after the fee change.
    /// Reason: Some amounts in the backlog can be insufficient for consolidation.
    func recalculateBacklog(prevFee : Nat, newFee : Nat) {
      label L for (p in backlog.iter()) {
        let deposit = depositRegistry.get(p).deposit;
        if (deposit <= newFee) {
          backlog.remove(p);
          ignore debit(p, deposit - prevFee);
          queuedFunds -= deposit;
          pushToDust(p, deposit, 0);
        };
      };
    };

    /// Recalculates the dust after the fee change.
    /// Reason: Some amounts in the backlog can be sufficient for consolidation.
    func recalculateDust() {
      label L for (p in dust.iter()) {
        let deposit = depositRegistry.get(p).deposit;
        if (deposit > fee_) {
          dust.remove(p);
          ignore credit(p, deposit - fee_);
          dustFunds -= deposit;
          pushToBacklog(p, deposit, 0);
        };
      };
    };

    func assertIntegrity() {
      let backlogFunds_ : Int = backlogFunds() - fee_ * backlog.size(); // backlog with fees subtracted
      if (totalCredited != totalConsolidated_ + backlogFunds_ + totalDebited) {
        let values : [Text] = [
          "Balances integrity failed",
          "totalCredited=" # Nat.toText(totalCredited),
          "totalDebited=" # Nat.toText(totalDebited),
          "totalConsolidated_=" # Nat.toText(totalConsolidated_),
          "backlogFunds_=" # Int.toText(backlogFunds_),
        ];
        freezeCallback(Text.join("; ", Iter.fromArray(values)));
        return;
      };

      if (depositedFunds_ != queuedFunds + underwayFunds + dustFunds) {
        let values : [Text] = [
          "Balances integrity failed",
          "depositedFunds_=" # Nat.toText(depositedFunds_),
          "queuedFunds=" # Nat.toText(queuedFunds),
          "underwayFunds=" # Nat.toText(underwayFunds),
          "dustFunds=" # Int.toText(dustFunds),
        ];
        freezeCallback(Text.join("; ", Iter.fromArray(values)));
      };
    };

    /// Updates the specified principal's deposit. Returns previous deposit.
    func updateDeposit(p : Principal, deposit : Nat) : Nat {
      var prevDeposit = depositRegistry.get(p).deposit;
      depositRegistry.setDeposit(p, deposit);
      depositedFunds_ += deposit;
      depositedFunds_ -= prevDeposit;
      prevDeposit;
    };

    /// Fetches actual deposit for a principal from the ICRC1 ledger.
    func loadDeposit(p : Principal) : async* Nat {
      await icrc1Ledger.icrc1_balance_of({
        owner = ownPrincipal;
        subaccount = ?Mapping.toSubaccount(p);
      });
    };

    /// Serializes the token handler data.
    public func share() : StableData = (
      depositRegistry.share(),
      backlog.share(),
      dust.share(),
      fee_,
      totalConsolidated_,
      totalWithdrawn_,
      depositedFunds_,
      queuedFunds,
    );

    /// Deserializes the token handler data.
    public func unshare(values : StableData) {
      depositRegistry.unshare(values.0);
      backlog.unshare(values.1);
      dust.unshare(values.2);
      fee_ := values.3;
      totalConsolidated_ := values.4;
      totalWithdrawn_ := values.5;
      depositedFunds_ := values.6;
      queuedFunds := values.7;
    };
  };
};
