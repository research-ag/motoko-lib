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

module TokenHandler {
  // https://github.com/dfinity/ICRC-1/blob/main/standards/ICRC-1/README.md
  public module ICRC1Interface {
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

  public type TrackingInfo = {
    deposit_balance : Nat;
    credit_balance : Int;
  };

  type TrackingInfoLock = {
    var deposit_balance : Nat; // the balance that is in the subaccount associated with the user
    var credit_balance : Int; // the balance that has been moved by S from S:P to S:0 (e.g. consolidated)
    var lock : Bool; // lock flag. For internal usage only
  };

  public class TokenHandler(
    icrc1LedgerPrincipal : Principal,
    ownPrincipal : Principal,
  ) {
    let icrc1Ledger = actor (Principal.toText(icrc1LedgerPrincipal)) : ICRC1Interface.Icrc1LedgerInterface;

    // a backlog of principals, with failed account consolidation
    var consolidationBacklog : AssocList.AssocList<Principal, ()> = null;

    // The map from principal to tracking info:
    var tree : RBTree.RBTree<Principal, TrackingInfoLock> = RBTree.RBTree<Principal, TrackingInfoLock>(Principal.compare);

    func clean(principal : Principal, info : TrackingInfoLock) {
      if (info.deposit_balance == 0 and info.credit_balance == 0 and not info.lock) {
        tree.delete(principal);
      };
    };

    func change(principal : Principal, f : (TrackingInfoLock) -> Bool) : Bool {
      let ?info = tree.get(principal) else return false;
      let changed = f(info);
      if (changed) clean(principal, info);
      return changed;
    };

    func set(principal : Principal, f : (TrackingInfoLock) -> Bool) : Bool {
      let info = switch (tree.get(principal)) {
        case (?info) info;
        case (null) {
          let info = {
            var deposit_balance = 0;
            var credit_balance : Int = 0;
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

    /// The handler will call icrc1_balance(S:P) to query the balance. It will detect if it has increased compared
    /// to the last balance seen. If it has increased then it will adjust the deposit_balance (and hence the usable_balance).
    /// It will also schedule or trigger a “consolidation”, i.e. moving the newly deposited funds from S:P to S:0.
    /// Note: concurrent notify() for the same P have to be handled with locks.
    public func notify(principal : Principal) : async* () {
      func obtainLock(principal : Principal) : Bool {
        set(
          principal,
          func(info) {
            if (info.lock) return false;
            info.lock := true;
            true;
          },
        );
      };

      func releaseLock(principal : Principal) {
        let changed = change(
          principal,
          func(info) {
            if (not info.lock) return false;
            info.lock := false;
            true;
          },
        );
        // while testing we should trap here
        if (not changed) Debug.trap("releasing lock that isn't locked");
      };

      func updateDeposit(principal : Principal, deposit_balance : Nat) : () {
        ignore set(principal, func(info) { info.deposit_balance := deposit_balance; true });
      };

      func consolidateAccount(principal : Principal) : async* () {
        var latestBalance = 0;
        try {
          latestBalance := await icrc1Ledger.icrc1_balance_of({
            owner = ownPrincipal;
            subaccount = ?toSubaccount(principal);
          });
        } catch (err) {
          throw err;
        };
        updateDeposit(principal, latestBalance);
        if (latestBalance != 0) {
          let transferResult = try {
            await icrc1Ledger.icrc1_transfer({
              from_subaccount = ?toSubaccount(principal);
              to = { owner = ownPrincipal; subaccount = null };
              amount = latestBalance;
              fee = null;
              memo = null;
              created_at_time = null;
            });
          } catch (err) {
            #Err(#CallIcrc1LedgerError);
          };
          switch (transferResult) {
            case (#Ok _) {
              credit(principal, latestBalance);
              updateDeposit(principal, 0);
            };
            case (#Err _) {
              updateDeposit(principal, latestBalance);
              consolidationBacklog := AssocList.replace<Principal, ()>(consolidationBacklog, principal, Principal.equal, ?()).0;
            };
          };
        };
      };

      if (not obtainLock(principal)) return;
      try {
        await* consolidateAccount(principal);
      } catch err {
        releaseLock(principal);
        throw err;
      };
      releaseLock(principal);
    };

    /// deduct amount from P’s usable balance. Return false if the balance is insufficient.
    public func debit(principal : Principal, amount : Nat) : Bool {
      change(
        principal,
        func(info) {
          if (info.deposit_balance + info.credit_balance < amount) return false;
          info.credit_balance -= amount;
          return true;
        },
      );
    };

    ///  add amount to P’s usable balance (the credit is created out of thin air)
    public func credit(principal : Principal, amount : Nat) : () {
      ignore set(
        principal,
        func(info) {
          info.credit_balance += amount;
          true;
        },
      );
    };

    /// query the usable balance
    public func balance(principal : Principal) : Nat {
      info(principal).usable_balance;
    };

    /// query all tracked balances for debug purposes
    public func info(principal : Principal) : TrackingInfo and {
      usable_balance : Nat;
    } {
      let ?item = tree.get(principal) else return {
        deposit_balance = 0;
        credit_balance = 0;
        usable_balance = 0;
      };
      if (item.deposit_balance + item.credit_balance < 0) {
        Debug.trap("item.deposit_balance + item.credit_balance < 0");
      };
      {
        deposit_balance = item.deposit_balance;
        credit_balance = item.credit_balance;
        usable_balance = Int.abs(item.deposit_balance + item.credit_balance);
      };
    };

    /// process first account, which was failed to consolidate last time
    public func processConsolidationBacklog() : async () = async switch (consolidationBacklog) {
      case (null) return;
      case (?((principal, _), list)) {
        consolidationBacklog := list;
        await* notify(principal);
      };
    };

    /// serialize tracking data
    public func share() : [(Principal, TrackingInfo)] = Iter.toArray(
      Iter.map<(Principal, TrackingInfoLock), (Principal, TrackingInfo)>(
        Iter.filter<(Principal, TrackingInfoLock)>(
          tree.entries(),
          func((principal, info)) = info.credit_balance != 0 or info.deposit_balance != 0,
        ),
        func((principal, info)) = (principal, { deposit_balance = info.deposit_balance; credit_balance = info.credit_balance }),
      )
    );

    /// deserialize tracking data
    public func unshare(values : [(Principal, TrackingInfo)]) {
      tree := RBTree.RBTree<Principal, TrackingInfoLock>(Principal.compare);
      for ((principal, value) in values.vals()) {
        tree.put(
          principal,
          {
            var deposit_balance = value.deposit_balance;
            var credit_balance = value.credit_balance;
            var lock = false;
          },
        );
      };
    };

    /// Convert Principal to ICRC1Interface.Subaccount
    public func toSubaccount(principal : Principal) : ICRC1Interface.Subaccount {
      // principal blob size can vary, but 29 bytes as most. We preserve it'subaccount size in result blob
      // and it'subaccount data itself so it can be deserialized back to principal
      let principalBytes = Blob.toArray(Principal.toBlob(principal));
      let principalSize = principalBytes.size();
      assert principalSize <= 29;
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
  };
};
