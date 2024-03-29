import RBTree "mo:base/RBTree";
import Iter "mo:base/Iter";
import Principal "mo:base/Principal";

module {
  /// Balance information associated with the principal.
  public type Info = {
    var deposit : Nat; // The balance that is in the subaccount associated with the user.
    var credit : Int; // The balance that has been moved by S from S:P to S:0 (e.g. consolidated).
  };

  /// Lockable balance information associated with the user.
  public type InfoLock = Info and {
    var lock : Bool; // Lock flag for internal usage only.
  };

  public type StableData = [(Principal, Info)];

  /// Manages the balances and locks associated with each user.
  public class BalanceRegistry(freezeCallback : (text : Text) -> ()) {
    /// Maps principals to their balance info.
    var tree : RBTree.RBTree<Principal, InfoLock> = RBTree.RBTree<Principal, InfoLock>(Principal.compare);

    /// Cleans up the principal entry if `deposit` is 0, `credit` is 0, and `lock` is false.
    func clean(p : Principal, info : InfoLock) {
      if (info.deposit == 0 and info.credit == 0 and not info.lock) {
        tree.delete(p);
      };
    };

    /// Modifies the existing balance info for the user based on a given callback.
    public func change(p : Principal, f : (Info) -> Bool) : Bool {
      let ?info = tree.get(p) else return false;
      let changed = f(info);
      if (changed) clean(p, info);
      return changed;
    };

    /// Modifies the balance info for the user based on a given callback.
    public func set(p : Principal, f : (Info) -> Bool) : Bool {
      let info = getOrCreate(p);
      let changed = f(info);
      clean(p, info);
      changed;
    };

    /// Gets the balance info for the user.
    public func get(p : Principal) : ?InfoLock = tree.get(p);

    /// Gets the balance info for the user or creates if the info is missing.
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

    /// Locks the balance info for the user.
    public func lock(p : Principal) : Bool {
      let info = getOrCreate(p);
      if (info.lock) return false;
      info.lock := true;
      true;
    };

    /// Locks the balance info for the user.
    public func unlock(p : Principal) = switch (tree.get(p)) {
      case (null) {
        freezeCallback("Unlock not existent p");
      };
      case (?info) {
        if (not info.lock) freezeCallback("Releasing lock that isn't locked");
        info.lock := false;
      };
    };

    /// Gets an iterable collection of balance info entries.
    public func items() : Iter.Iter<InfoLock> = Iter.map<(Principal, InfoLock), InfoLock>(
      tree.entries(),
      func(entry : (Principal, InfoLock)) : InfoLock = entry.1,
    );

    /// Serializes the balance registry data.
    public func share() : StableData = Iter.toArray(
      Iter.filter<(Principal, InfoLock)>(
        tree.entries(),
        func((p, info)) = info.credit != 0 or info.deposit != 0,
      )
    );

    /// Deserializes the balance registry data.
    public func unshare(values : StableData) {
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
};
