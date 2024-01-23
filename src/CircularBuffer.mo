import Array "mo:base/Array";
import Iter "mo:base/Iter";
import Nat64 "mo:base/Nat64";
import Region "mo:base/Region";
import Blob "mo:base/Blob";
import Nat32 "mo:base/Nat32";
import Prim "mo:prim";

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

  type Address = Nat; // offset into data region, reduced modulo length
  type Index = Nat; // pointer index, not reduced modulo capacity

  public type CircularBufferStableState = {
    length : Nat;
    capacity : Nat;

    index : Region;
    var start : Nat;
    var count : Nat;

    data : Region;
    var start_data : Address;
    var count_data : Nat;

    var pushes : Nat;
  };

  let PAGE_SIZE = 65536;
  func bytesToPages(n : Nat) : Nat64 {
    Nat64.fromNat((n + PAGE_SIZE - 1) / PAGE_SIZE);
  };

  func unwrap<X>(x : ?X) : X {
    switch (x) {
      case (?x) x;
      case (null) Prim.trap("cannot unwrap");
    };
  };

  public class CircularBufferStable<T>(
    serialize : T -> Blob,
    deserialize : Blob -> T,
    capacity : Nat,
    length : Nat,
  ) {
    let POINTER_SIZE = 4;

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
    func pointerOffset(i : Index) : Nat64 {
      Nat64.fromNat(i % (capacity + 1) * POINTER_SIZE);
    };

    func storePointer(i : Index, addr : Address) {
      Region.storeNat32(state().index, pointerOffset(i), Nat32.fromNat(addr));
    };

    func loadPointer(i : Index) : Address {
      Nat32.toNat(Region.loadNat32(state().index, pointerOffset(i)));
    };

    // Load and store data
    func storeData(addr : Address, blob : Blob) {
      Region.storeBlob(state().data, Nat64.fromNat(addr), blob);
    };

    func loadData(addr : Address, len : Nat) : Blob {
      Region.loadBlob(state().data, Nat64.fromNat(addr), len);
    };

    func loadInterval(from : Address, to : Address) : T {
      let blob = if (from < to) {
        loadData(from, to - from);
      } else if (from > to) {
        let sz : Nat = length - from;
        let next1 = loadData(from, sz).vals().next;
        let next2 = loadData(0, to).vals().next;
        Blob.fromArray(Array.tabulate<Nat8>(sz + to, func(i) = if (i < sz) unwrap(next1()) else unwrap(next2())));
      } else {
        "" : Blob;
      };
      deserialize(blob);
    };

    func pop_(s : CircularBufferStableState, take : Bool) : ?T {
      let new_start_data : Address = loadPointer(s.start + 1);
      let item_length = (new_start_data + length - s.start_data : Nat) % length;

      let value = if (take) {
        ?loadInterval(s.start_data, new_start_data);
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
      let item_length = blob.size();

      assert item_length < length;

      if (force) {
        while (s.count == capacity or length < item_length + s.count_data) {
          ignore pop_(s, false);
        };
      } else if (s.count == capacity or length < item_length + s.count_data) {
        return false;
      };

      if (item_length > 0) {
        let end_data = (s.start_data + s.count_data) % length;
        if (end_data + item_length <= length) {
          storeData(end_data, blob);
        } else {
          let next = blob.vals().next;
          let sz : Nat = length - end_data;
          let part1 = Blob.fromArray(Array.tabulate<Nat8>(sz, func(i) = unwrap(next())));
          let part2 = Blob.fromArray(Array.tabulate<Nat8>(item_length - sz, func(i) = unwrap(next())));
          storeData(end_data, part1);
          storeData(0, part2);
        };
      };
      s.count_data += item_length;
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
      let to = loadPointer(i + 1);
      loadInterval(from, to);
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
