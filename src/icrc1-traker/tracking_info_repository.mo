import RBTree "mo:base/RBTree";
import Principal "mo:base/Principal";
import Iter "mo:base/Iter";
import R "mo:base/Result";
import Debug "mo:base/Debug";

module TrackingInfoRepository {

  type TrackingInfo = {
    var tracked : Nat;
    var credit : Int;
    var consolidationLock : Bool;
  };
  public type StableTrackingInfo = { tracked : Nat; credit : Int };

  // terminology: spendable balance = deposit balance + credit balance
  public class TrackingInfoRepository() {

    var tree : RBTree.RBTree<Principal, TrackingInfo> = RBTree.RBTree<Principal, TrackingInfo>(Principal.compare);

    public func creditBalanceOf(p : Principal) : Int {
      let ?item = tree.get(p) else return 0;
      item.credit;
    };

    public func spendableBalanceOf(p : Principal) : Int {
      let ?item = tree.get(p) else return 0;
      item.tracked + item.credit;
    };

    private func cleanIfZero(info : TrackingInfo, p : Principal) {
      if (info.tracked == 0 and info.credit == 0 and not info.consolidationLock) {
        tree.delete(p);
      };
    };

    public func checkNewDeposits(p : Principal, tracked : Nat) : Int {
      let info = getOrCreate(p);
      info.tracked := tracked;
      cleanIfZero(info, p);
      info.tracked + info.credit;
    };

    public func addCredit(p : Principal, delta : Int) : Int {
      let info = getOrCreate(p);
      info.credit += delta;
      cleanIfZero(info, p);
      info.tracked + info.credit;
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
          func((p, ti)) = ti.credit != 0 or ti.tracked != 0,
        ),
        func((p, ti)) = (p, { tracked = ti.tracked; credit = ti.credit }),
      ),
    );

    public func unshare(values : [(Principal, StableTrackingInfo)]) {
      tree := RBTree.RBTree<Principal, TrackingInfo>(Principal.compare);
      for ((p, value) in values.vals()) {
        tree.put(p, { var tracked = value.tracked; var credit = value.credit; var consolidationLock = false });
      };
    };

    private func getOrCreate(p : Principal) : TrackingInfo = switch (tree.get(p)) {
      case (?ti) ti;
      case (null) {
        let ti = { var tracked = 0; var credit : Int = 0; var consolidationLock = false; };
        tree.put(p, ti);
        ti;
      };
    };
  };
};
