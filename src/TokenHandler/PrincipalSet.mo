import RBTree "mo:base/RBTree";
import Principal "mo:base/Principal";
import Iter "mo:base/Iter";

module {
  public type StableData = RBTree.Tree<Principal, ()>;

  /// Represents a set of principals.
  public class PrincipalSet() {
    let map = RBTree.RBTree<Principal, ()>(Principal.compare);

    /// Retrieves the size of the principal set.
    public func size() : Nat {
      RBTree.size(map.share());
    };

    /// Checks if the principal set contains a specified principal.
    public func has(p : Principal) : Bool {
      switch (map.get(p)) { case (null) { false }; case (_) { true } };
    };

    /// Adds a new principal to the principal set.
    public func push(p : Principal) {
      map.put(p, ());
    };

    /// Removes a principal from the principal set.
    public func remove(p : Principal) {
      map.delete(p);
    };

    /// Creates an iterator for the principals in the backlog.
    public func iter() : Iter.Iter<Principal> {
      Iter.map<(Principal, ()), Principal>(map.entries(), func((p, _) : (Principal, ())) = p);
    };

    /// Serializes the principal set data.
    public func share() : StableData {
      map.share();
    };

    /// Deserializes the principal set data.
    public func unshare(data : StableData) {
      map.unshare(data);
    };
  };
};
