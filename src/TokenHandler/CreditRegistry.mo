import RBTree "mo:base/RBTree";
import Principal "mo:base/Principal";
import Option "mo:base/Option";
import Iter "mo:base/Iter";
import Int "mo:base/Int";

module {
  public type StableData = [(Principal, Int)];

  /// IntMap is a full (not partial) map from K to Int with default value 0 for all keys.
  class IntMap<K>(compare : (K, K) -> { #equal; #less; #greater }) {
    var map : RBTree.RBTree<K, Int> = RBTree.RBTree<K, Int>(compare);
    var sum_ : Int = 0;

    /// Get a value.
    public func get(x : K) : Int = map.get(x) |> Option.get(_, 0);

    /// Set a value.
    public func set(x : K, v : Int) {
      let old_v = (if (v == 0) map.remove(x) else map.replace(x, v))
      |> Option.get(_, 0);
      sum_ += v - old_v;
    };

    /// Set a value.
    public func add(x : K, d : Int) = set(x, get(x) + d);

    /// Get the sum of all values.
    public func sum() : Int = sum_;

    /// Serializes the map.
    public func share() : [(K, Int)] = Iter.toArray(map.entries());

    /// Deserializes the map.
    public func unshare(data : [(K, Int)]) {
      map := RBTree.RBTree<K, Int>(compare);
      sum_ := 0;
      for ((k, v) in data.vals()) set(k, v);
    };
  };

  /// Tracks credited funds (usable balance) associated with each principal.
  public class CreditRegistry(
    log : (Principal, { #credited : Nat; #debited : Nat }) -> ()
  ) {
    var map : IntMap<Principal> = IntMap<Principal>(Principal.compare);

    /// Retrieves the total credited funds in the credit registry.
    public func creditTotal() : Int = map.sum();

    /// Gets the current credit amount associated with a specific principal.
    public func get(p : Principal) : Int = map.get(p);

    /// Deducts amount from P’s credit.
    /// With checking the availability of sufficient funds.
    public func debitStrict(p : Principal, amount : Nat) : Bool {
      let current = map.get(p);
      if (amount > current) return false;
      map.set(p, current - amount);
      log(p, #debited(amount));
      true;
    };

    /// Deducts amount from P’s credit.
    /// Without checking the availability of sufficient funds.
    public func debit(p : Principal, amount : Nat) {
      map.add(p, -amount);
      log(p, #debited(amount));
    };

    /// Increases the credit amount associated with a specific principal
    /// (the credit is created out of thin air).
    public func credit(p : Principal, amount : Nat) {
      map.add(p, amount);
      log(p, #credited(amount));
    };

    /// Serializes the credit registry data.
    public func share() : StableData = map.share();

    /// Deserializes the credit registry data.
    public func unshare(values : StableData) = map.unshare(values);
  };
};
