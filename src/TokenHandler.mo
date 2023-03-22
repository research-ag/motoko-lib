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

// https://github.com/dfinity/ICRC-1/blob/main/standards/ICRC-1/README.md
module Icrc1Interface {
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

module TokenHandler {
  public type StableTrackingInfo = {
    deposit_balance : Nat;
    credit_balance : Int;
  };
  public type Icrc1LedgerInterface = Icrc1Interface.Icrc1LedgerInterface;

  type TrackingInfo = {
    var deposit_balance : Nat; // the balance that is in the subaccount associated with the user
    var credit_balance : Int; // the balance that has been moved by S from S:P to S:0 (e.g. consolidated)
    var consolidationLock : Bool; // lock flag. For internal usage only
  };

  public class TokenHandler(
    icrc1LedgerPrincipal : Principal,
    ownPrincipal : Principal,
  ) {

    /// The handler will call icrc1_balance(S:P) to query the balance. It will detect if it has increased compared 
    /// to the last balance seen. If it has increased then it will adjust the deposit_balance (and hence the usable_balance). 
    /// It will also schedule or trigger a “consolidation”, i.e. moving the newly deposited funds from S:P to S:0. 
    /// Note: concurrent notify() for the same P have to be handled with locks.
    public func notify(p : Principal) : async* () {
      await* consolidateAccount(p);
    };

    /// deduct amount from P’s usable balance. Return false if the balance is insufficient.
    public func debit(p : Principal, amount : Nat) : Bool {
      let ?info = tree.get(p) else return false;
      if (info.deposit_balance + info.credit_balance < amount) {
        return false;
      };
      info.credit_balance -= amount;
      cleanTrackingInfoIfZero(info, p);
      return true;
    };

    ///  add amount to P’s usable balance (the credit is created out of thin air)
    public func credit(p : Principal, amount : Nat) : () {
      let info = getOrCreateTrackingInfo(p);
      info.credit_balance += amount;
      cleanTrackingInfoIfZero(info, p);
    };

    /// query the usable balance
    public func balance(p : Principal) : Nat {
      let ?item = tree.get(p) else return 0;
      let balance = item.deposit_balance + item.credit_balance;
      if (balance >= 0) {
        return Int.abs(balance);
      } else {
        Debug.trap("item.deposit_balance + item.credit_balance < 0");
      }
    };

    /// query all tracked balances for debug purposes
    public func info(p : Principal) : StableTrackingInfo {
      let ?item = tree.get(p) else return {
        deposit_balance = 0;
        credit_balance = 0;
        usable_balance = 0;
      };
      {
        deposit_balance = item.deposit_balance;
        credit_balance = item.credit_balance;
      };
    };

    /// process first account, which was failed to consolidate last time
    public func processConsolidationBacklog() : async () = async switch (consolidationBacklog) {
      case (null) return;
      case (?((p, _), list)) {
        consolidationBacklog := list;
        await* consolidateAccount(p);
      };
    };

    /// serialize tracking data
    public func share() : [(Principal, StableTrackingInfo)] = Iter.toArray(
      Iter.map<(Principal, TrackingInfo), (Principal, StableTrackingInfo)>(
        Iter.filter<(Principal, TrackingInfo)>(
          tree.entries(),
          func((p, ti)) = ti.credit_balance != 0 or ti.deposit_balance != 0,
        ),
        func((p, ti)) = (p, { deposit_balance = ti.deposit_balance; credit_balance = ti.credit_balance }),
      )
    );

    /// deserialize tracking data
    public func unshare(values : [(Principal, StableTrackingInfo)]) {
      tree := RBTree.RBTree<Principal, TrackingInfo>(Principal.compare);
      for ((p, value) in values.vals()) {
        tree.put(
          p,
          {
            var deposit_balance = value.deposit_balance;
            var credit_balance = value.credit_balance;
            var consolidationLock = false;
          },
        );
      };
    };

    public func principalToSubaccount(p : Principal) : Icrc1Interface.Subaccount {
      // principal blob size can vary, but 29 bytes as most. We preserve it's size in result blob 
      // and it's data itself so it can be deserialized back to principal
      let principalBytes = Blob.toArray(Principal.toBlob(p));
      let principalSize = principalBytes.size();
      assert principalSize <= 29;
      let subaccountData : [Nat8] = Array.tabulate(32, func (n: Nat): Nat8 = 
        if (n == 0) {
          Nat8.fromNat(principalSize);
        } else if (n > principalSize) {
          0;
        } else {
          principalBytes[n - 1];
        }
      );
      Blob.fromArray(subaccountData);
    };

    private func subaccountToPrincipal(s : Icrc1Interface.Subaccount) : Principal {
      let subaccountBytes = Blob.toArray(s);
      let principalSize = Nat8.toNat(subaccountBytes[0]);
      let principalData : [Nat8] = Array.tabulate(principalSize, func (n: Nat): Nat8 = subaccountBytes[n + 1]);
      Principal.fromBlob(Blob.fromArray(principalData));
    };

    private func consolidateAccount(p : Principal) : async* () {
      if (not obtainTrackingInfoLock(p)) return;
      var latestBalance = 0;
      try {
        latestBalance := await icrc1Ledger.icrc1_balance_of({
          owner = ownPrincipal;
          subaccount = ?principalToSubaccount(p);
        });
      } catch (err) {
        releaseTrackingInfoLock(p);
        throw err;
      };
      updateDepositBalance(p, latestBalance);
      if (latestBalance != 0) {
        let transferResult = try {
          await icrc1Ledger.icrc1_transfer({
            from_subaccount = ?principalToSubaccount(p);
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
            credit(p, latestBalance);
            updateDepositBalance(p, 0);
          };
          case (#Err _) {
            updateDepositBalance(p, latestBalance);
            consolidationBacklog := AssocList.replace<Principal, ()>(consolidationBacklog, p, Principal.equal, ?()).0;
          };
        };
      };
      releaseTrackingInfoLock(p);
    };

    private func getOrCreateTrackingInfo(p : Principal) : TrackingInfo = switch (tree.get(p)) {
      case (?ti) ti;
      case (null) {
        let ti = {
          var deposit_balance = 0;
          var credit_balance : Int = 0;
          var usable_balance : Int = 0;
          var consolidationLock = false;
        };
        tree.put(p, ti);
        ti;
      };
    };

    private func cleanTrackingInfoIfZero(info : TrackingInfo, p : Principal) {
      if (info.deposit_balance == 0 and info.credit_balance == 0 and not info.consolidationLock) {
        tree.delete(p);
      };
    };

    public func obtainTrackingInfoLock(p : Principal) : Bool {
      let info = getOrCreateTrackingInfo(p);
      if (info.consolidationLock) return false;
      info.consolidationLock := true;
      true;
    };

    public func releaseTrackingInfoLock(p : Principal) {
      // while testing we should trap here
      let ?info = tree.get(p) else {
        Debug.trap("releasing lock that isn't locked");
      };
      if (not info.consolidationLock) Debug.trap("releasing lock that isn't locked");
      info.consolidationLock := false;
      cleanTrackingInfoIfZero(info, p);
    };

    private func updateDepositBalance(p : Principal, deposit_balance : Nat) : () {
      let info = getOrCreateTrackingInfo(p);
      info.deposit_balance := deposit_balance;
      cleanTrackingInfoIfZero(info, p);
    };

    let icrc1Ledger = actor (Principal.toText(icrc1LedgerPrincipal)) : Icrc1Interface.Icrc1LedgerInterface;

    // a backlog of principals, with failed account consolidation
    var consolidationBacklog : AssocList.AssocList<Principal, ()> = null;

    // The map from principal to tracking info:
    var tree : RBTree.RBTree<Principal, TrackingInfo> = RBTree.RBTree<Principal, TrackingInfo>(Principal.compare);
  };
};
