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

import Icrc1Interface "icrc1_interface";

module {
  
  public type StableTrackingInfo = { deposit_balance : Nat; credit_balance : Int };
  public type Icrc1LedgerInterface = Icrc1Interface.Icrc1LedgerInterface;

  type TrackingInfo = {
    var deposit_balance : Nat;    // the balance that is in the subaccount associated with the user
    var credit_balance : Int;     // the balance that has been moved by S from S:P to S:0 (e.g. consolidated)
    var consolidationLock : Bool; // lock flag. For internal usage only
  };

  public class TokenHandler(
    icrc1LedgerPrincipal: Principal, 
    ownPrincipal: Principal,
  ) {

    /** The handler will call icrc1_balance(S:P) to query the balance. It will detect if it has increased compared 
    to the last balance seen. If it has increased then it will adjust the deposit_balance (and hence the usable_balance). 
    It will also schedule or trigger a “consolidation”, i.e. moving the newly deposited funds from S:P to S:0. 
    Note: concurrent notify() for the same P have to be handled with locks. */
    public func notify(p: Principal): async* () {
      await* consolidateAccount(p);
    };

    /** deduct amount from P’s usable balance. Return false if the balance is insufficient. */
    public func debit(p: Principal, amount: Nat): Bool {
      let info = getOrCreateTrackingInfo(p);
      if (info.deposit_balance + info.credit_balance < amount) {
        cleanTrackingInfoIfZero(info, p);
        return false;
      };
      info.credit_balance -= amount;
      cleanTrackingInfoIfZero(info, p);
      return true;
    };

    /**  add amount to P’s usable balance (the credit is created out of thin air) */
    public func credit(p: Principal, amount: Nat): () {
      let info = getOrCreateTrackingInfo(p);
      info.credit_balance += amount;
      cleanTrackingInfoIfZero(info, p);
    };

    /** query the usable balance */
    public func balance(p: Principal): Int {
      let ?item = tree.get(p) else return 0;
      item.deposit_balance + item.credit_balance;
    };

    /** query all tracked balances for debug purposes */
    public func info(p: Principal): StableTrackingInfo {
      let ?item = tree.get(p) else return { deposit_balance = 0; credit_balance = 0; usable_balance = 0 };
      { deposit_balance = item.deposit_balance; credit_balance = item.credit_balance };
    };

    /** process first account, which was failed to consolidate last time */
    public func processConsolidationBacklog(): async () = async switch (consolidationBacklog) {
      case (null) return;
      case (?((p, _), list)) {
        consolidationBacklog := list;
        await* consolidateAccount(p);
      };
    };

    /** serialize tracking data */
    public func share() : [(Principal, StableTrackingInfo)] = Iter.toArray(
      Iter.map<(Principal, TrackingInfo), (Principal, StableTrackingInfo)>(
        Iter.filter<(Principal, TrackingInfo)>(
          tree.entries(),
          func((p, ti)) = ti.credit_balance != 0 or ti.deposit_balance != 0,
        ),
        func((p, ti)) = (p, { deposit_balance = ti.deposit_balance; credit_balance = ti.credit_balance }),
      ),
    );


    /** deserialize tracking data */
    public func unshare(values : [(Principal, StableTrackingInfo)]) {
      tree := RBTree.RBTree<Principal, TrackingInfo>(Principal.compare);
      for ((p, value) in values.vals()) {
        tree.put(p, { 
          var deposit_balance = value.deposit_balance; 
          var credit_balance = value.credit_balance; 
          var consolidationLock = false
        });
      };
    };

    private func consolidateAccount(p: Principal): async* () {
      if (not obtainTrackingInfoLock(p)) return;
      var latestBalance = 0;
      try {
        latestBalance := await icrc1Ledger.icrc1_balance_of({ owner = ownPrincipal; subaccount = ?Principal.toBlob(p); }); // FIXME should be 32 bytes instead of 29;
      } catch (err) {
        releaseTrackingInfoLock(p);
        throw err;
      };
      updateDepositBalance(p, latestBalance);
      if (latestBalance != 0) { 
        let transferResult = try {
          await icrc1Ledger.icrc1_transfer({
            from_subaccount = ?Principal.toBlob(p); // FIXME should be 32 bytes instead of 29
            to = { owner = ownPrincipal; subaccount = null; };
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
        let ti = { var deposit_balance = 0; var credit_balance : Int = 0; var usable_balance : Int = 0; var consolidationLock = false; };
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
      let ?info = tree.get(p) else { Debug.trap("releasing lock that isn't locked") }; 
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
    var consolidationBacklog: AssocList.AssocList<Principal, ()> = null;

    // The map from principal to tracking info:
    var tree : RBTree.RBTree<Principal, TrackingInfo> = RBTree.RBTree<Principal, TrackingInfo>(Principal.compare);
  };

}
