import Array "mo:base/Array";
import Iter "mo:base/Iter";
import Nat64 "mo:base/Nat64";
import Region "mo:base/Region";
import Blob "mo:base/Blob";
import Nat32 "mo:base/Nat32";

module CircularBuffer {
  public class CircularBuffer<T>(capacity : Nat) {
    assert capacity != 0;

    var array : [var ?T] = Array.init(capacity, null);
    var last = 0;
    var pushes = 0;

    /// Number of items that were ever pushed to the buffer
    public func pushesAmount() : Nat = pushes;

    /// Insert value into the buffer
    public func push(item : T) {
      array[last] := ?item;
      pushes += 1;
      last += 1;
      if (last == capacity) last := 0;
    };

    /// Return interval `[start, end)` of indices of elements available.
    public func available() : (Nat, Nat) {
      (if (pushes <= capacity) 0 else pushes - capacity, pushes);
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
    public func unshare(data : ([var ?T], Nat, Nat)) {
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

    func bytesToPages(n : Nat) : Nat64 {
      Nat64.fromNat((n + PAGE_SIZE - 1) / PAGE_SIZE);
    };

    /// Assert no waste in regions memory
    public func assert_no_waste() {
      assert capacity > 0;
      assert ((capacity + 1) * POINTER_SIZE) % PAGE_SIZE == 0;

      assert length > 0;
      assert length % PAGE_SIZE == 0;
      assert length <= 2 ** (POINTER_SIZE * 8);
    };

    var state_ : ?CircularBufferStableState = null;

    /// Reset circular buffer state
    public func reset() {
      let s = state();
      s.pushes := 0;
      s.start := 0;
      s.count := 0;
      s.start_data := 0;
      s.count_data := 0;
      Region.storeNat32(s.index, 0, 0);
    };

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
          assert Region.grow(s.index, bytesToPages((capacity + 1) * POINTER_SIZE)) != 0xFFFF_FFFF_FFFF_FFFF;
          assert Region.grow(s.data, bytesToPages(length)) != 0xFFFF_FFFF_FFFF_FFFF;
          Region.storeNat32(s.index, 0, 0);
          state_ := ?s;
          s;
        };
      };
    };

    /// Number of items that were ever pushed to the buffer
    public func pushesAmount() : Nat = state().pushes;

    // Load and store pointers
    func pointerPosition(i : Nat) : Nat64 {
      let pos = i % (capacity + 1);
      Nat64.fromNat(pos * POINTER_SIZE);
    };
    func storePointer(i : Nat, val : Nat) {
      Region.storeNat32(state().index, pointerPosition(i), Nat32.fromNat(val));
    };
    func loadPointer(i : Nat) : Nat {
      Nat32.toNat(Region.loadNat32(state().index, pointerPosition(i)));
    };
    // Load and store data
    func storeData(pos : Nat, blob : Blob) {
      Region.storeBlob(state().data, Nat64.fromNat(pos), blob);
    };
    func loadData(pos : Nat, len : Nat) : Blob {
      Region.loadBlob(state().data, Nat64.fromNat(pos), len);
    };

    func pop_(s : CircularBufferStableState, take : Bool) : ?T {
      let new_start_data = loadPointer(s.start + 1);
      let item_length = (new_start_data + length - s.start_data : Nat) % length;

      let value = if (take) {
        let blob = if (s.start_data < new_start_data) {
          loadData(s.start_data, item_length);
        } else if (s.start_data > new_start_data) {
          let sz1 : Nat = length - s.start_data;
          let first_part = Blob.toArray(loadData(s.start_data, sz1));
          let second_part = Blob.toArray(loadData(0, new_start_data));
          Blob.fromArray(Array.tabulate<Nat8>(item_length, func(i) = if (i < sz1) first_part[i] else second_part[i - sz1]));
        } else {
          Blob.fromArray([]);
        };
        ?deserialize(blob);
      } else { null };

      s.count_data -= item_length;
      s.start_data := new_start_data;
      s.start := (s.start + 1) % (capacity + 1);
      s.count -= 1;
      value;
    };

    public func deleteTo(index : Nat) {
      let (l, r) = available();
      assert l < index and index <= r;
      let s = state();
      for (i in Iter.range(0, index - l - 1)) {
        ignore pop_(s, false);
      };
    };

    public func pop() : ?T {
      let s = state();
      if (s.count == 0) return null;
      pop_(s, true);
    };

    func push_(item : T, force : Bool) : Bool {
      let s = state();
      let blob = serialize(item);

      assert blob.size() < length;

      if (force) {
        while (s.count == capacity or length < blob.size() + s.count_data) {
          ignore pop_(s, false);
        };
      } else if (s.count == capacity or length < blob.size() + s.count_data) {
        return false;
      };

      if (blob.size() > 0) {
        let end_data = (s.start_data + s.count_data) % length;
        if (end_data + blob.size() <= length) {
          storeData(end_data, blob);
        } else {
          let a = Blob.toArray(blob);
          let sz : Nat = length - end_data;
          let first_part = Blob.fromArray(Array.tabulate<Nat8>(sz, func(i) = a[i]));
          let second_part = Blob.fromArray(Array.tabulate<Nat8>(blob.size() - sz, func(i) = a[sz + i]));
          storeData(end_data, first_part);
          storeData(0, second_part);
        };
      };
      s.count_data += blob.size();
      s.count += 1;
      storePointer(s.start + s.count, (s.start_data + s.count_data) % length);
      s.pushes += 1;
      true;
    };

    /// Insert value into the buffer
    public func push(item : T) : Bool = push_(item, false);

    /// Insert value into the buffer with overwriting
    public func push_force(item : T) = ignore push_(item, true);

    /// Return interval `[start, end)` of indices of elements available.
    public func available() : (Nat, Nat) {
      let s = state();
      (s.pushes - s.count, s.pushes);
    };

    func get_(start : Nat, l : Nat, index : Nat) : T {
      let i = start + index - l : Nat;

      let from = loadPointer(i);
      let to = loadPointer(i +1);
      let blob = if (to < from) {
        let first_part = Blob.toArray(loadData(from, length - from));
        let second_part = Blob.toArray(loadData(0, to));
        Blob.fromArray(
          Array.tabulate<Nat8>(
            first_part.size() + second_part.size(),
            func(i) = if (i < first_part.size()) first_part[i] else second_part[i - first_part.size()],
          )
        );
      } else if (to == from) {
        Blob.fromArray([]);
      } else {
        loadData(from, to - from);
      };
      deserialize(blob);
    };

    /// Returns single element added with number `index` or null if element is not available or index out of bounds.
    public func get(index : Nat) : ?T {
      let (l, r) = available();
      if (not (l <= index and index < r)) {
        return null;
      };
      ?get_(state().start, l, index);
    };

    /// Return iterator to values added with numbers in interval `[from; to)`.
    /// `from` should be not more then `to`. Both should be not more then `pushes`.
    public func slice(from : Nat, to : Nat) : Iter.Iter<T> {
      assert from <= to;
      let interval = available();

      assert interval.0 <= from and from <= interval.1 and interval.0 <= to and to <= interval.1;

      let start = state().start;

      object {
        var i = from;

        public func next() : ?T {
          if (i == to) return null;
          let ret = get_(start, interval.0, i);
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
          assert capacity == data.capacity;
          assert length == data.length;
          state_ := ?data;
        };
      };
    };
  };
};
