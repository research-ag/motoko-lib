import RBTree "mo:base/RBTree";
import Option "mo:base/Option";
import Iter "mo:base/Iter";

module {
  /// Map is a full (not partial) map from K to Int with default value 0 for all keys.
  public class Map<K>(compare : (K, K) -> { #equal; #less; #greater }) {
    var map : RBTree.RBTree<K, Int> = RBTree.RBTree<K, Int>(compare);
    var sum_ : Int = 0;

    /// Get a value.
    public func get(x : K) : Int = map.get(x) |> Option.get(_, 0);

    /// Set a value.
    public func set(x : K, v : Int) {
      (
        if (v != 0) map.replace(x, v) else map.remove(x)
      )
      |> Option.get(_, 0)
      |> (sum_ += v - _);
    };

    /// Add to a value.
    public func add(x : K, d : Int) = set(x, get(x) + d);

    /// Conditionally add to a value.
    public func addIf(x : K, d : Int, p : Int -> Bool) : Bool {
      let current = get(x);
      let res = p(current);
      if (res) set(x, current + d);
      res
    };

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
};
