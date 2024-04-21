import Principal "mo:base/Principal";
import Int "mo:base/Int";
import Result "mo:base/Result";
import Text "mo:base/Text";
import Nat "mo:base/Nat";
import Iter "mo:base/Iter";

import ICRC1 "ICRC1";
import DepositRegistry "DepositRegistry";
import Mapping "Mapping";

module {
  public type StableData = (
    DepositRegistry.StableData, // depositRegistry
    Nat, // fee_
    Nat, // totalConsolidated_
    Nat, // totalWithdrawn_
    Nat, // depositedFunds_
    Nat, // queuedFunds
  );

  public type LogEvent = {
    #feeUpdated : { old : Nat; new : Nat };
    #newDeposit : Nat;
    #consolidated : { deducted : Nat; credited : Nat };
    #consolidationError : ICRC1.TransferError or { #CallIcrc1LedgerError };
    #withdraw : { to : ICRC1.Account; amount : Nat };
  };

  /// Manages accounts and funds for users.
  /// Handles deposit, withdrawal, and consolidation operations.
  public class AccountManager(
    icrc1LedgerPrincipal : Principal,
    ownPrincipal : Principal,
    log : (Principal, LogEvent) -> (),
    initialFee : Nat,
    freezeCallback : (text : Text) -> (),
    credit_ : (Principal, Nat) -> (),
    debit_ : (Principal, Nat) -> (),
  ) {

    let icrc1Ledger = actor (Principal.toText(icrc1LedgerPrincipal)) : ICRC1.ICRC1Ledger;

    /// Manages deposit balances for each user.
    let depositRegistry : DepositRegistry.DepositRegistry = DepositRegistry.DepositRegistry(freezeCallback);

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

    /// Total funds credited within deposit tracking and consolidation.
    /// Accumulated value.
    var totalCredited : Nat = 0;

    /// Total funds debited within deposit tracking and consolidation.
    /// Accumulated value.
    var totalDebited : Nat = 0;

    // Pass through the lookup counter from depositRegistry 
    // TODO: Remove later 
    public func lookups() : Nat = depositRegistry.lookups();

    /// Retrieves the current fee amount.
    public func fee() : Nat = fee_;

    /// Updates the fee amount based on the ICRC1 ledger.
    public func updateFee() : async* Nat {
      let newFee = await icrc1Ledger.icrc1_fee();
      setNewFee(newFee);
      newFee;
    };

    func setNewFee(newFee : Nat) {
      if (fee_ != newFee) {
        log(ownPrincipal, #feeUpdated({ old = fee_; new = newFee }));
        recalculateDepositRegistry(newFee, fee_);
        fee_ := newFee;
      };
    };

    /// Retrieves the sum of all current deposits.
    public func depositedFunds() : Nat = depositedFunds_;

    /// Returns the size of the deposit registry.
    public func depositsNumber() : Nat = depositRegistry.size();

    /// Retrieves the sum of all successful consolidations.
    public func totalConsolidated() : Nat = totalConsolidated_;

    /// Retrieves the sum of all deductions from the main account.
    public func totalWithdrawn() : Nat = totalWithdrawn_;

    /// Retrieves the calculated balance of the main account.
    public func consolidatedFunds() : Nat = totalConsolidated_ - totalWithdrawn_;

    /// Retrieves the deposit of a principal.
    public func getDeposit(p : Principal) : Nat = depositRegistry.get(p).deposit;

    /// Notifies of a deposit and schedules consolidation process.
    /// Returns the newly detected deposit if successful.
    public func notify(p : Principal) : async* ?Nat {
      if (depositRegistry.isLock(p)) return null;

      depositRegistry.lock(p);
      let latestDeposit = try {
        await* loadDeposit(p);
      } catch (err) {
        depositRegistry.unlock(p);
        throw err;
      };
      depositRegistry.unlock(p);

      if (latestDeposit <= fee_) return ?0;

      let prevDeposit = updateDeposit(p, latestDeposit);

      if (latestDeposit < prevDeposit) freezeCallback("latestDeposit < prevDeposit on notify");
      let depositDelta = latestDeposit - prevDeposit : Nat;
      if (depositDelta == 0) return ?0;

      // precredit incremental difference
      if (prevDeposit == 0) {
        credit(p, latestDeposit - fee_);
      } else {
        credit(p, depositDelta);
      };

      queuedFunds += depositDelta;
      log(p, #newDeposit(depositDelta));

      // schedule a canister self-call to initiate the consolidation
      // we need try-catch so that we don't trap if scheduling fails synchronously
      try ignore trigger() catch (_) {};

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
          log(p, #consolidated({ deducted = deposit; credited = transferAmount }));
        };
        case (#Err err) {
          log(p, #consolidationError(err));
        };
      };

      transferResult;
    };

    /// Attempts to consolidate the funds for a particular principal.
    func consolidate(p : Principal) : async* () {
      let deposit = depositRegistry.get(p).deposit;

      let transferResult = await* processConsolidationTransfer(p, deposit);

      switch (transferResult) {
        case (#Err(#BadFee { expected_fee })) {
          debit(p, deposit - fee_);
          setNewFee(expected_fee);

          if (deposit <= fee_) {
            underwayFunds -= deposit;
            ignore updateDeposit(p, 0);
            return;
          };

          credit(p, deposit - expected_fee);
        };
        case (_) {};
      };

      underwayFunds -= deposit;
    };

    /// Triggers the proccessing first encountered deposit.
    public func trigger() : async* () {
      var entry : ?(Principal, DepositRegistry.DepositInfo) = null;

      label L for (v in depositRegistry.entries()) {
        if (not depositRegistry.isLock(v.0)) {
          entry := ?v;
          break L;
        };
      };

      switch (entry) {
        case (null) { return };
        case (?(p, depositInfo)) {
          let deposit = depositInfo.deposit;
          depositRegistry.lock(p);
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
          log(ownPrincipal, #withdraw({ to = to; amount = amount }));
          #ok(txIdx, amount - fee_);
        };
        case (#Err(#BadFee { expected_fee })) {
          setNewFee(expected_fee);
          let retryResult = await* processWithdrawTransfer(to, amount);
          switch (retryResult) {
            case (#Ok txIdx) {
              log(ownPrincipal, #withdraw({ to = to; amount = amount }));
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
    func credit(p : Principal, amount : Nat) {
      totalCredited += amount;
      credit_(p, amount);
    };

    /// Deducts the credit amount associated with a specific principal.
    /// For internal use only - within deposit tracking and consolidation.
    func debit(p : Principal, amount : Nat) {
      totalDebited += amount;
      debit_(p, amount);
    };

    /// Recalculates the deposit registry after the fee change.
    /// Reason: Some amounts in the deposit registry can be insufficient for consolidation.
    func recalculateDepositRegistry(newFee : Nat, prevFee : Nat) {
      if (newFee > prevFee) {
        label L for ((p, info) in depositRegistry.entries()) {
          if (info.lock) continue L;
          let deposit = info.deposit;
          if (deposit <= newFee) {
            ignore updateDeposit(p, 0);
            debit(p, deposit - prevFee);
            queuedFunds -= deposit;
          };
        };
      };
    };

    func assertIntegrity() {
      let deposited : Int = depositedFunds_ - fee_ * depositRegistry.size(); // deposited funds with fees subtracted
      if (totalCredited != totalConsolidated_ + deposited + totalDebited) {
        let values : [Text] = [
          "Balances integrity failed",
          "totalCredited=" # Nat.toText(totalCredited),
          "totalConsolidated_=" # Nat.toText(totalConsolidated_),
          "deposited=" # Int.toText(deposited),
          "totalDebited=" # Nat.toText(totalDebited),
        ];
        freezeCallback(Text.join("; ", Iter.fromArray(values)));
        return;
      };

      if (depositedFunds_ != queuedFunds + underwayFunds) {
        let values : [Text] = [
          "Balances integrity failed",
          "depositedFunds_=" # Nat.toText(depositedFunds_),
          "queuedFunds=" # Nat.toText(queuedFunds),
          "underwayFunds=" # Nat.toText(underwayFunds),
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
      fee_,
      totalConsolidated_,
      totalWithdrawn_,
      depositedFunds_,
      queuedFunds,
    );

    /// Deserializes the token handler data.
    public func unshare(values : StableData) {
      depositRegistry.unshare(values.0);
      fee_ := values.1;
      totalConsolidated_ := values.2;
      totalWithdrawn_ := values.3;
      depositedFunds_ := values.4;
      queuedFunds := values.5;
    };
  };
};
