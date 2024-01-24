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
    var maxPages : ?Nat64 = null;

    let ELEMENT_SIZE : Nat64 = 16;

    func requiredPages(bytes : Nat64) : Nat64 = ((bytes + ((1 << 16) - 1)) / (1 << 16));

    func regionEnsureSizeBytes(r : Region, new_pages : Nat64) {
      let pages = Region.size(r);
      if (new_pages > pages) {
        let add_pages = new_pages - pages;
        assert Region.grow(r, add_pages) == pages;
      };
    };

    func state() : StableData {
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

    public func add(item : T) : Bool {
      let self = state();

      let blob = serialize(item);
      let blob_size = Nat64.fromNat(blob.size());

      let new_bytes_pages = requiredPages(self.bytes_count + blob_size);
      let new_elems_pages = requiredPages((self.elems_count + 1) * ELEMENT_SIZE);

      switch (maxPages) {
        case (null) {};
        case (?x) {
          if (new_elems_pages + new_bytes_pages > x) {
            return false;
          };
        };
      };

      let elem_pos = self.bytes_count;

      regionEnsureSizeBytes(self.bytes, new_bytes_pages);
      if (blob.size() != 0) {
        Region.storeBlob(self.bytes, elem_pos, blob);
      };

      regionEnsureSizeBytes(self.elems, new_elems_pages);
      let elem_i = self.elems_count * ELEMENT_SIZE;
      Region.storeNat64(self.elems, elem_i + 0, elem_pos);
      Region.storeNat64(self.elems, elem_i + 8, blob_size);
      self.elems_count += 1;
      self.bytes_count += blob_size;
      true;
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

    public func setMaxPages(max : ?Nat64) {
      maxPages := max;
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
