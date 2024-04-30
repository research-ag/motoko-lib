import Principal "mo:base/Principal";
import Int "mo:base/Int";
import Result "mo:base/Result";
import Text "mo:base/Text";
import Nat "mo:base/Nat";
import Iter "mo:base/Iter";
import Debug "mo:base/Debug";

import ICRC1 "ICRC1";
import NatMap "NatMapWithLock";
import Mapping "Mapping";

module {
  public type Lock = { #notify; #consolidate };
  public type StableData = (
    NatMap.StableData<Principal, Lock>, // depositRegistry
    Nat, // fee_
    Nat, // totalConsolidated_
    Nat, // totalWithdrawn_
    Nat, // queuedFunds
  );

  public type LogEvent = {
    #feeUpdated : { old : Nat; new : Nat };
    #newDeposit : Nat;
    #consolidated : { deducted : Nat; credited : Nat };
    #consolidationError : ICRC1.TransferError or { #CallIcrc1LedgerError };
    #withdraw : { to : ICRC1.Account; amount : Nat };
    #withdrawalError : ICRC1.TransferError or {
      #CallIcrc1LedgerError;
      #TooLowQuantity;
    };
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

    /// Manages deposit balances for each user.
    let depositRegistry = NatMap.NatMapWithLock<Principal, Lock>(Principal.compare);

    /// Current fee amount.
    var fee_ : Nat = initialFee;

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
      let newFee = await icrc1Ledger.fee();
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
    public func depositedFunds() : Nat = depositRegistry.sum();

    /// Returns the size of the deposit registry.
    public func depositsNumber() : Nat = depositRegistry.size();

    /// Retrieves the sum of all successful consolidations.
    public func totalConsolidated() : Nat = totalConsolidated_;

    /// Retrieves the sum of all deductions from the main account.
    public func totalWithdrawn() : Nat = totalWithdrawn_;

    /// Retrieves the calculated balance of the main account.
    public func consolidatedFunds() : Nat = totalConsolidated_ - totalWithdrawn_;

    /// Retrieves the deposit of a principal.
    public func getDeposit(p : Principal) : Nat = depositRegistry.get(p);

    /// Notifies of a deposit and schedules consolidation process.
    /// Returns the newly detected deposit if successful.
    public func notify(p : Principal) : async* ?Nat {
      let ?(_, release) = depositRegistry.obtainLock(p, #notify) else return null;
      let latestDeposit = try {
        await* loadDeposit(p);
      } catch (err) {
        ignore release(null);
        throw err;
      };

      if (latestDeposit <= fee_) {
        ignore release(null);
        return ?0;
      };

      let delta = release(?latestDeposit);
      if (delta < 0) freezeCallback("latestDeposit < prevDeposit on notify");
      if (delta == 0) return ?0;
      let inc = Int.abs(delta);

      // precredit incremental difference
      if (latestDeposit == inc) {
        credit(p, latestDeposit - fee_);
      } else {
        credit(p, inc);
      };

      queuedFunds += inc;
      log(p, #newDeposit(inc));

      // schedule a canister self-call to initiate the consolidation
      // we need try-catch so that we don't trap if scheduling fails synchronously
      try ignore trigger() catch (_) {};

      return ?inc;
    };

    /// Processes the consolidation transfer for a principal.
    func processConsolidationTransfer(p : Principal, deposit : Nat) : async* {
      #Ok : Nat;
      #Err : ICRC1.TransferError or { #CallIcrc1LedgerError };
    } {
      let transferAmount : Nat = Int.abs(deposit - fee_);

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

      switch (transferResult) {
        case (#Ok _) {
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
    func consolidate(p : Principal) : async* Bool {
      let deposit = depositRegistry.get(p);

      let originalFee = fee_;
      let transferResult = await* processConsolidationTransfer(p, deposit);

      switch (transferResult) {
        case (#Err(#BadFee { expected_fee })) {
          debit(p, deposit - originalFee);
          setNewFee(expected_fee);

          if (deposit > fee_) {
            credit(p, deposit - fee_);
          };
          false;
        };
        case (#Err _) false; // all other errors
        case (#Ok _) true;
      };
    };

    /// Triggers the proccessing first encountered deposit.
    public func trigger() : async* () {
      let ?p = depositRegistry.firstUnlocked() else return;
      let ?(deposit, release) = depositRegistry.obtainLock(p, #consolidate) else Debug.trap("Failed to obtain lock");
      queuedFunds -= deposit;
      underwayFunds += deposit;
      let success = await* consolidate(p);
      underwayFunds -= deposit;
      if (success or deposit <= fee_) {
        ignore release(?0);
      } else {
        ignore release(null);
        queuedFunds += deposit;
      };
      assertIntegrity();
    };

    /// Processes the transfer of funds for withdrawal.
    func processWithdrawTransfer(to : ICRC1.Account, amount : Nat) : async* {
      #Ok : Nat;
      #Err : ICRC1.TransferError or { #CallIcrc1LedgerError; #TooLowQuantity };
    } {
      if (amount <= fee_) return #Err(#TooLowQuantity);

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
          setNewFee(expected_fee);
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

    /// Recalculates the deposit registry after the fee change.
    /// Reason: Some amounts in the deposit registry can be insufficient for consolidation.
    func recalculateDepositRegistry(newFee : Nat, prevFee : Nat) {
      if (newFee > prevFee) {
        label L for ((p, info) in depositRegistry.entries()) {
          switch (info.lock) {
            case (? #consolidate) continue L;
            case (_) {};
          };
          let deposit = info.value;
          if (deposit <= newFee) {
            depositRegistry.erase(p);
            debit(p, deposit - prevFee);
            queuedFunds -= deposit;
          };
        };
      };
    };

    func assertIntegrity() {
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

      if (depositRegistry.sum() != queuedFunds + underwayFunds) {
        let values : [Text] = [
          "Balances integrity failed",
          "depositedFunds_=" # Nat.toText(depositRegistry.sum()),
          "queuedFunds=" # Nat.toText(queuedFunds),
          "underwayFunds=" # Nat.toText(underwayFunds),
        ];
        freezeCallback(Text.join("; ", Iter.fromArray(values)));
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
      queuedFunds,
    );

    /// Deserializes the token handler data.
    public func unshare(values : StableData) {
      depositRegistry.unshare(values.0);
      fee_ := values.1;
      totalConsolidated_ := values.2;
      totalWithdrawn_ := values.3;
      queuedFunds := values.4;
    };
  };
};
