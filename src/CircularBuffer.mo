import Array "mo:base/Array";
import Nat "mo:base/Nat";
import Iter "mo:base/Iter";
import Debug "mo:base/Debug";
import Int "mo:base/Int";
import Nat64 "mo:base/Nat64";
import Region "mo:base/Region";
import Blob "mo:base/Blob";
import Option "mo:base/Option";
import Prim "mo:⛔";
import MemoryRegion "mo:memory-region/MemoryRegion";

module CircularBuffer {
  /// Circular buffer, which preserves amount of pushed values
  public class CircularBufferBase<T, S>(
    array : {
      get : (Nat) -> ?T;
      add : (?T) -> ();
      share : () -> (S);
      unshare : S -> ();
    },
    capacity : Nat,
  ) {
    assert capacity != 0;

    var pushes : Int = 0;

    /// Number of items that were ever pushed to the buffer
    public func pushesAmount() : Nat = Int.abs(pushes);

    /// Insert value into the buffer
    public func push(item : T) {
      array.add(?item);
      pushes += 1;
    };

    /// Return interval `[start, end)` of indices of elements available.
    public func available() : (Nat, Nat) {
      (Int.abs(Int.max(0, pushes - capacity)), Int.abs(pushes));
    };

    /// Returns single element added with number `index` or null if element is not available or index out of bounds.
    public func get(index : Nat) : ?T {
      let (l, r) = available();
      if (l <= index and index < r) {
        array.get(index % capacity);
      } else {
        null;
      };
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
          let ret = array.get(start);
          start += 1;
          if (start == capacity) start := 0;
          i += 1;
          ret;
        };
      };
    };

    /// Share stable content
    public func share() : (S, Int) = (array.share(), pushes);

    /// Unshare from stable content
    public func unshare(data : (S, Int)) {
      array.unshare(data.0);
      pushes := data.1;
    };
  };

  public func CircularBuffer<T>(capacity : Nat) : CircularBufferBase<T, (Nat, [var ?T])> {
    let array = object {
      let array : [var ?T] = Array.init(capacity, null);
      var last : Nat = 0;

      public func get(index : Nat) : ?T {
        array[index];
      };

      public func add(elem : ?T) {
        array[last] := elem;
        last += 1;
        if (last == capacity) last := 0;
      };

      public func share() : ((Nat, [var ?T])) = (last, array);

      public func unshare(value : (Nat, [var ?T])) {
        last := value.0;
        for (i in Iter.range(0, capacity - 1)) {
          array[i] := value.1 [i];
        };
      };
    };
    CircularBufferBase<T, (Nat, [var ?T])>(array, capacity);
  };

  module Buffer {
    public type StableBuffer = {
      memory_region : MemoryRegion.MemoryRegion;

      elems : Region;
      var elems_count : Nat64;
    };

    let elem_size = 16 : Nat64; // two Nat64s, for pos and size.

    func regionEnsureSizeBytes(r : Region, new_byte_count : Nat64) {
      let pages = Region.size(r);
      if (new_byte_count > pages << 16) {
        let new_pages = ((new_byte_count + ((1 << 16) - 1)) / (1 << 16)) - pages;
        assert Region.grow(r, new_pages) == pages;
      };
    };

    public func new() : StableBuffer = {
      memory_region = MemoryRegion.new();
      elems = Region.new();
      var elems_count = 0;
    };

    public func add(self : StableBuffer, blob : Blob) {
      let elem_i = self.elems_count;
      self.elems_count += 1;

      let elem_pos = Nat64.fromNat(MemoryRegion.addBlob(self.memory_region, blob));

      regionEnsureSizeBytes(self.elems, self.elems_count * elem_size);
      Region.storeNat64(self.elems, elem_i * elem_size + 0, elem_pos);
      Region.storeNat64(self.elems, elem_i * elem_size + 8, Prim.natToNat64(blob.size()));
    };

    public func get(self : StableBuffer, index : Nat64) : Blob {
      assert index < self.elems_count;
      let pos = Region.loadNat64(self.elems, index * elem_size);
      let size = Region.loadNat64(self.elems, index * elem_size + 8);
      MemoryRegion.loadBlob(self.memory_region, Prim.nat64ToNat(pos), Prim.nat64ToNat(size));
    };

    public func put(self : StableBuffer, index : Nat64, blob : Blob) {
      assert index < self.elems_count;
      let pos = Region.loadNat64(self.elems, index * elem_size);
      let size = Region.loadNat64(self.elems, index * elem_size + 8);
      ignore MemoryRegion.removeBlob(self.memory_region, Prim.nat64ToNat(pos), Prim.nat64ToNat(size));

      let elem_pos = Nat64.fromNat(MemoryRegion.addBlob(self.memory_region, blob));

      Region.storeNat64(self.elems, index * elem_size + 0, elem_pos);
      Region.storeNat64(self.elems, index * elem_size + 8, Prim.natToNat64(blob.size()));
    };

    public func size(self : StableBuffer) : Nat {
      Nat64.toNat(self.elems_count);
    };
  };

  public func StableCircularBuffer<T>(
    capacity : Nat,
    serialize : (?T) -> Blob,
    deserialize : (Blob) -> ?T,
  ) : CircularBufferBase<T, (Nat, Bool, Buffer.StableBuffer)> {
    let array = object {
      var a : ?Buffer.StableBuffer = null;
      var last = 0;
      var full = false;

      func array() : Buffer.StableBuffer {
        switch (a) {
          case (null) {
            let buf = Buffer.new();
            a := ?buf;
            buf;
          };
          case (?buf) {
            buf;
          };
        };
      };

      public func get(index : Nat) : ?T {
        deserialize(Buffer.get(array(), Nat64.fromNat(index)));
      };

      public func add(value : ?T) {
        if (not full) {
          Buffer.add(array(), serialize(value));
        } else {
          Buffer.put(array(), Nat64.fromNat(last), serialize(value));
        };
        last += 1;
        if (last == capacity) {
          last := 0;
          full := true;
        };
      };

      public func share() : ((Nat, Bool, Buffer.StableBuffer)) {
        (last, full, array());
      };

      public func unshare(data : (Nat, Bool, Buffer.StableBuffer)) {
        last := data.0;
        full := data.1;
        switch (a) {
          case (null) {
            a := ?data.2;
          };
          case (_) {
            assert false;
          };
        };
      };
    };

    CircularBufferBase<T, (Nat, Bool, Buffer.StableBuffer)>(array, capacity);
  };
};
