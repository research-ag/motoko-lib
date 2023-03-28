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

    /// Return interval `[start, end)` of indices of elements available.
    public func available() : (Nat, Nat) {
      (Int.abs(Int.max(0, pushes - capacity)), Int.abs(pushes));
    };

    func realIndex(index : Nat) : Nat {
      var x = last - (pushes - index);
      if (x < 0) x += capacity;
      Int.abs(x);
    };

    /// Returns single element added with number `index` or null if element is not available or index out of bounds.
    public func get(index : Nat) : ?T {
      let (l, r) = available();
      if (l <= index and index < r) { array[realIndex(index)] } else { null };
    };

    /// Return iterator to values added with numbers in interval `[from; to)`.
    /// `from` should be not more then `to`. Both should be not more then `pushes`.
    public func slice(from : Nat, to : Nat) : Iter.Iter<T> {
      assert from <= to;
      let interval = available();

      assert interval.0 <= from and from <= interval.1 and interval.0 <= to and to <= interval.1;

      let count : Int = to - from;

      object {
        var start = realIndex(from);

        var i = 0;

        public func next() : ?T {
          if (i == count) return null;
          let ret = array[start];
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
