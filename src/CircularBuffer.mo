import Array "mo:base/Array";
import Nat "mo:base/Nat";
import Iter "mo:base/Iter";
import Debug "mo:base/Debug";
import Int "mo:base/Int";
import Nat64 "mo:base/Nat64";
import Region "mo:base/Region";
import Blob "mo:base/Blob";
import Option "mo:base/Option";
import Nat32 "mo:base/Nat32";
import Prim "mo:⛔";
import MemoryRegion "mo:memory-region/MemoryRegion";

module CircularBuffer {
  public class CircularBuffer<T>(capacity : Nat) {
    assert capacity != 0;

    var array : [var ?T] = Array.init(capacity, null);
    var last : Nat = 0;
    var pushes : Int = 0;

    /// Number of items that were ever pushed to the buffer
    public func pushesAmount() : Nat = Int.abs(pushes);

    /// Insert value into the buffer
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

    /// Returns single element added with number `index` or null if element is not available or index out of bounds.
    public func get(index : Nat) : ?T {
      let (l, r) = available();
      if (l <= index and index < r) { array[index % capacity] } else { null };
    };

    /// Return iterator to values added with numbers in interval `[from; to)`.
    /// `from` should be not more then `to`. Both should be not more then `pushes`.
    public func slice(from : Nat, to : Nat) : Iter.Iter<T> {
      assert from <= to;
      let interval = available();

      assert interval.0 <= from and from <= interval.1 and interval.0 <= to and to <= interval.1;

      let count : Int = to - from;

      object {
        var start = from % capacity;

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

  public type CircularBufferStableState = {
    length : Nat;
    capacity : Nat;

    index : Region;
    var start : Nat;
    var count : Nat;

    data : Region;
    var start_data : Nat;
    var count_data : Nat;

    var pushes : Nat;
  };

  public class CircularBufferStable<T>(
    serialize : T -> Blob,
    deserialize : Blob -> T,
    capacity : Nat,
    length : Nat,
  ) {
    let POINTER_SIZE = 4;
    let PAGE_SIZE = 2 ** 16;

    /// Assert no waste in regions memory
    public func assert_no_waste() {
      assert capacity > 0;
      assert (capacity * POINTER_SIZE) % PAGE_SIZE == 0;
      assert capacity * POINTER_SIZE <= 2 ** (POINTER_SIZE * 8);

      assert length > 0;
      assert length % PAGE_SIZE == 0;
      assert length <= 2 ** (POINTER_SIZE * 8);
    };

    var state_ : ?CircularBufferStableState = null;

    func state() : CircularBufferStableState {
      switch (state_) {
        case (?s) s;
        case (null) {
          let s : CircularBufferStableState = {
            capacity;
            length;
            index = Region.new();
            data = Region.new();
            var pushes = 0;
            var start = 0;
            var count = 0;
            var start_data = 0;
            var count_data = 0;
          };
          assert Region.grow(s.index, Nat64.fromNat((capacity * POINTER_SIZE + PAGE_SIZE - 1) / PAGE_SIZE)) != 0xFFFF_FFFF_FFFF_FFFF;
          assert Region.grow(s.data, Nat64.fromNat((length + PAGE_SIZE - 1) / PAGE_SIZE)) != 0xFFFF_FFFF_FFFF_FFFF;
          Region.storeNat32(s.index, 0, 0);
          state_ := ?s;
          s;
        };
      };
    };

    /// Number of items that were ever pushed to the buffer
    public func pushesAmount() : Nat = state().pushes;

    /// Insert value into the buffer
    public func push(item : T) {
      let s = state();
      let blob = serialize(item);

      // 0 < blob.size() necessary for correct work of get
      assert 0 < blob.size() and blob.size() <= length;

      while (s.count == capacity or length < blob.size() + s.count_data) {
        let new_start = Nat32.toNat(Region.loadNat32(s.index, Nat64.fromNat((s.start + 1) % capacity * POINTER_SIZE)));
        s.count_data -= (new_start + length - s.start_data) % length;
        s.start_data := new_start;
        s.start := (s.start + 1) % capacity;
        s.count -= 1;
      };

      let end_data = (s.start_data + s.count_data) % length;
      if (end_data + blob.size() <= length) {
        Region.storeBlob(s.data, Nat64.fromNat(end_data), blob);
      } else {
        let a = Blob.toArray(blob);
        let first_part = Blob.fromArray(Array.tabulate<Nat8>(Int.abs(length : Int - end_data), func(i) = a[i]));
        let second_part = Blob.fromArray(Array.tabulate<Nat8>(blob.size() - first_part.size(), func(i) = a[first_part.size() + i]));
        Region.storeBlob(s.data, Nat64.fromNat(end_data), first_part);
        Region.storeBlob(s.data, 0, second_part);
      };
      s.count_data += blob.size();
      s.count += 1;
      Region.storeNat32(s.index, Nat64.fromNat(((s.start + s.count) % capacity) * POINTER_SIZE), Nat32.fromNat((s.start_data + s.count_data) % length));
      s.pushes += 1;
    };

    /// Return interval `[start, end)` of indices of elements available.
    public func available() : (Nat, Nat) {
      let s = state();
      (Int.abs(Int.max(0, s.pushes : Int - s.count)), s.pushes);
    };

    func get_(s : CircularBufferStableState, l : Nat, index : Nat) : T {
      let i = Int.abs(s.start : Int + index - l);

      let from = Nat32.toNat(Region.loadNat32(s.index, Nat64.fromNat(i * POINTER_SIZE)));
      let to = Nat32.toNat(Region.loadNat32(s.index, Nat64.fromNat((i + 1) % capacity * POINTER_SIZE)));
      let blob = if (to <= from) {
        let first_part = Blob.toArray(Region.loadBlob(s.data, Nat64.fromNat(from), length - from));
        let second_part = Blob.toArray(Region.loadBlob(s.data, 0, to));
        Blob.fromArray(
          Array.tabulate<Nat8>(
            first_part.size() + second_part.size(),
            func(i) = if (i < first_part.size()) first_part[i] else second_part[i - first_part.size()],
          )
        );
      } else {
        Region.loadBlob(s.data, Nat64.fromNat(from), to - from);
      };
      deserialize(blob);
    };

    /// Returns single element added with number `index` or null if element is not available or index out of bounds.
    public func get(index : Nat) : ?T {
      let s = state();
      let (l, r) = available();
      if (not (l <= index and index < r)) {
        return null;
      };
      ?get_(s, l, index);
    };

    /// Return iterator to values added with numbers in interval `[from; to)`.
    /// `from` should be not more then `to`. Both should be not more then `pushes`.
    public func slice(from : Nat, to : Nat) : Iter.Iter<T> {
      assert from <= to;
      let interval = available();

      assert interval.0 <= from and from <= interval.1 and interval.0 <= to and to <= interval.1;

      let s = state();
      let count : Int = to - from;

      object {
        var i = from;

        public func next() : ?T {
          if (i == to) return null;
          let ret = get_(s, interval.0, i);
          i += 1;
          ?ret;
        };
      };
    };

    /// Share stable content
    public func share() : CircularBufferStableState = state();

    /// Unshare from stable content
    public func unshare(data : CircularBufferStableState) {
      switch (state_) {
        case (?s) {
          assert false;
        };
        case (null) {
          if (capacity > data.capacity) {
            assert Region.grow(data.index, Nat64.fromNat(((capacity - data.capacity) * POINTER_SIZE + PAGE_SIZE - 1) / PAGE_SIZE)) != 0xFFFF_FFFF_FFFF_FFFF;
          };
          if (length > data.length) {
            assert Region.grow(data.data, Nat64.fromNat((length - data.length + PAGE_SIZE - 1) / PAGE_SIZE)) != 0xFFFF_FFFF_FFFF_FFFF;
          };
          state_ := ?data;
        };
      };
    };
  };
};
