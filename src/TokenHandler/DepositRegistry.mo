import RBTree "mo:base/RBTree";
import Iter "mo:base/Iter";
import Principal "mo:base/Principal";

module {
  /// Represents the deposit information associated with the user.
  public type DepositInfo = {
    var deposit : Nat; // The balance that is in the subaccount associated with the user.
    var queued : Nat; // The funds queued for consolidation.
    var underway : Nat; // The funds currently undergoing consolidation.
    var lock : Bool; // Flag indicating if the balance is locked.
  };

  public type StableData = [(Principal, DepositInfo)];

  /// Manages the deposits and locks associated with each user.
  public class DepositRegistry(freezeCallback : (text : Text) -> ()) {
    /// Maps user principals to their deposit info.
    var tree : RBTree.RBTree<Principal, DepositInfo> = RBTree.RBTree<Principal, DepositInfo>(Principal.compare);

    /// Cleans up the deposit info if there is no deposit for a user (and if not locked).
    func clean(p : Principal, info : DepositInfo) {
      if (info.deposit == 0 and not info.lock) {
        tree.delete(p);
      };
    };

    /// Modifies the deposit information for a user based on a provided callback.
    public func set(p : Principal, f : (DepositInfo) -> Bool) : Bool {
      let info = getOrCreate(p);
      let changed = f(info);
      clean(p, info);
      changed;
    };

    /// Gets the deposit information for a specific principal.
    public func get(p : Principal) : ?DepositInfo = tree.get(p);

    /// Gets the deposit information for a specific principal.
    /// Creates new deposit information if none exists.
    func getOrCreate(p : Principal) : DepositInfo = switch (tree.get(p)) {
      case (?info) info;
      case (null) {
        let info = {
          var deposit = 0;
          var queued = 0;
          var underway = 0;
          var lock = false;
        };
        tree.put(p, info);
        info;
      };
    };

    /// Checks if the deposit info for a specific principal is currently locked.
    public func isLock(p : Principal) : Bool {
      let ?info = get(p) else return false;
      return info.lock;

    };

    /// Locks the deposit info for a specific user to prevent changes.
    public func lock(p : Principal) : Bool {
      let info = getOrCreate(p);
      if (info.lock) return false;
      info.lock := true;
      true;
    };

    /// Unlocks the deposit info for a particular principal to allow modifications.
    public func unlock(p : Principal) = switch (tree.get(p)) {
      case (null) {
        freezeCallback("Unlock not existent p");
      };
      case (?info) {
        if (not info.lock) freezeCallback("Releasing lock that isn't locked");
        info.lock := false;
      };
    };

    /// Serializes the deposit registry data.
    public func share() : StableData = Iter.toArray(
      Iter.filter<(Principal, DepositInfo)>(
        tree.entries(),
        func((p, info)) = info.deposit != 0 or info.queued != 0 or info.underway != 0,
      )
    );

    /// Deserializes the deposit registry data.
    public func unshare(values : StableData) {
      tree := RBTree.RBTree<Principal, DepositInfo>(Principal.compare);
      for ((p, value) in values.vals()) {
        tree.put(
          p,
          {
            var deposit = value.deposit;
            var queued = value.queued;
            var underway = 0;
            var lock = false;
          },
        );
      };
    };
  };
};
