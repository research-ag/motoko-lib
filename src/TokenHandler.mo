import R "mo:base/Result";
import Cycles "mo:base/ExperimentalCycles";
import RBTree "mo:base/RBTree";
import Principal "mo:base/Principal";
import Iter "mo:base/Iter";
import Option "mo:base/Option";
import Debug "mo:base/Debug";
import Int "mo:base/Int";
import AssocList "mo:base/AssocList";
import Blob "mo:base/Blob";
import Nat8 "mo:base/Nat8";
import Array "mo:base/Array";
import Buffer "mo:base/Buffer";
import List "mo:base/List";

module TokenHandler {
  // https://github.com/dfinity/ICRC-1/blob/main/standards/ICRC-1/README.md
  module ICRC1 {
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
    
    let a = Array.tabulate<Nat8>(32, func (i : Nat) : Nat8 {
      if (i + size < 31) {
        0;
      } else 
      if (i + size == 31) {
        Nat8.fromNat(size)
      } else {
        bytes[i + size - 32];
      };
    });
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

  public type Info = {
    var deposit : Nat; // the balance that is in the subaccount associated with the user
    var credit : Int; // the balance that has been moved by S from S:P to S:0 (e.g. consolidated)
  };

  type InfoLock = Info and {
    var lock : Bool; // lock flag. For internal usage only
  };

  class Map() {
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

    public func set(p : Principal, f : (Info) -> Bool) : Bool {
      let info = switch (tree.get(p)) {
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
      let changed = f(info);
      clean(p, info);
      changed;
    };

    public func get(p : Principal) : ?InfoLock = tree.get(p);

    public func lock(p : Principal) : Bool {
      let ?info = tree.get(p) else Debug.trap("Lock not existent p");
      if (info.lock) return false;
      info.lock := true;
      true;
    };

    public func unlock(p : Principal) {
      let ?info = tree.get(p) else Debug.trap("Unlock not existent p");
      if (not info.lock) Debug.trap("releasing lock that isn't locked");
      info.lock := false;
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
  };

  class BackLog() {
    // a backlog of principals, waiting for consolidation
    var backlog : AssocList.AssocList<Principal, ()> = null;
    var size_ : Nat = 0;

    public func push(p : Principal) {
      let (updated, prev) = AssocList.replace<Principal, ()>(backlog, p, Principal.equal, ?());
      backlog := updated;
      switch (prev) {
        case (null) size_ += 1;
        case (_) {};
      };
    };

    public func remove(p : Principal) {
      let (updated, prev) = AssocList.replace<Principal, ()>(backlog, p, Principal.equal, null);
      backlog := updated;
      switch (prev) {
        case (null) {};
        case (_) size_ -= 1;
      };
    };

    /// retrieve the current size of consolidation backlog
    public func size() : Nat = size_;

    public func pop() : ?Principal {
      switch (backlog) {
        case (null) null;
        case (?((p, _), list)) {
          backlog := list;
          size_ -= 1;
          ?p;
        };
      };
    };

    public func share() : [Principal] {
      let array = Array.init<Principal>(size_,Principal.fromText("2vxsx-fae"));

      var i = 0;
      List.iterate(backlog, func ((x, _) : (Principal, ())) {
        array[i] := x;
        i += 1;
      });

      Array.freeze(array);
    };

    public func unshare(array : [Principal]) {
      backlog := null;
      size_ := array.size();
      var i = size_;
      while (i > 0) {
        backlog := ?((array[i - 1], ()), backlog);
        i -= 1;
      };
    };
  };

  public class TokenHandler(
    icrc1LedgerPrincipal : Principal,
    ownPrincipal : Principal,
    fee : Nat,
  ) {

    let icrc1Ledger = actor (Principal.toText(icrc1LedgerPrincipal)) : ICRC1.ICRC1Ledger;

    // The map from p to tracking info:
    // var tree : RBTree.RBTree<Principal, InfoLock> = RBTree.RBTree<Principal, InfoLock>(Principal.compare);

    let map : Map = Map();
    let backlog : BackLog = BackLog();

    // a backlog of principals, waiting for consolidation
    // var backlog : AssocList.AssocList<Principal, ()> = null;
    // var backlogSize : Nat = 0;

    /// query the usable balance
    public func balance(p : Principal) : Nat = info(p).usable_balance;

    /// query all tracked balances for debug purposes
    public func info(p : Principal) : Info and {
      var usable_balance : Nat;
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

    /// retrieve the current size of consolidation backlog
    public func backlogSize() : Nat = backlog.size();

    /// deduct amount from P’s usable balance. Return false if the balance is insufficient.
    public func debit(p : Principal, amount : Nat) : Bool {
      map.change(
        p,
        func(info) {
          if (usableBalance(info) < amount) return false;
          info.credit -= amount;
          return true;
        },
      );
    };

    ///  add amount to P’s usable balance (the credit is created out of thin air)
    public func credit(p : Principal, amount : Nat) : () {
      ignore map.set(
        p,
        func(info) {
          info.credit += amount;
          true;
        },
      );
    };

    /// The handler will call icrc1_balance(S:P) to query the balance. It will detect if it has increased compared
    /// to the last balance seen. If it has increased then it will adjust the deposit (and hence the usable_balance).
    /// It will also schedule or trigger a “consolidation”, i.e. moving the newly deposited funds from S:P to S:0.
    public func notify(p : Principal) : async* () {
      if (not map.lock(p)) return;
      try {
        let latestBalance = await* loadBalance(p);
        updateDeposit(p, latestBalance);
        if (latestBalance > fee) {
          // schedule consolidation for this p
          backlog.push(p);
          ignore processBacklog();
        };
        map.unlock(p);
      } catch err {
        map.unlock(p);
        throw err;
      };
    };

    /// process first account from backlog
    public func processBacklog() : async* () {
      func consolidate(p : Principal) : async* () {
        let latestBalance = try { await* loadBalance(p) } catch (err) {
          backlog.push(p);
          return;
        };
        if (latestBalance <= fee) return;

        updateDeposit(p, latestBalance);

        let transferResult = try {
          await icrc1Ledger.icrc1_transfer({
            from_subaccount = ?toSubaccount(p);
            to = { owner = ownPrincipal; subaccount = null };
            amount = latestBalance - fee;
            fee = null;
            memo = null;
            created_at_time = null;
          });
        } catch (err) {
          #Err(#CallIcrc1LedgerError);
        };

        switch (transferResult) {
          case (#Ok _) {
            updateDeposit(p, 0);
            credit(p, latestBalance - fee);
          };
          case (#Err _) {
            backlog.push(p);
          };
        };
      };

      let ?p = backlog.pop() else return;
      if (not map.lock(p)) return;
      await* consolidate(p);
      map.unlock(p);
    };

    /// serialize tracking data
    public func share() : ([(Principal, Info)], [Principal]) = (map.share(), backlog.share());

    /// deserialize tracking data
    public func unshare(values : ([(Principal, Info)], [Principal])) {
      map.unshare(values.0);
      backlog.unshare(values.1);
    };

    func usableBalance(item : Info) : Nat {
      let usableDeposit = Int.max(0, item.deposit - fee);
      if (item.credit + usableDeposit < 0) {
        Debug.trap("item.credit + Int.max(0, item.deposit - fee) < 0");
      };
      Int.abs(item.credit + usableDeposit);
    };

    func updateDeposit(p : Principal, deposit : Nat) : () {
      ignore map.set(p, func(info) { info.deposit := deposit; true });
    };

    func loadBalance(p : Principal) : async* Nat {
      await icrc1Ledger.icrc1_balance_of({
        owner = ownPrincipal;
        subaccount = ?toSubaccount(p);
      });
    };
  };
};
