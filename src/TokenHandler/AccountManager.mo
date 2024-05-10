import Principal "mo:base/Principal";
import Int "mo:base/Int";
import Result "mo:base/Result";
import Text "mo:base/Text";
import Nat "mo:base/Nat";
import Iter "mo:base/Iter";

import ICRC1 "ICRC1";
import NatMap "NatMapWithLock";
import Mapping "Mapping";

module {
  public type StableData = (
    NatMap.StableData<Principal>, // depositRegistry
    Nat, // fee_
    Nat, // totalConsolidated_
    Nat, // totalWithdrawn_
  );

  public type LogEvent = {
    #feeUpdated : { old : Nat; new : Nat };
    #depositMinimumUpdated : { old : Nat; new : Nat };
    #withdrawalMinimumUpdated : { old : Nat; new : Nat };
    #newDeposit : Nat;
    #consolidated : { deducted : Nat; credited : Nat };
    #consolidationError : ICRC1.TransferError or { #CallIcrc1LedgerError };
    #withdraw : { to : ICRC1.Account; amount : Nat };
    #withdrawalError : ICRC1.TransferError or {
      #CallIcrc1LedgerError;
      #TooLowQuantity;
    };
  };

  public type MinimumType = {
    #deposit;
    #withdrawal;
  };

  /// Manages accounts and funds for users.
  /// Handles deposit, withdrawal, and consolidation operations.
  public class AccountManager(
    icrc1Ledger : ICRC1.LedgerAPI,
    ownPrincipal : Principal,
    log : (Principal, LogEvent) -> (),
    initialFee : Nat,
    freezeCallback : (text : Text) -> (),
    credit_ : (Principal, Nat) -> (),
    debit_ : (Principal, Nat) -> (),
  ) {

    /// Current fee amount.
    var fee_ : Nat = initialFee;

    /// Manages deposit balances for each user.
    let depositRegistry = NatMap.NatMapWithLock<Principal>(Principal.compare, fee_ + 1);

    /// Admin-defined deposit minimum.
    /// Can be less then the current fee.
    /// Final minimum: max(admin_defined_min, fee + 1).
    var definedDepositMinimum_ : Nat = 1;

    /// Admin-defined withdrawal minimum.
    /// Can be less then the current fee.
    /// Final minimum: max(admin_defined_min, fee + 1).
    var definedWithdrawalMinimum_ : Nat = 1;

    /// Total amount consolidated. Accumulated value.
    var totalConsolidated_ : Nat = 0;

    /// Total amount withdrawn. Accumulated value.
    var totalWithdrawn_ : Nat = 0;

    /// Total funds underway for consolidation.
    var underwayFunds_ : Nat = 0;

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

    /// Retrieves the admin-defined minimum of the specific type.
    public func definedMinimum(minimumType : MinimumType) : Nat = switch (minimumType) {
      case (#deposit) definedDepositMinimum_;
      case (#withdrawal) definedWithdrawalMinimum_;
    };

    /// Calculates the final minimum of the specific type.
    public func minimum(minimumType : MinimumType) : Nat = Nat.max(definedMinimum(minimumType), fee_ + 1);

    /// Defines the admin-defined minimum of the specific type.
    public func setMinimum(minimumType : MinimumType, min : Nat) {
      if (min == definedMinimum(minimumType)) return;
      let prevMin = minimum(minimumType);
      switch (minimumType) {
        case (#deposit) definedDepositMinimum_ := min;
        case (#withdrawal) definedWithdrawalMinimum_ := min;
      };
      let nextMin = minimum(minimumType);
      if (prevMin != nextMin) {
        log(
          ownPrincipal,
          switch (minimumType) {
            case (#deposit) #depositMinimumUpdated({
              old = prevMin;
              new = nextMin;
            });
            case (#withdrawal) #withdrawalMinimumUpdated({
              old = prevMin;
              new = nextMin;
            });
          },
        );
      };
    };

    var fetchFeeLock : Bool = false;

    /// Updates the fee amount based on the ICRC1 ledger.
    /// Returns the new fee, or `null` if fetching is already in progress.
    public func fetchFee() : async* ?Nat {
      if (fetchFeeLock) return null;
      fetchFeeLock := true;
      let newFee = await icrc1Ledger.fee();
      fetchFeeLock := false;
      updateFee(newFee);
      ?newFee;
    };

    func updateFee(newFee : Nat) {
      if (fee_ == newFee) return;
      let prevDepositMin = minimum(#deposit);
      let prevWithdrawalMin = minimum(#withdrawal);
      // update the deposit minimum depending on the new fee
      // the callback debits the principal for deposits that are removed in this step
      depositRegistry.setMinimum(newFee + 1, func(p, v) = debit(p, v - fee_));
      // adjust credit for all queued deposits
      depositRegistry.iterate(
        func(p, v) {
          if (v <= newFee) freezeCallback("deposit <= newFee should have been erased in previous step");
          if (newFee > fee_) {
            debit(p, newFee - fee_);
          } else {
            credit(p, fee_ - newFee);
          };
        }
      );
      log(ownPrincipal, #feeUpdated({ old = fee_; new = newFee }));
      fee_ := newFee;
      // check if deposit minimum is updated
      let newDepositMin = minimum(#deposit);
      if (prevDepositMin != newDepositMin) {
        log(ownPrincipal, #depositMinimumUpdated({ old = prevDepositMin; new = newDepositMin }));
      };
      // check if withdrawal minimum is updated
      let newWithdrawalMin = minimum(#withdrawal);
      if (prevWithdrawalMin != newWithdrawalMin) {
        log(ownPrincipal, #withdrawalMinimumUpdated({ old = prevWithdrawalMin; new = newWithdrawalMin }));
      };
    };

    /// Retrieves the sum of all current deposits.
    public func depositedFunds() : Nat = depositRegistry.sum() + underwayFunds_;

    /// Retrieves the sum of all current deposits.
    public func underwayFunds() : Nat = underwayFunds_;

    /// Retrieves the sum of all current deposits.
    public func queuedFunds() : Nat = depositRegistry.sum();

    /// Returns the size of the deposit registry.
    public func depositsNumber() : Nat = depositRegistry.size();

    /// Retrieves the sum of all successful consolidations.
    public func totalConsolidated() : Nat = totalConsolidated_;

    /// Retrieves the sum of all deductions from the main account.
    public func totalWithdrawn() : Nat = totalWithdrawn_;

    /// Retrieves the calculated balance of the main account.
    public func consolidatedFunds() : Nat = totalConsolidated_ - totalWithdrawn_;

    /// Retrieves the deposit of a principal.
    public func getDeposit(p : Principal) : ?Nat = depositRegistry.getOpt(p);

    func process_deposit(p : Principal, deposit : Nat, release : ?Nat -> Int) : Nat {
      if (deposit <= fee_) {
        ignore release(null);
        return 0;
      };
      let delta = release(?deposit);
      if (delta < 0) freezeCallback("latestDeposit < prevDeposit on notify");
      if (delta == 0) return 0;
      let inc = Int.abs(delta);

      if (deposit == inc) {
        credit(p, deposit - fee_);
      } else {
        credit(p, inc);
      };
      inc;
    };

    /// Notifies of a deposit and schedules consolidation process.
    /// Returns the newly detected deposit if successful.
    public func notify(p : Principal) : async* ?Nat {
      let ?release = depositRegistry.obtainLock(p) else return null;

      let latestDeposit = try {
        await* loadDeposit(p);
      } catch (err) {
        ignore release(null);
        throw err;
      };

      if (latestDeposit < minimum(#deposit)) {
        ignore release(null);
        return ?0;
      };

      // This function calls release() to release the lock
      let inc = process_deposit(p, latestDeposit, release);

      if (inc > 0) {
        log(p, #newDeposit(inc));

        // schedule a canister self-call to initiate the consolidation
        // we need try-catch so that we don't trap if scheduling fails synchronously
        try ignore trigger() catch (_) {};
      };

      return ?inc;
    };

    /// Processes the consolidation transfer for a principal.
    func processConsolidationTransfer(p : Principal, deposit : Nat) : async* {
      #Ok : Nat;
      #Err : ICRC1.TransferError or { #CallIcrc1LedgerError };
    } {
      let transferAmount : Nat = deposit - fee_;

      let transferResult = try {
        await icrc1Ledger.transfer({
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

      transferResult;
    };

    /// Attempts to consolidate the funds for a particular principal.
    func consolidate(p : Principal, release : ?Nat -> Int) : async* () {
      let deposit = depositRegistry.erase(p);
      let originalCredit : Nat = deposit - fee_;

      let transferResult = await* processConsolidationTransfer(p, deposit);

      // catch #BadFee
      switch (transferResult) {
        case (#Err(#BadFee { expected_fee })) updateFee(expected_fee);
        case (_) {};
      };

      switch (transferResult) {
        case (#Ok _) {
          log(p, #consolidated({ deducted = deposit; credited = originalCredit }));
          totalConsolidated_ += originalCredit;
          ignore release(null);
        };
        case (#Err err) {
          log(p, #consolidationError(err));
          debit(p, originalCredit);
          ignore process_deposit(p, deposit, release);
        };
      };
    };

    /// Triggers the proccessing first encountered deposit.
    public func trigger() : async* () {
      let ?(p, deposit, release) = depositRegistry.nextLock() else return;
      underwayFunds_ += deposit;
      await* consolidate(p, release);
      underwayFunds_ -= deposit;
      assertIntegrity();
    };

    /// Processes the transfer of funds for withdrawal.
    func processWithdrawTransfer(to : ICRC1.Account, amount : Nat) : async* {
      #Ok : Nat;
      #Err : ICRC1.TransferError or { #CallIcrc1LedgerError; #TooLowQuantity };
    } {
      if (amount < minimum(#withdrawal)) return #Err(#TooLowQuantity);

      try {
        await icrc1Ledger.transfer({
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
          updateFee(expected_fee);
          let retryResult = await* processWithdrawTransfer(to, amount);
          switch (retryResult) {
            case (#Ok txIdx) {
              log(ownPrincipal, #withdraw({ to = to; amount = amount }));
              #ok(txIdx, amount - fee_);
            };
            case (#Err err) {
              totalWithdrawn_ -= amount;
              log(ownPrincipal, #withdrawalError(err));
              #err(err);
            };
          };
        };
        case (#Err err) {
          totalWithdrawn_ -= amount;
          log(ownPrincipal, #withdrawalError(err));
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

    public func assertIntegrity() {
      let deposited : Int = depositRegistry.sum() - fee_ * depositRegistry.size(); // deposited funds with fees subtracted
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

    };

    /// Fetches actual deposit for a principal from the ICRC1 ledger.
    func loadDeposit(p : Principal) : async* Nat {
      await icrc1Ledger.balance_of({
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
    );

    /// Deserializes the token handler data.
    public func unshare(values : StableData) {
      depositRegistry.unshare(values.0);
      fee_ := values.1;
      totalConsolidated_ := values.2;
      totalWithdrawn_ := values.3;
    };
  };
};
