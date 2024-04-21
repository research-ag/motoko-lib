import RBTree "mo:base/RBTree";
import Iter "mo:base/Iter";
import Principal "mo:base/Principal";

module {
  /// Represents the deposit information associated with the user.
  public type DepositInfo = {
    var deposit : Nat; // The balance that is in the subaccount associated with the user.
    var lock : Bool; // Flag indicating if the balance is locked.
  };

  public type StableData = [(Principal, DepositInfo)];

  /// Manages the deposits and locks associated with each user.
  public class DepositRegistry(freezeCallback : (text : Text) -> ()) {
    /// Maps user principals to their deposit info.
    var tree : RBTree.RBTree<Principal, DepositInfo> = RBTree.RBTree<Principal, DepositInfo>(Principal.compare);

    // For benchmarking purposes we track how often we lookup a key in the tree
    // TODO: remove in production
    var lookupCtr = 0;
    public func lookups() : Nat = lookupCtr;

    /// Retrieves size of the deposit registry.
    /// It's a bit tricky to cache because when lock, then new zero-deposit record can be created.
    public func size() : Nat {
      var size_ = 0;
      for ((p, depositInfo) in entries()) {
        if (depositInfo.deposit != 0) {
          size_ += 1;
        };
      };
      size_;
    };

    /// Cleans up the deposit info if there is no deposit for a user (and if not locked).
    func clean(p : Principal, info : DepositInfo) {
      if (info.deposit == 0 and not info.lock) {
        tree.delete(p);
        lookupCtr += 1;
      };
    };

    /// Modifies the deposit for a specific principal.
    public func setDeposit(p : Principal, deposit : Nat) : () {
      let info = getOrCreate(p, true);
      info.deposit := deposit;
      clean(p, info);
    };

    /// Gets the deposit information for a specific principal.
    public func get(p : Principal) : DepositInfo = getOrCreate(p, false);

    /// Gets the deposit information for a specific principal.
    /// Creates empty deposit information if none exists.
    /// Inserts into the map if `insert` equals `true`.
    func getOrCreate(p : Principal, insert : Bool) : DepositInfo {
      lookupCtr += 1;
      switch (tree.get(p)) {
        case (?info) info;
        case (null) {
          let info = {
            var deposit = 0;
            var lock = false;
          };
          if (insert) {
            tree.put(p, info);
            lookupCtr += 1;
          };
          info;
        };
      };
    };

    /// Checks if the deposit info for a specific principal is currently locked.
    public func isLock(p : Principal) : Bool {
      let info = get(p);
      info.lock;
    };

    /// Locks the deposit info for a specific user to prevent changes.
    public func lock(p : Principal) {
      let info = getOrCreate(p, true);
      info.lock := true;
    };

    /// Unlocks the deposit info for a particular principal to allow modifications.
    public func unlock(p : Principal) {
      lookupCtr += 1;
      switch (tree.get(p)) {
        case (null) {
          freezeCallback("Unlock not existent p");
        };
        case (?info) {
          if (not info.lock) freezeCallback("Releasing lock that isn't locked");
          info.lock := false;
          clean(p, info);
        };
      };
    };

    /// Creates an iterator for the entries of the deposit registry.
    public func entries() : Iter.Iter<(Principal, DepositInfo)> = tree.entries();

    /// Serializes the deposit registry data.
    public func share() : StableData = Iter.toArray(
      Iter.filter<(Principal, DepositInfo)>(
        tree.entries(),
        func((p, info)) = info.deposit != 0,
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
            var lock = false;
          },
        );
      };
    };
  };
};
