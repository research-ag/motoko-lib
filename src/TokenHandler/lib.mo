import Result "mo:base/Result";
import Principal "mo:base/Principal";
import Time "mo:base/Time";
import Option "mo:base/Option";
import Int "mo:base/Int";
import Iter "mo:base/Iter";
import Text "mo:base/Text";
import Nat "mo:base/Nat";
import Debug "mo:base/Debug";

import CircularBuffer "../CircularBuffer";
import Mapping "Mapping";
import Backlog "Backlog";
import BalanceRegistry "BalanceRegistry";
import ICRC1 "ICRC1";

module {
  type Info = BalanceRegistry.Info;
  type InfoLock = BalanceRegistry.InfoLock;

  public type JournalRecord = (
    Time.Time,
    Principal,
    {
      #newDeposit : Nat;
      #consolidated : { deducted : Nat; credited : Nat };
      #debited : Nat;
      #credited : Nat;
      #feeUpdated : { old : Nat; new : Nat };
      #error : Text;
      #consolidationError : ICRC1.TransferError or { #CallIcrc1LedgerError };
      #withdraw : { to : ICRC1.Account; amount : Nat };
    },
  );

  public type StableData = (
    BalanceRegistry.StableData, // balanceRegistry
    Backlog.StableData, // backlog
    Nat, // fee_
    Nat, // totalConsolidated_
    Nat, // totalWithdrawn_
    Nat, // depositedFunds_
    (Nat, Nat), // totalDebited, totalCredited
    ([var ?JournalRecord], Nat, Nat) // journal
  );

  public func defaultStableData() : StableData = ([], (0, []), 0, 0, 0, 0, (0, 0), ([var], 0, 0));

  /// Converts `Principal` to `ICRC1.Subaccount`.
  public func toSubaccount(p : Principal) : ICRC1.Subaccount = Mapping.toSubaccount(p);

  /// Converts `ICRC1.Subaccount` to `Principal`.
  public func toPrincipal(subaccount : ICRC1.Subaccount) : ?Principal = Mapping.toPrincipal(subaccount);

  public class TokenHandler(
    icrc1LedgerPrincipal_ : Principal,
    ownPrincipal : Principal,
    journalSize : Nat,
  ) {

    let icrc1Ledger = actor (Principal.toText(icrc1LedgerPrincipal_)) : ICRC1.ICRC1Ledger;

    /// If some unexpected error happened, this flag turns true and handler stops doing anything until recreated.
    var isFrozen_ : Bool = false;

    /// Freezes the handler in case of unexpected errors and logs the error message to the journal.
    func freezeTokenHandler(errorText : Text) : () {
      isFrozen_ := true;
      journal.push((Time.now(), ownPrincipal, #error(errorText)));
    };

    /// Backlog of funds waiting for consolidation.
    let backlog : Backlog.Backlog = Backlog.Backlog();

    /// Collection of logs capturing events like deposits, withdrawals, fee updates, errors, etc.
    /// The journal provides a chronological history of actions taken by the handler.
    var journal : CircularBuffer.CircularBuffer<JournalRecord> = CircularBuffer.CircularBuffer<JournalRecord>(journalSize);

    /// Balances and locks associated with each user.
    let balanceRegistry : BalanceRegistry.BalanceRegistry = BalanceRegistry.BalanceRegistry(freezeTokenHandler);

    /// Total amount consolidated. Accumulated value.
    var totalConsolidated_ : Nat = 0;

    /// Total amount withdrawn. Accumulated value.
    var totalWithdrawn_ : Nat = 0;

    /// Current fee.
    var fee_ : Nat = 0;

    /// Total amount debited via `debit(p, amount)`.
    var totalDebited : Nat = 0;

    /// Total amount credited via `credit(p, amount)`.
    var totalCredited : Nat = 0;

    /// Total current deposited funds.
    var depositedFunds_ : Nat = 0;

    /// Returns the fee.
    public func fee() : Nat = fee_;

    /// Fetches and updates the fee from the ICRC1 ledger.
    public func updateFee() : async* Nat {
      let newFee = await icrc1Ledger.icrc1_fee();
      if (fee_ != newFee) {
        journal.push((Time.now(), ownPrincipal, #feeUpdated({ old = fee_; new = newFee })));
        fee_ := newFee;
      };
      newFee;
    };

    /// Retrieves the usable balance for a given principal.
    public func balance(p : Principal) : Int = info(p).usable_balance;

    /// Retrieves all tracked balances for debug purposes.
    public func info(p : Principal) : Info and {
      var usable_balance : Int;
    } {
      let ?item = balanceRegistry.get(p) else return {
        var deposit = 0;
        var credit = 0;
        var usable_balance = 0;
      };
      {
        var deposit = item.deposit;
        var credit = item.credit;
        var usable_balance = usableBalance(item);
      };
    };

    ///
    /// Fetches journal records from a specified index for debug purposes.
    ///
    /// Returns:
    /// 1) array of all items in order, starting from the oldest record in journal, but no earlier than "startFrom" if provided
    /// 2) the index of next upcoming journal log. Use this value as "startFrom" in your next journal query to fetch next entries
    public func queryJournal(startFrom : ?Nat) : ([JournalRecord], Nat) = (
      (
        Option.get(startFrom, 0)
        |> Int.abs(Int.max(_, journal.pushesAmount() - journalSize))
        |> journal.slice(_, journal.pushesAmount())
        |> Iter.toArray(_)
      ),
      journal.pushesAmount(),
    );

    /// Returns the ICRC1 ledger principal.
    public func icrc1LedgerPrincipal() : Principal = icrc1LedgerPrincipal_;

    /// Checks if the TokenHandler is frozen.
    public func isFrozen() : Bool = isFrozen_;

    /// Returns the size of the consolidation backlog.
    public func backlogSize() : Nat = backlog.size();

    /// Retrieves the sum of all successful consolidations
    public func totalConsolidated() : Nat = totalConsolidated_;

    /// Retrieves the sum of all deductions from the main account.
    public func totalWithdrawn() : Nat = totalWithdrawn_;

    /// Retrieves the calculated balance of the main account.
    public func consolidatedFunds() : Nat = totalConsolidated_ - totalWithdrawn_;

    /// Returns the sum of all balances in the backlog.
    public func backlogFunds() : Nat = backlog.funds();

    /// Retrieves the sum of all current deposits. This value is nearly the same as backlogFunds(), but includes
    /// entries, which could not be added to backlog, for instance when balance less than fee.
    /// It's always >= backlogFunds()
    public func depositedFunds() : Nat = depositedFunds_;

    /// Retrieves the sum of all user current credit funds.
    /// It can be negative because user can spend deposited funds before consolidation.
    public func creditedFunds() : Int = totalConsolidated_ + totalCredited - totalDebited;

    /// Calculates the sum of all user usable funds.
    public func usableFunds() : Int {
      // It's tricky to cache it because of excluding deposits, smaller than fee, from the usable balance.
      var usableSum : Int = 0;
      for (info in balanceRegistry.items()) {
        usableSum += usableBalance(info);
      };
      usableSum;
    };

    /// Deducts amount from P’s usable balance.
    /// Returns false if the balance is insufficient.
    public func debit(p : Principal, amount : Nat) : Bool {
      if (isFrozen()) {
        return false;
      };
      let result = balanceRegistry.change(
        p,
        func(info) {
          if (usableBalance(info) < amount) return false;
          info.credit -= amount;
          journal.push((Time.now(), p, #debited(amount)));
          return true;
        },
      );
      if (result) {
        totalDebited += amount;
      };
      assertBalancesIntegrity();
      result;
    };

    /// Adds amount to P’s usable balance (the credit is created out of thin air).
    public func credit(p : Principal, amount : Nat) : Bool {
      if (isFrozen()) {
        return false;
      };
      ignore balanceRegistry.set(
        p,
        func(info) {
          info.credit += amount;
          true;
        },
      );
      totalCredited += amount;
      journal.push((Time.now(), p, #credited(amount)));
      assertBalancesIntegrity();
      true;
    };

    /// The handler will call icrc1_balance(S:P) to query the balance. It will detect if it has increased compared
    /// to the last balance seen. If it has increased then it will adjust the deposit (and hence the usable_balance).
    /// It will also schedule or trigger a “consolidation”, i.e. moving the newly deposited funds from S:P to S:0.
    /// Returns the newly detected deposit and total usable balance if success, otherwise null.
    public func notify(p : Principal) : async* ?(Nat, Int) {
      if (isFrozen() or not balanceRegistry.lock(p)) return null;
      let latestDeposit = try {
        await* loadDeposit(p);
      } catch err {
        balanceRegistry.unlock(p);
        throw err;
      };
      balanceRegistry.unlock(p);

      let oldDeposit = updateDeposit(p, latestDeposit);
      if (latestDeposit < oldDeposit) freezeTokenHandler("latestDeposit < oldDeposit on notify");

      if (latestDeposit > fee_) {
        // schedule consolidation for this p
        backlog.push(p, latestDeposit);
        // schedule a canister self-call to process the backlog
        // we need try-catch so that we don't trap if scheduling fails synchronously
        try ignore processBacklog() catch (_) {};
      };

      let balanceDelta = latestDeposit - oldDeposit : Nat;
      if (balanceDelta > 0) journal.push((Time.now(), p, #newDeposit(balanceDelta)));
      ?(balanceDelta, usableBalanceForPrincipal(p));
    };

    /// Attempts to transfer funds from the specified principal's
    /// subaccount to the main account after deducting the applicable fee.
    /// If the transfer is successful, the credited amount is updated in the balance registry and logged in the journal.
    /// If an error occurs during the transfer, it is recorded in the journal as a consolidation error.
    func processConsolidationTransfer(p : Principal, deposit : Nat) : async* ?{
      #Ok : Nat;
      #Err : ICRC1.TransferError or { #CallIcrc1LedgerError };
    } {
      if (deposit <= fee_) return null;
      let transferAmount = Int.abs(deposit - fee_);
      let transferResult = try {
        // Debug.print("transfer p " # debug_show p);
        // Debug.print("transfer p blob " # debug_show Mapping.toSubaccount(p));
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
          ignore balanceRegistry.set(
            p,
            func(info) {
              info.credit += transferAmount;
              true;
            },
          );
          journal.push((Time.now(), p, #consolidated({ deducted = deposit; credited = transferAmount })));
        };
        case (#Err err) {
          journal.push((Time.now(), p, #consolidationError(err)));
        };
      };
      ?transferResult;
    };

    /// Attempts to consolidate the funds for a particular principal.
    /// Fetches the latest balance, updates the deposit, and initiates the consolidation transfer process.
    func consolidate(p : Principal) : async* () {
      let latestDeposit = try { await* loadDeposit(p) } catch (err) {
        backlog.push(p, 0);
        return;
      };
      ignore updateDeposit(p, latestDeposit);
      let transferResult = await* processConsolidationTransfer(p, latestDeposit);
      // Debug.print("transferResult " # debug_show transferResult);
      switch (transferResult) {
        case (? #Err(#BadFee { expected_fee })) {
          journal.push((Time.now(), ownPrincipal, #feeUpdated({ old = fee_; new = expected_fee })));
          fee_ := expected_fee;
          let retryResult = await* processConsolidationTransfer(p, latestDeposit);
          Debug.print("retryResult " # debug_show retryResult);
          switch (retryResult) {
            case (? #Err _) backlog.push(p, latestDeposit);
            case (_) {};
          };
        };
        case (? #Err _) backlog.push(p, latestDeposit);
        case (_) {};
      };
    };

    /// Processes the backlog by consolidating funds for the first account in the backlog.
    /// Locks the balance info, invokes the consolidation process, and upon completion unlocks the balance info.
    public func processBacklog() : async () {
      if (isFrozen()) {
        return;
      };
      let (p, cb) = label L : (Principal, () -> ()) loop {
        let ?v = backlog.pop() else return;
        if (balanceRegistry.lock(v.0)) {
          break L v;
        } else {
          v.1 ();
        };
      };
      await* consolidate(p);
      cb();
      balanceRegistry.unlock(p);
      assertBalancesIntegrity();
    };

    /// Initiates a withdrawal by transferring tokens to another account.
    /// Returns ICRC1 transaction index and amount of transferred tokens (fee excluded).
    public func withdraw(to : ICRC1.Account, amount : Nat) : async* Result.Result<(transactionIndex : Nat, withdrawnAmount : Nat), ICRC1.TransferError or { #CallIcrc1LedgerError; #TooLowQuantity }> {

      let processTransfer = func() : async* {
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

      totalWithdrawn_ += amount;
      let callResult = await* processTransfer();

      switch (callResult) {
        case (#Ok txIdx) {
          journal.push((Time.now(), ownPrincipal, #withdraw({ to = to; amount = amount })));
          #ok(txIdx, amount - fee_);
        };
        case (#Err(#BadFee { expected_fee })) {
          journal.push((Time.now(), ownPrincipal, #feeUpdated({ old = fee_; new = expected_fee })));
          fee_ := expected_fee;
          let retryResult = await* processTransfer();
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

    /// Computes the usable balance for a given principal.
    func usableBalanceForPrincipal(p : Principal) : Int = Option.get(Option.map<InfoLock, Int>(balanceRegistry.get(p), usableBalance), 0);

    /// Computes the usable balance based on the balance info and the fee.
    func usableBalance(info : Info) : Int {
      let usableDeposit = Int.max(0, info.deposit - fee_);
      info.credit + usableDeposit;
    };

    /// Updates the specified principal's balance deposit. Returns old deposit.
    func updateDeposit(p : Principal, deposit : Nat) : Nat {
      var oldDeposit = 0;
      ignore balanceRegistry.set(
        p,
        func(info) {
          oldDeposit := info.deposit;
          info.deposit := deposit;
          true;
        },
      );
      depositedFunds_ += deposit;
      depositedFunds_ -= oldDeposit;
      oldDeposit;
    };

    /// Fetches actual deposit for a principal from the ICRC1 ledger.
    func loadDeposit(p : Principal) : async* Nat {
      await icrc1Ledger.icrc1_balance_of({
        owner = ownPrincipal;
        subaccount = ?Mapping.toSubaccount(p);
      });
    };

    /// Ensures the integrity of balances data.
    func assertBalancesIntegrity() : () {
      let usableSum = usableFunds();
      if (usableSum + fee_ * backlog.size() != backlog.funds() + creditedFunds()) {
        let values : [Text] = [
          "Balances integrity failed",
          Int.toText(usableSum),
          Nat.toText(fee_ * backlog.size()),
          Nat.toText(backlog.funds()),
          Int.toText(creditedFunds()),
        ];
        freezeTokenHandler(Text.join("; ", Iter.fromArray(values)));
      };
    };

    /// Serializes the token handler data.
    public func share() : StableData = (
      balanceRegistry.share(),
      backlog.share(),
      fee_,
      totalConsolidated_,
      totalWithdrawn_,
      depositedFunds_,
      (totalDebited, totalCredited),
      journal.share(),
    );

    /// Deserializes the token handler data.
    public func unshare(values : StableData) {
      balanceRegistry.unshare(values.0);
      backlog.unshare(values.1);
      fee_ := values.2;
      totalConsolidated_ := values.3;
      totalWithdrawn_ := values.4;
      depositedFunds_ := values.5;
      totalDebited := values.6.0;
      totalCredited := values.6.1;
      journal.unshare(values.7);
    };
  };

};
