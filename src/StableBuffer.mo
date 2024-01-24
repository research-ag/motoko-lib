import Prim "mo:⛔";
import Region "mo:base/Region";
import Nat64 "mo:base/Nat64";

module Buffer {
  public type StableData = {
    bytes : Region;
    var bytes_count : Nat64;

    elems : Region;
    var elems_count : Nat64;
  };

  public class StableBuffer<T>(serialize : (T) -> Blob, deserialize : (Blob) -> T) {
    var state_ : ?StableData = null;

    let ELEMENT_SIZE : Nat64 = 16;

    func regionEnsureSizeBytes(r : Region, new_byte_count : Nat64) {
      let pages = Region.size(r);
      if (new_byte_count > pages << 16) {
        let new_pages = ((new_byte_count + ((1 << 16) - 1)) / (1 << 16)) - pages;
        assert Region.grow(r, new_pages) == pages;
      };
    };

    public func state() : StableData {
      switch (state_) {
        case (?s) s;
        case (null) {
          let s : StableData = {
            bytes = Region.new();
            var bytes_count = 0;
            elems = Region.new();
            var elems_count = 0;
          };
          state_ := ?s;
          s;
        };
      };
    };

    public func add(item : T) {
      let self = state();

      let blob = serialize(item);

      let elem_i = self.elems_count;
      self.elems_count += 1;

      let elem_pos = self.bytes_count;
      self.bytes_count += Prim.natToNat64(blob.size());

      regionEnsureSizeBytes(self.bytes, self.bytes_count);
      if (blob.size() != 0) {
        Region.storeBlob(self.bytes, elem_pos, blob);
      };

      regionEnsureSizeBytes(self.elems, self.elems_count * ELEMENT_SIZE);
      Region.storeNat64(self.elems, elem_i * ELEMENT_SIZE + 0, elem_pos);
      Region.storeNat64(self.elems, elem_i * ELEMENT_SIZE + 8, Nat64.fromNat(blob.size()));
    };

    public func get(index : Nat) : T {
      let self = state();
      let i = Nat64.fromNat(index);
      assert i < self.elems_count;
      let size = Region.loadNat64(self.elems, i * ELEMENT_SIZE + 8);
      let blob = if (size != 0) {
        let pos = Region.loadNat64(self.elems, i * ELEMENT_SIZE);
        Region.loadBlob(self.bytes, pos, Nat64.toNat(size));
      } else {
        "" : Blob;
      };
      deserialize(blob);
    };

    public func size() : Nat {
      let self = state();
      Nat64.toNat(self.elems_count);
    };

    public func bytes() : Nat {
      let self = state();
      Nat64.toNat(self.bytes_count);
    };

    public func pages() : Nat {
      let self = state();
      Nat64.toNat(Region.size(self.elems) + Region.size(self.bytes));
    };

    public func share() : StableData = state();

    public func unshare(data : StableData) {
      switch (state_) {
        case (null) {
          state_ := ?data;
        };
        case (?s) {
          assert false;
        };
      };
    };
  };
};
