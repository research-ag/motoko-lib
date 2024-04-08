import Principal "mo:base/Principal";
import Time "mo:base/Time";
import Int "mo:base/Int";
import Result "mo:base/Result";

import ICRC1 "ICRC1";
import Backlog "Backlog";
import DepositRegistry "DepositRegistry";
import Mapping "Mapping";
import Journal "Journal";
import CreditRegistry "CreditRegistry";

module {
  public type StableData = (
    DepositRegistry.StableData, // depositRegistry
    Backlog.StableData, // backlog
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
    isFrozen : () -> Bool,
    freezeCallback : (text : Text) -> (),
    creditRegistry : CreditRegistry.CreditRegistry,
  ) {

    let icrc1Ledger = actor (Principal.toText(icrc1LedgerPrincipal)) : ICRC1.ICRC1Ledger;

    /// Manages deposit balances for each user.
    let depositRegistry : DepositRegistry.DepositRegistry = DepositRegistry.DepositRegistry(freezeCallback);

    /// Manages acklog of principals waiting for processing.
    let backlog : Backlog.Backlog = Backlog.Backlog();

    /// Current fee amount.
    var fee_ : Nat = 0;

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

    /// Retrieves the current fee amount.
    public func fee() : Nat = fee_;

    /// Updates the fee amount based on the ICRC1 ledger.
    public func updateFee() : async* Nat {
      let newFee = await icrc1Ledger.icrc1_fee();
      if (fee_ != newFee) {
        journal.push((Time.now(), ownPrincipal, #feeUpdated({ old = fee_; new = newFee })));
        fee_ := newFee;
        recalculateBacklog();
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

      if (latestDeposit > fee_) {
        // precredit deposit funds
        ignore creditRegistry.credit(p, latestDeposit - fee_);
        // schedule consolidation for this p
        pushToBacklog(p, latestDeposit);
        // schedule a canister self-call to process the backlog
        // we need try-catch so that we don't trap if scheduling fails synchronously
        try ignore processBacklog() catch (_) {};
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
        #InsufficientDeposit;
      };
    } {
      if (deposit <= fee_) return #Err(#InsufficientDeposit);

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
        pushToBacklog(p, 0);
        return;
      };

      ignore updateDeposit(p, latestDeposit);

      ignore depositRegistry.set(
        p,
        func(info) {
          info.underway := latestDeposit;
          underwayFunds += latestDeposit - info.underway;
          true;
        },
      );

      let transferResult = await* processConsolidationTransfer(p, latestDeposit);

      switch (transferResult) {
        case (#Err(#InsufficientDeposit)) {
          ignore creditRegistry.debit(p, latestDeposit - fee_);
        };
        case (#Err(#BadFee { expected_fee })) {

          ignore creditRegistry.debit(p, latestDeposit - fee_);
          ignore creditRegistry.credit(p, latestDeposit - expected_fee);

          fee_ := expected_fee;

          journal.push((Time.now(), ownPrincipal, #feeUpdated({ old = fee_; new = expected_fee })));

          recalculateBacklog();

          let retryResult = await* processConsolidationTransfer(p, latestDeposit);
          switch (retryResult) {
            case (#Err(#InsufficientDeposit)) {
              ignore creditRegistry.debit(p, latestDeposit - fee_);
            };
            case (#Err _) {
              ignore creditRegistry.debit(p, latestDeposit - fee_);
              pushToBacklog(p, latestDeposit);
            };
            case (_) {};
          };
        };
        case (#Err _) {
          ignore creditRegistry.debit(p, latestDeposit - fee_);
          pushToBacklog(p, latestDeposit);
        };
        case (_) {};

      };

      ignore depositRegistry.set(
        p,
        func(info) {
          info.underway := 0;
          underwayFunds -= latestDeposit;
          true;
        },
      );
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
          ignore depositRegistry.set(
            p,
            func(info) {
              let amount = info.queued;
              info.queued := 0;
              queuedFunds -= amount;
              info.underway := amount;
              underwayFunds += amount;
              true;
            },
          );
          await* consolidate(p);
          depositRegistry.unlock(p);
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
          fee_ := expected_fee;
          recalculateBacklog();
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

    func pushToBacklog(p : Principal, deposit : Nat) {
      ignore depositRegistry.set(
        p,
        func(info) {
          queuedFunds -= info.queued;
          queuedFunds += deposit;
          info.queued := deposit;
          true;
        },
      );

      backlog.push(p);
    };

    /// Recalculate the backlog after the fee change.
    /// Reason: Some amounts in the backlog can be insufficient for consolidation.
    func recalculateBacklog() {
      label L for (p in backlog.iter()) {
        let ?depositInfo = depositRegistry.get(p) else continue L;
        if (depositInfo.queued <= fee_) {
          backlog.remove(p);
          ignore creditRegistry.debit(p, depositInfo.queued - fee_);
          ignore depositRegistry.set(
            p,
            func(info) {
              info.queued := 0;
              queuedFunds -= info.queued;
              true;
            },
          );
        };
      };
    };

    /// Updates the specified principal's deposit. Returns previous deposit.
    func updateDeposit(p : Principal, deposit : Nat) : Nat {
      var prevDeposit = 0;
      ignore depositRegistry.set(
        p,
        func(info) {
          prevDeposit := info.deposit;
          info.deposit := deposit;
          true;
        },
      );
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
      fee_ := values.2;
      totalConsolidated_ := values.3;
      totalWithdrawn_ := values.4;
      depositedFunds_ := values.5;
      queuedFunds := values.6;
    };
  };
};
