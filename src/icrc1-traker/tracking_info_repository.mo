import RBTree "mo:base/RBTree";
import Principal "mo:base/Principal";
import Iter "mo:base/Iter";
import R "mo:base/Result";
import Debug "mo:base/Debug";

module TrackingInfoRepository {

  type TrackingInfo = {
    var deposit_balance : Nat; // the balance that is in the subaccount associated with the user
    var credit_balance : Int; // the balance that has been moved by S from S:P to S:0 (e.g. consolidated)
    var consolidationLock : Bool;
  };
  public type StableTrackingInfo = { deposit_balance : Nat; credit_balance : Int };

  public class TrackingInfoRepository() {

    var tree : RBTree.RBTree<Principal, TrackingInfo> = RBTree.RBTree<Principal, TrackingInfo>(Principal.compare);

    public func usableBalanceOf(p : Principal) : Int {
      let ?item = tree.get(p) else return 0;
      item.deposit_balance + item.credit_balance;
    };

    public func info(p : Principal) : StableTrackingInfo {
      let ?item = tree.get(p) else return { deposit_balance = 0; credit_balance = 0; usable_balance = 0 };
      { deposit_balance = item.deposit_balance; credit_balance = item.credit_balance };
    };

    private func cleanIfZero(info : TrackingInfo, p : Principal) {
      if (info.deposit_balance == 0 and info.credit_balance == 0 and not info.consolidationLock) {
        tree.delete(p);
      };
    };

    public func updateDepositBalance(p : Principal, deposit_balance : Nat) : () {
      let info = getOrCreate(p);
      info.deposit_balance := deposit_balance;
      cleanIfZero(info, p);
    };

    public func debit(p: Principal, amount: Nat): Bool {
      let info = getOrCreate(p);
      if (info.deposit_balance + info.credit_balance < amount) {
        cleanIfZero(info, p);
        return false;
      };
      info.credit_balance -= amount;
      cleanIfZero(info, p);
      return true;
    };
    public func credit(p : Principal, amount : Nat) : () {
      let info = getOrCreate(p);
      info.credit_balance += amount;
      cleanIfZero(info, p);
    };

    public func obtainLock(p : Principal) : Bool {
      let info = getOrCreate(p);
      if (info.consolidationLock) return false;
      info.consolidationLock := true;
      true;
    };

    public func releaseLock(p : Principal) {
      // while testing we should trap here
      let ?info = tree.get(p) else { Debug.trap("releasing lock that isn't locked") }; 
      if (not info.consolidationLock) Debug.trap("releasing lock that isn't locked"); 
      info.consolidationLock := false;
      cleanIfZero(info, p);
    };

    public func share() : [(Principal, StableTrackingInfo)] = Iter.toArray(
      Iter.map<(Principal, TrackingInfo), (Principal, StableTrackingInfo)>(
        Iter.filter<(Principal, TrackingInfo)>(
          tree.entries(),
          func((p, ti)) = ti.credit_balance != 0 or ti.deposit_balance != 0,
        ),
        func((p, ti)) = (p, { deposit_balance = ti.deposit_balance; credit_balance = ti.credit_balance }),
      ),
    );

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

    private func getOrCreate(p : Principal) : TrackingInfo = switch (tree.get(p)) {
      case (?ti) ti;
      case (null) {
        let ti = { var deposit_balance = 0; var credit_balance : Int = 0; var usable_balance : Int = 0; var consolidationLock = false; };
        tree.put(p, ti);
        ti;
      };
    };
  };
};
