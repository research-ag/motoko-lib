import RBTree "mo:base/RBTree";
import Principal "mo:base/Principal";
import Iter "mo:base/Iter";
import Option "mo:base/Option";
import Int "mo:base/Int";
import AssocList "mo:base/AssocList";
import Blob "mo:base/Blob";
import Nat8 "mo:base/Nat8";
import Array "mo:base/Array";
import List "mo:base/List";
import Time = "mo:base/Time";
import Nat = "mo:base/Nat";
import Text = "mo:base/Text";
import Result "mo:base/Result";

import CircularBuffer "CircularBuffer";

module TokenHandler {
  // https://github.com/dfinity/ICRC-1/blob/main/standards/ICRC-1/README.md
  public module ICRC1 {
    public type Subaccount = Blob;
    public type Account = { owner : Principal; subaccount : ?Subaccount };
    public type TransferArgs = {
      from_subaccount : ?Subaccount;
      to : Account;
      amount : Nat;
      fee : ?Nat;
      memo : ?Blob;
      created_at_time : ?Nat64;
    };
    public type TransferError = {
      #BadFee : { expected_fee : Nat };
      #BadBurn : { min_burn_amount : Nat };
      #InsufficientFunds : { balance : Nat };
      #TooOld;
      #CreatedInFuture : { ledger_time : Nat64 };
      #Duplicate : { duplicate_of : Nat };
      #TemporarilyUnavailable;
      #GenericError : { error_code : Nat; message : Text };
    };
    public type ICRC1Ledger = actor {
      icrc1_balance_of : (Account) -> async (Nat);
      icrc1_transfer : (TransferArgs) -> async ({
        #Ok : Nat;
        #Err : TransferError;
      });
    };
  };

  /// Convert Principal to ICRC1.Subaccount
  public func toSubaccount(p : Principal) : ICRC1.Subaccount {
    // p blob size can vary, but 29 bytes as most. We preserve it'subaccount size in result blob
    // and it'subaccount data itself so it can be deserialized back to p
    let bytes = Blob.toArray(Principal.toBlob(p));
    let size = bytes.size();

    assert size <= 29;

    let a = Array.tabulate<Nat8>(
      32,
      func(i : Nat) : Nat8 {
        if (i + size < 31) {
          0;
        } else if (i + size == 31) {
          Nat8.fromNat(size);
        } else {
          bytes[i + size - 32];
        };
      },
    );
    Blob.fromArray(a);
  };

  /// Convert ICRC1.Subaccount to Principal
  public func toPrincipal(subaccount : ICRC1.Subaccount) : ?Principal {
    func first(a : [Nat8]) : Nat {
      var i = 0;
      while (i < 32) {
        if (bytes[i] != 0) {
          return i;
        };
        i += 1;
      };
      i;
    };

    let bytes = Blob.toArray(subaccount);
    assert bytes.size() == 32;

    let size_index = first(bytes);
    if (size_index == 32) return null;

    let size = Nat8.toNat(bytes[size_index]);
    if (size_index + size != 31) return null;

    ?Principal.fromBlob(Blob.fromArray(Array.tabulate(size, func(i : Nat) : Nat8 = bytes[i + 1 + size_index])));
  };

  public func defaultHandlerStableData() : StableData = ([], (0, []), 0, 0, 0, (0, 0), ([var], 0, 0));

  public type Info = {
    var deposit : Nat; // the balance that is in the subaccount associated with the user
    var credit : Int; // the balance that has been moved by S from S:P to S:0 (e.g. consolidated)
  };

  type InfoLock = Info and {
    var lock : Bool; // lock flag. For internal usage only
  };

  class Map(assertionFailureCallback : (text : Text) -> ()) {
    var tree : RBTree.RBTree<Principal, InfoLock> = RBTree.RBTree<Principal, InfoLock>(Principal.compare);

    func clean(p : Principal, info : InfoLock) {
      if (info.deposit == 0 and info.credit == 0 and not info.lock) {
        tree.delete(p);
      };
    };

    public func change(p : Principal, f : (Info) -> Bool) : Bool {
      let ?info = tree.get(p) else return false;
      let changed = f(info);
      if (changed) clean(p, info);
      return changed;
    };

    public func getOrCreate(p : Principal) : InfoLock = switch (tree.get(p)) {
      case (?info) info;
      case (null) {
        let info = {
          var deposit = 0;
          var credit : Int = 0;
          var lock = false;
        };
        tree.put(p, info);
        info;
      };
    };

    public func set(p : Principal, f : (Info) -> Bool) : Bool {
      let info = getOrCreate(p);
      let changed = f(info);
      clean(p, info);
      changed;
    };

    public func get(p : Principal) : ?InfoLock = tree.get(p);

    public func lock(p : Principal) : Bool {
      let info = getOrCreate(p);
      if (info.lock) return false;
      info.lock := true;
      true;
    };

    public func unlock(p : Principal) = switch (tree.get(p)) {
      case (null) {
        assertionFailureCallback("Unlock not existent p");
      };
      case (?info) {
        if (not info.lock) assertionFailureCallback("releasing lock that isn't locked");
        info.lock := false;
      };
    };

    public func share() : [(Principal, Info)] = Iter.toArray(
      Iter.filter<(Principal, InfoLock)>(
        tree.entries(),
        func((p, info)) = info.credit != 0 or info.deposit != 0,
      )
    );

    /// deserialize tracking data
    public func unshare(values : [(Principal, Info)]) {
      tree := RBTree.RBTree<Principal, InfoLock>(Principal.compare);
      for ((p, value) in values.vals()) {
        tree.put(
          p,
          {
            var deposit = value.deposit;
            var credit = value.credit;
            var lock = false;
          },
        );
      };
    };

    public func items() : Iter.Iter<InfoLock> = Iter.map<(Principal, InfoLock), InfoLock>(
      tree.entries(),
      func(entry : (Principal, InfoLock)) : InfoLock = entry.1,
    );
  };

  class BackLog() {
    // a backlog of principals, waiting for consolidation
    var backlog : AssocList.AssocList<Principal, Nat> = null;
    var size_ : Nat = 0;
    var funds_ : Nat = 0;

    public func push(p : Principal, amount : Nat) {
      let (updated, prev) = AssocList.replace<Principal, Nat>(backlog, p, Principal.equal, ?amount);
      funds_ += amount;
      backlog := updated;
      switch (prev) {
        case (null) size_ += 1;
        case (?prevAmount) {
          funds_ -= prevAmount;
        };
      };
    };

    public func remove(p : Principal) {
      let (updated, prev) = AssocList.replace<Principal, Nat>(backlog, p, Principal.equal, null);
      backlog := updated;
      switch (prev) {
        case (null) {};
        case (?prevAmount) {
          size_ -= 1;
          funds_ -= prevAmount;
        };
      };
    };

    /// retrieve the current size of consolidation backlog
    public func size() : Nat = size_;

    /// retrieve the estimated sum of all balances in the backlog
    public func funds() : Nat = funds_;

    public func pop() : ?Principal {
      switch (backlog) {
        case (null) null;
        case (?((p, amount), list)) {
          backlog := list;
          size_ -= 1;
          funds_ -= amount;
          ?p;
        };
      };
    };

    public func share() : (Nat, [(Principal, Nat)]) {
      (funds_, List.toArray(backlog));
    };

    public func unshare(data : (Nat, [(Principal, Nat)])) {
      backlog := null;
      funds_ := data.0;
      size_ := data.1.size();
      var i = size_;
      while (i > 0) {
        backlog := ?(data.1 [i - 1], backlog);
        i -= 1;
      };
    };
  };

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
    [(Principal, Info)], // map
    (Nat, [(Principal, Nat)]), // backlog
    Nat, // totalConsolidated
    Nat, // totalWithdrawn
    Nat, // depositedFunds_
    (Nat, Nat), // totalDebited, totalCredited
    ([var ?JournalRecord], Nat, Nat) // journal
  );

  public class TokenHandler(
    icrc1LedgerPrincipal_ : Principal,
    ownPrincipal : Principal,
    journalSize : Nat,
  ) {

    let icrc1Ledger = actor (Principal.toText(icrc1LedgerPrincipal_)) : ICRC1.ICRC1Ledger;

    /// if some unexpected error happened, this flag turns true and handler stops doing anything until recreated
    var isFrozen_ : Bool = false;
    func freezeTokenHandler(errorText : Text) : () {
      isFrozen_ := true;
      journal.push((Time.now(), ownPrincipal, #error(errorText)));
    };

    let backlog : BackLog = BackLog();
    var journal : CircularBuffer.CircularBuffer<JournalRecord> = CircularBuffer.CircularBuffer<JournalRecord>(journalSize);
    var totalConsolidated_ : Nat = 0;
    var totalWithdrawn_ : Nat = 0;
    let map : Map = Map(freezeTokenHandler);
    var fee_ : Nat = 0;
    var totalDebited : Nat = 0;
    var totalCredited : Nat = 0;
    var depositedFunds_ : Nat = 0;

    /// query the fee
    public func getFee() : Nat = fee_;

    /// query the usable balance
    public func balance(p : Principal) : Int = info(p).usable_balance;

    /// query all tracked balances for debug purposes
    public func info(p : Principal) : Info and {
      var usable_balance : Int;
    } {
      let ?item = map.get(p) else return {
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

    /// query journal for debug purposes. Returns:
    /// 1) array of all items in order, starting from the oldest record in journal, but no earlier than "startFrom" if provided
    /// 2) the index of next upcoming journal log. Use this value as "startFrom" in your next journal query to fetch next entries
    public func queryJournal(startFrom : ?Nat) : ([JournalRecord], Nat) = (
      Iter.toArray(
        journal.slice(
          Int.abs(Int.max(Option.get(startFrom, 0), journal.pushesAmount() - journalSize)),
          journal.pushesAmount(),
        )
      ),
      journal.pushesAmount(),
    );

    /// retrieve the ICRC1 ledger principal
    public func icrc1LedgerPrincipal() : Principal = icrc1LedgerPrincipal_;

    /// retrieve the current freeze state
    public func isFrozen() : Bool = isFrozen_;

    /// retrieve the current size of consolidation backlog
    public func backlogSize() : Nat = backlog.size();

    /// retrieve the sum of all successful consolidations
    public func totalConsolidated() : Nat = totalConsolidated_;

    /// retrieve the sum of all deductions from main account of the token handler
    public func totalWithdrawn() : Nat = totalWithdrawn_;

    /// retrieve the calculated balance of main account of the token handler
    public func consolidatedFunds() : Nat = totalConsolidated_ - totalWithdrawn_;

    /// retrieve the estimated sum of all balances in the backlog
    public func backlogFunds() : Nat = backlog.funds();

    /// retrieve the sum of all deposits. This value is nearly the same as backlogFunds(), but includes
    /// entries, which could not be added to backlog, for instance when balance less than fee.
    /// It's always >= backlogFunds()
    public func depositedFunds() : Nat = depositedFunds_;

    /// retrieve the sum of all user credit balances.
    /// It can be negative because user can spend deposited funds before consolidation
    public func creditedFunds() : Int = totalConsolidated_ + totalCredited - totalDebited;

    /// retrieve the sum of all user usable balances
    public func usableFunds() : Int {
      // it's tricky to cache it because of excluding deposits, smaller than fee, from the usable balance.
      var usableSum : Int = 0;
      for (info in map.items()) {
        usableSum += usableBalance(info);
      };
      usableSum;
    };

    /// deduct amount from P’s usable balance. Return false if the balance is insufficient.
    public func debit(p : Principal, amount : Nat) : Bool {
      if (isFrozen()) {
        return false;
      };
      let result = map.change(
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

    ///  add amount to P’s usable balance (the credit is created out of thin air)
    public func credit(p : Principal, amount : Nat) : Bool {
      if (isFrozen()) {
        return false;
      };
      ignore map.set(
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
    /// Returns the newly detected deposit and total usable balance if success, otherwise null
    public func notify(p : Principal) : async* ?(Nat, Int) {
      if (isFrozen() or not map.lock(p)) return null;
      let latestBalance = try {
        await* loadBalance(p);
      } catch err {
        map.unlock(p);
        throw err;
      };
      map.unlock(p);

      let oldBalance = updateDeposit(p, latestBalance);
      if (latestBalance < oldBalance) freezeTokenHandler("latestBalance < oldBalance on notify");

      if (latestBalance > fee_) {
        // schedule consolidation for this p
        backlog.push(p, latestBalance);
        // schedule a canister self-call to process the backlog
        // we need try-catch so that we don't trap if scheduling fails synchronously
        try ignore processBacklog() catch (_) {};
      };

      let balanceDelta = latestBalance - oldBalance : Nat;
      if (balanceDelta > 0) journal.push((Time.now(), p, #newDeposit(balanceDelta)));
      ?(balanceDelta, usableBalanceForPrincipal(p));
    };

    /// process first account from backlog
    public func processBacklog() : async () {
      func consolidate(p : Principal) : async* () {
        func processConsolidationTransfer() : async* ?{
          #Ok : Nat;
          #Err : ICRC1.TransferError or { #CallIcrc1LedgerError };
        } {
          if (latestBalance <= fee_) return null;
          let transferAmount = Int.abs(latestBalance - fee_);
          let transferResult = try {
            await icrc1Ledger.icrc1_transfer({
              from_subaccount = ?toSubaccount(p);
              to = { owner = ownPrincipal; subaccount = null };
              amount = transferAmount;
              fee = ?fee_;
              memo = null;
              created_at_time = null;
            });
          } catch (err) {
            #Err(#CallIcrc1LedgerError);
          };
          switch (transferResult) {
            case (#Ok _) {
              ignore updateDeposit(p, 0);
              totalConsolidated_ += transferAmount;
              ignore map.set(
                p,
                func(info) {
                  info.credit += transferAmount;
                  true;
                },
              );
              journal.push((Time.now(), p, #consolidated({ deducted = latestBalance; credited = transferAmount })));
            };
            case (#Err err) {
              journal.push((Time.now(), p, #consolidationError(err)));
            };
          };
          ?transferResult;
        };

        let latestBalance = try { await* loadBalance(p) } catch (err) {
          backlog.push(p, 0);
          return;
        };
        ignore updateDeposit(p, latestBalance);
        let transferResult = await* processConsolidationTransfer();
        switch (transferResult) {
          case (? #Err(#BadFee { expected_fee })) {
            journal.push((Time.now(), ownPrincipal, #feeUpdated({ old = fee_; new = expected_fee })));
            fee_ := expected_fee;
            let retryResult = await* processConsolidationTransfer();
            switch (retryResult) {
              case (? #Err err) backlog.push(p, latestBalance);
              case (_) {};
            };
          };
          case (? #Err _) backlog.push(p, latestBalance);
          case (_) {};
        };
      };

      if (isFrozen()) {
        return;
      };
      let ?p = backlog.pop() else return;
      if (not map.lock(p)) return;
      await* consolidate(p);
      map.unlock(p);
      assertBalancesIntegrity();
    };

    /// send tokens to another account, return ICRC1 transaction index and amount of transferred tokens (fee excluded)
    public func withdraw(to : ICRC1.Account, amount : Nat) : async* Result.Result<(transactionIndex : Nat, withdrawnAmount : Nat), ICRC1.TransferError or { #CallIcrc1LedgerError; #TooLowQuantity }> {
      let transfer = func() : async* {
        #Ok : Nat;
        #Err : ICRC1.TransferError or { #CallIcrc1LedgerError; #TooLowQuantity };
      } {
        if (amount <= fee_) return #Err(#TooLowQuantity);
        let callResult = try {
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
      let callResult = await* transfer();
      switch (callResult) {
        case (#Ok txIdx) {
          journal.push((Time.now(), ownPrincipal, #withdraw({ to = to; amount = amount })));
          #ok(txIdx, amount - fee_);
        };
        case (#Err(#BadFee { expected_fee })) {
          journal.push((Time.now(), ownPrincipal, #feeUpdated({ old = fee_; new = expected_fee })));
          fee_ := expected_fee;
          let retryResult = await* transfer();
          switch (retryResult) {
            case (#Ok txIdx) {
              totalWithdrawn_ += amount;
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

    /// serialize tracking data
    public func share() : StableData = (
      map.share(),
      backlog.share(),
      totalConsolidated_,
      totalWithdrawn_,
      depositedFunds_,
      (totalDebited, totalCredited),
      journal.share(),
    );

    /// deserialize tracking data
    public func unshare(values : StableData) {
      map.unshare(values.0);
      backlog.unshare(values.1);
      totalConsolidated_ := values.2;
      totalWithdrawn_ := values.3;
      depositedFunds_ := values.4;
      totalDebited := values.5.0;
      totalCredited := values.5.1;
      journal.unshare(values.6);
    };

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

    func usableBalanceForPrincipal(p : Principal) : Int = Option.get(Option.map<InfoLock, Int>(map.get(p), usableBalance), 0);

    func usableBalance(item : Info) : Int {
      let usableDeposit = Int.max(0, item.deposit - fee_);
      item.credit + usableDeposit;
    };

    // returns old deposit
    func updateDeposit(p : Principal, deposit : Nat) : Nat {
      var oldDeposit = 0;
      ignore map.set(
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

    func loadBalance(p : Principal) : async* Nat {
      await icrc1Ledger.icrc1_balance_of({
        owner = ownPrincipal;
        subaccount = ?toSubaccount(p);
      });
    };
  };
};
