import Debug "mo:base/Debug";
import Error "mo:base/Error";
import Option "mo:base/Option";
import Principal "mo:base/Principal";
import R "mo:base/Result";
import AssocList "mo:base/AssocList";

import Icrc1Tracker "icrc1_tracker";
import Icrc1Interface "icrc1_interface";

actor class Icrc1TrackerAPI(icrc1Ledger : ?Principal) = self {

  stable let Icrc1Ledger = switch (icrc1Ledger) {
    case (?p) actor (Principal.toText(p)) : Icrc1Tracker.Icrc1LedgerInterface;
    case (_) { Debug.trap("not initialized and no icrc1 ledger supplied");}
  };

  stable var savedArgs : ?Principal = null; // own principal
  stable var stableTrackingTable : [(Principal, Icrc1Tracker.StableTrackingInfo)] = [];
  stable var stableConsolidationBacklog: AssocList.AssocList<Principal, ()> = null;

  var tracker = switch (savedArgs) {
    case (?v) ?Icrc1Tracker.Icrc1Tracker(Icrc1Ledger, v);
    case (_) null
  };

  var initActive = false; // lock to prevent concurrent init() calls

  public shared func init(): async () {
    assert Option.isNull(savedArgs); // trap if already )initialized
    assert (not initActive); // trap if init() already in process
    initActive := true;
    let p = Principal.fromActor(self);
    savedArgs := ?(p);
    tracker := ?Icrc1Tracker.Icrc1Tracker(Icrc1Ledger, p);
    initActive := false;
  };

  public query func creditAvailable(p: Principal): async Int = async
    switch(tracker) {
      case (?m) m.creditAvailable(p);
      case (_) Debug.trap("not initialized");
    };

  public shared func notify(p: Principal): async () = async
    switch(tracker) {
      case (?m) await* m.notify(p);
      case (_) Debug.trap("not initialized");
    };

  system func preupgrade() =
    switch(tracker) {
      case(?m) {
        stableTrackingTable := m.trackingRepo.share();
        stableConsolidationBacklog := m.consolidationBacklog;
      };
      case(_) { };
    };

  system func postupgrade() =
    switch(tracker) {
      case(?m) {
        m.trackingRepo.unshare(stableTrackingTable);
        m.consolidationBacklog := stableConsolidationBacklog;
      };
      case(_) { };
    };

};
