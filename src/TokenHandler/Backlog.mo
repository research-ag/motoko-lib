import RBTree "mo:base/RBTree";
import Principal "mo:base/Principal";
import Iter "mo:base/Iter";

module {
  public type StableData = RBTree.Tree<Principal, ()>;

  /// Represents a backlog of principals waiting for processing.
  public class Backlog() {
    let backlog = RBTree.RBTree<Principal, ()>(Principal.compare);

    /// Retrieves the size of the backlog.
    public func size() : Nat {
      RBTree.size(backlog.share());
    };

    /// Adds a new principal to the backlog.
    public func push(p : Principal) {
      backlog.put(p, ());
    };

    /// Removes a principal from the backlog.
    public func remove(p : Principal) {
      backlog.delete(p);
    };

    /// Creates an iterator for the principals in the backlog.
    public func iter() : Iter.Iter<Principal> {
      Iter.map<(Principal, ()), Principal>(backlog.entries(), func((p, _) : (Principal, ())) = p);
    };

    /// Serializes the backlog data.
    public func share() : StableData {
      backlog.share();
    };

    /// Deserializes the backlog data.
    public func unshare(data : StableData) {
      backlog.unshare(data);
    };
  };
};
