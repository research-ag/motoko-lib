import Array "mo:base/Array";
import Nat "mo:base/Nat";
import Iter "mo:base/Iter";
import Debug "mo:base/Debug";
import Int "mo:base/Int";

module CircularBuffer {
  /// Circular buffer, which preserves amount of pushed values
  public class CircularBuffer<T>(capacity : Nat) {
    var array : [var ?T] = Array.init(capacity, null);
    var last : Nat = 0;
    var pushes : Int = 0;

    /// Number of items that were ever pushed to the buffer
    public func pushesAmount() : Nat = Int.abs(pushes);

    /// insert value into the buffer
    public func push(item : T) {
      array[last] := ?item;
      pushes += 1;
      last += 1;
      if (last == capacity) last := 0;
    };

    /// Return iterator to values added with numbers in interval `[from; to)`.
    /// `from` should be not more then `to`. Both should be not more then `pushes`.
    public func slice(from : Nat, to : Nat) : Iter.Iter<T> {
      assert from <= to and to <= pushes;

      let min = if (pushes >= capacity) { pushes - capacity } else { 0 };

      let count = Int.max(min, to) - Int.max(min, from);

      func wrap(i : Nat) : Nat {
        var start = last - (pushes - Int.max(min, i));
        if (start < 0) start += capacity;
        Int.abs(start);
      };

      object {
        var start = wrap(from);
        var i = 0;

        public func next() : ?T {
          if (i == count) return null;
          let ret = array[Int.abs(start)];
          start += 1;
          if (start == capacity) start := 0;
          i += 1;
          ret;
        };
      };
    };

    /// Share stable content
    public func share() : ([var ?T], Nat, Int) = (array, last, pushes);

    /// Unshare from stable content
    public func unshare(data : ([var ?T], Nat, Int)) {
      array := data.0;
      last := data.1;
      pushes := data.2;
    };
  };
};
