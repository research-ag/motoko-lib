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

module TokenHandler {
  // https://github.com/dfinity/ICRC-1/blob/main/standards/ICRC-1/README.md
  module ICRC1Interface {
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
    public type Icrc1LedgerInterface = actor {
      icrc1_balance_of : (Account) -> async (Nat);
      icrc1_transfer : (TransferArgs) -> async ({
        #Ok : Nat;
        #Err : TransferError;
      });
    };
  };

  /// Convert Principal to ICRC1Interface.Subaccount
  public func toSubaccount(principal : Principal) : ICRC1Interface.Subaccount {
    // principal blob size can vary, but 29 bytes as most. We preserve it'subaccount size in result blob
    // and it'subaccount data itself so it can be deserialized back to principal
    let principalBytes = Blob.toArray(Principal.toBlob(principal));
    let principalSize = principalBytes.size();
    //assert principalSize <= 29;
    let subaccountData : [Nat8] = Array.tabulate(
      32,
      func(n : Nat) : Nat8 = if (n == 0) {
        Nat8.fromNat(principalSize);
      } else if (n <= principalSize) {
        principalBytes[n - 1];
      } else {
        0;
      },
    );
    Blob.fromArray(subaccountData);
  };

  /// Convert ICRC1Interface.Subaccount to Principal
  public func toPrincipal(subaccount : ICRC1Interface.Subaccount) : Principal {
    let subaccountBytes = Blob.toArray(subaccount);
    let principalSize = Nat8.toNat(subaccountBytes[0]);
    let principalData : [Nat8] = Array.tabulate(principalSize, func(n : Nat) : Nat8 = subaccountBytes[n + 1]);
    Principal.fromBlob(Blob.fromArray(principalData));
  };

  public type Info = {
    var deposit : Nat; // the balance that is in the subaccount associated with the user
    var credit : Int; // the balance that has been moved by S from S:P to S:0 (e.g. consolidated)
  };

  type InfoLock = Info and {
    var lock : Bool; // lock flag. For internal usage only
  };

  public class Map() {
    var tree : RBTree.RBTree<Principal, InfoLock> = RBTree.RBTree<Principal, InfoLock>(Principal.compare);

    func clean(principal : Principal, info : InfoLock) {
      if (info.deposit == 0 and info.credit == 0 and not info.lock) {
        tree.delete(principal);
      };
    };

    public func change(principal : Principal, f : (Info) -> Bool) : Bool {
      let ?info = tree.get(principal) else return false;
      let changed = f(info);
      if (changed) clean(principal, info);
      return changed;
    };

    public func set(principal : Principal, f : (Info) -> Bool) : Bool {
      let info = switch (tree.get(principal)) {
        case (?info) info;
        case (null) {
          let info = {
            var deposit = 0;
            var credit : Int = 0;
            var lock = false;
          };
          tree.put(principal, info);
          info;
        };
      };
      let changed = f(info);
      clean(principal, info);
      changed;
    };

    public func get(principal : Principal) : ?InfoLock = tree.get(principal);

    public func lock(principal : Principal) : Bool {
      let ?info = tree.get(principal) else Debug.trap("Lock not existent principal");
      if (info.lock) return false;
      info.lock := true;
      true;
    };

    public func unlock(principal : Principal) {
      let ?info = tree.get(principal) else Debug.trap("Unlock not existent principal");
      if (not info.lock) Debug.trap("releasing lock that isn't locked");
      info.lock := false;
    };

    public func share() : [(Principal, Info)] = Iter.toArray(
      Iter.filter<(Principal, InfoLock)>(
        tree.entries(),
        func((principal, info)) = info.credit != 0 or info.deposit != 0,
      )
    );

    /// deserialize tracking data
    public func unshare(values : [(Principal, Info)]) {
      tree := RBTree.RBTree<Principal, InfoLock>(Principal.compare);
      for ((principal, value) in values.vals()) {
        tree.put(
          principal,
          {
            var deposit = value.deposit;
            var credit = value.credit;
            var lock = false;
          },
        );
      };
    };
  };

  public class BackLog() {
    // a backlog of principals, waiting for consolidation
    var backlog : AssocList.AssocList<Principal, ()> = null;
    var size_ : Nat = 0;

    public func push(principal : Principal) {
      let (updated, prev) = AssocList.replace<Principal, ()>(backlog, principal, Principal.equal, ?());
      backlog := updated;
      switch (prev) {
        case (null) size_ += 1;
        case (_) {};
      };
    };

    public func remove(principal : Principal) {
      let (updated, prev) = AssocList.replace<Principal, ()>(backlog, principal, Principal.equal, null);
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
        case (?((principal, _), list)) {
          backlog := list;
          size_ -= 1;
          ?principal;
        };
      };
    };

    public func share() : [Principal] {
      func fold(list : AssocList.AssocList<Principal, ()>) : Buffer.Buffer<Principal> {
        let ?((principal, _), tail) = list else return Buffer.Buffer<Principal>(0);
        let a = fold(tail);
        a.add(principal);
        a;
      };

      Buffer.toArray(fold(backlog));
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

    let icrc1Ledger = actor (Principal.toText(icrc1LedgerPrincipal)) : ICRC1Interface.Icrc1LedgerInterface;

    // The map from principal to tracking info:
    // var tree : RBTree.RBTree<Principal, InfoLock> = RBTree.RBTree<Principal, InfoLock>(Principal.compare);

    let map : Map = Map();
    let backlog : BackLog = BackLog();

    // a backlog of principals, waiting for consolidation
    // var backlog : AssocList.AssocList<Principal, ()> = null;
    // var backlogSize : Nat = 0;

    /// query the usable balance
    public func balance(principal : Principal) : Nat = info(principal).usable_balance;

    /// query all tracked balances for debug purposes
    public func info(principal : Principal) : Info and {
      var usable_balance : Nat;
    } {
      let ?item = map.get(principal) else return {
        var deposit = 0;
        var credit = 0;
        var usable_balance = 0;
      };

      let usableDeposit = Int.max(0, item.deposit - fee);
      if (item.credit + usableDeposit < 0) {
        Debug.trap("item.credit + Int.max(0, item.deposit - fee) < 0");
      };

      {
        var deposit = item.deposit;
        var credit = item.credit;
        var usable_balance = Int.abs(item.credit + usableDeposit);
      };
    };

    /// retrieve the current size of consolidation backlog
    public func backlogSize() : Nat = backlog.size();

    /// deduct amount from P’s usable balance. Return false if the balance is insufficient.
    public func debit(principal : Principal, amount : Nat) : Bool {
      map.change(
        principal,
        func(info) {
          if (info.deposit + info.credit < amount) return false;
          info.credit -= amount;
          return true;
        },
      );
    };

    ///  add amount to P’s usable balance (the credit is created out of thin air)
    public func credit(principal : Principal, amount : Nat) : () {
      ignore map.set(
        principal,
        func(info) {
          info.credit += amount;
          true;
        },
      );
    };

    /// The handler will call icrc1_balance(S:P) to query the balance. It will detect if it has increased compared
    /// to the last balance seen. If it has increased then it will adjust the deposit (and hence the usable_balance).
    /// It will also schedule or trigger a “consolidation”, i.e. moving the newly deposited funds from S:P to S:0.
    public func notify(principal : Principal) : async* () {
      if (not map.lock(principal)) return;
      try {
        let latestBalance = await* loadBalance(principal);
        updateDeposit(principal, latestBalance);
        if (latestBalance > fee) {
          // schedule consolidation for this principal
          backlog.push(principal);
          ignore processBacklog();
        };
        map.unlock(principal);
      } catch err {
        map.unlock(principal);
        throw err;
      };
    };

    /// process first account from backlog
    public func processBacklog() : async* () {
      func consolidate(p : Principal) : async* () {
        let latestBalance = try { 
          await* loadBalance(p) 
        } catch (err) {
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

      let ?principal = backlog.pop() else return;
      if (not map.lock(principal)) return;
      await* consolidate(principal);
      map.unlock(principal);
    };

    /// serialize tracking data
    public func share() : ([(Principal, Info)], [Principal]) = (map.share(), backlog.share());

    /// deserialize tracking data
    public func unshare(values : ([(Principal, Info)], [Principal])) {
      map.unshare(values.0);
      backlog.unshare(values.1);
    };

    func updateDeposit(principal : Principal, deposit : Nat) : () {
      ignore map.set(principal, func(info) { info.deposit := deposit; true });
    };

    func loadBalance(principal : Principal) : async* Nat {
      await icrc1Ledger.icrc1_balance_of({
        owner = ownPrincipal;
        subaccount = ?toSubaccount(principal);
      });
    };
  };
};
