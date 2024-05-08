import Blob "mo:base/Blob";
import Region "mo:base/Region";
import Nat64 "mo:base/Nat64";
import Nat8 "mo:base/Nat8";
import Nat16 "mo:base/Nat16";
import Iter "mo:base/Iter";
import Debug "mo:base/Debug";
import Text "mo:base/Text";
import Nat "mo:base/Nat";
import Nat32 "mo:base/Nat32";

module {
  type StableTrieState = {
    region : Region.Region;
    size : Nat;
  };

  public class StableTrie(pointer_size : Nat, children_number : Nat, key_size : Nat, value_size : Nat) {
    assert pointer_size % 2 == 0 and 2 <= pointer_size and pointer_size <= 8;
    assert children_number == 2 or children_number == 4 or children_number == 16 or children_number == 256;
    assert key_size >= 1;

    let children_number_ = Nat64.fromNat(children_number);
    let key_size_ = Nat64.fromNat(key_size);
    let value_size_ = Nat64.fromNat(value_size);
    let pointer_size_ = Nat64.fromNat(pointer_size);
    let address_bits = pointer_size_ * 8 - 1;
    let nodeSize : Nat64 = children_number_ * pointer_size_;
    let leafSize : Nat64 = key_size_ + value_size_;
    let empty_values : Bool = value_size == 0;

    var region_ : ?Region.Region = null;
    var regionSpace : Nat64 = 0;
    var size_ : Nat64 = 0;
    var leaf_count_ : Nat64 = 0;

    func region() : Region.Region {
      switch (region_) {
        case (?r) r;
        case (null) {
          let r = Region.new();
          assert Region.grow(r, 1) != 0xFFFF_FFFF_FFFF_FFFF;
          regionSpace := 65536 - (8 - pointer_size_);
          region_ := ?r;
          size_ := nodeSize;
          regionSpace -= nodeSize;
          r;
        };
      };
    };

    func allocate(region : Region.Region, n : Nat64) : Nat64 {
      assert size_ >> address_bits == 0;
      if (regionSpace < n) {
        assert Region.grow(region, 1) != 0xFFFF_FFFF_FFFF_FFFF;
        regionSpace +%= 65536;
      };
      let pos = size_;
      size_ +%= n;
      regionSpace -%= n;
      pos;
    };

    func newInternalNode(region : Region.Region) : Nat64 {
      allocate(region, nodeSize) << 1;
    };

    func newLeaf(region : Region.Region, key : Blob, value : Blob) : Nat64 {
      let pos = allocate(region, leafSize);
      Region.storeBlob(region, pos, key);
      if (not empty_values) {
        Region.storeBlob(region, pos +% key_size_, value);
      };
      leaf_count_ +%= 1;
      Nat64.bitset(pos << 1, 0);
    };

    let loadMask : Nat64 = switch (pointer_size_) {
      case (8) 0xffff_ffff_ffff_ffff;
      case (6) 0xffff_ffff_ffff;
      case (4) 0xffff_ffff;
      case (2) 0xffff;
      case (_) 0;
    };

    public func getChild(region : Region.Region, node : Nat64, index : Nat8) : Nat64 {
      let offset = node >> 1 +% Nat64.fromIntWrap(Nat8.toNat(index)) * pointer_size_;
      Region.loadNat64(region, offset) & loadMask;
    };

    public func setChild(region : Region.Region, node : Nat64, index : Nat8, child : Nat64) {
      let offset = node >> 1 +% Nat64.fromIntWrap(Nat8.toNat(index)) * pointer_size_;
      switch (pointer_size_) {
        case (8) Region.storeNat64(region, offset, child);
        case (6) {
          Region.storeNat32(region, offset, Nat32.fromNat64(child & 0xffff_ffff));
          Region.storeNat16(region, offset +% 4, Nat16.fromNat32(Nat32.fromNat64(child >> 32)));
        };
        case (4) Region.storeNat32(region, offset, Nat32.fromNat64(child));
        case (2) Region.storeNat16(region, offset, Nat16.fromNat32(Nat32.fromNat64(child)));
        case (_) Debug.trap("Can never happen");
      };
    };

    public func getKey(region : Region.Region, offset : Nat64) : Blob {
      Region.loadBlob(region, offset >> 1, key_size);
    };

    public func value(region : Region.Region, offset : Nat64) : Blob {
      if (empty_values) return "";
      Region.loadBlob(region, offset >> 1 +% Nat64.fromIntWrap(key_size), value_size);
    };

    public func print(region : Region.Region, offset : Nat64) {
      Debug.print(
        Nat64.toText(offset) # " node " # Text.join(
          " ",
          Iter.map<Nat, Text>(
            Iter.range(0, children_number - 1),
            func(x : Nat) : Text = switch (getChild(region, offset, Nat8.fromIntWrap(x))) {
              case (0) "null";
              case (ch) if (Nat64.bittest(ch, 0)) debug_show (getKey(region, ch)) else Nat64.toText(ch);
            },
          ),
        )
      );
      for (x in Iter.range(0, children_number - 1)) {
        switch (getChild(region, offset, Nat8.fromIntWrap(x))) {
          case (0) {};
          case (ch) if (not Nat64.bittest(ch, 0)) print(region, ch);
        };
      };
    };

    let (bitlength, bitmask) : (Nat16, Nat16) = switch (children_number) {
      case (2) (1, 0x1);
      case (4) (2, 0x3);
      case (16) (4, 0xf);
      case (256) (8, 0xff);
      case (_) (0, 0);
    };

    func keyToIndices(key : Blob, depth : Nat16) : () -> Nat8 {
      var skipBits = depth * bitlength;
      let iter = key.vals();
      while (skipBits >= 8) {
        ignore iter.next();
        skipBits -%= 8;
      };
      let ?first = iter.next() else Debug.trap("shoud not happen");
      var byte : Nat16 = (Nat8.toNat16(first) | 256) >> skipBits;
      func _next() : Nat8 {
        if (byte == 1) {
          switch (iter.next()) {
            case (?b) {
              byte := Nat8.toNat16(b) | 256;
            };
            case (null) Debug.trap("should not happen");
          };
        };
        let ret = Nat8.fromNat16(byte & bitmask);
        byte >>= bitlength;
        return ret;
      };
    };

    public func add(key : Blob, value : Blob) : Bool {
      let reg = region();
      var node : Nat64 = 0; // root node
      var old_leaf : Nat64 = 0;

      var depth : Nat16 = 0;

      let next_idx = keyToIndices(key, 0);
      var last = label l : Nat8 loop {
        let idx = next_idx();
        switch (getChild(reg, node, idx)) {
          case (0) {
            setChild(reg, node, idx, newLeaf(reg, key, value));
            return true;
          };
          case (n) {
            if (Nat64.bittest(n, 0)) {
              old_leaf := n;
              break l idx;
            };
            node := n;
            depth +%= 1;
          };
        };
      };

      let old_key = getKey(reg, old_leaf);
      if (key == old_key) {
        return false;
      };

      let next_old_idx = keyToIndices(old_key, depth +% 1);
      label l loop {
        let add = newInternalNode(reg);
        setChild(reg, node, last, add);
        node := add;

        let (a, b) = (next_idx(), next_old_idx());
        if (a == b) {
          last := a;
        } else {
          setChild(reg, node, a, newLeaf(reg, key, value));
          setChild(reg, node, b, old_leaf);
          break l;
        };
      };
      true;
    };

    public func get(key : Blob) : ?Blob {
      let reg = region();
      let next_idx = keyToIndices(key, 0);

      var node : Nat64 = 0;
      loop {
        let idx = next_idx();
        node := switch (getChild(reg, node, idx)) {
          case (0) {
            return null;
          };
          case (n) {
            if (Nat64.bittest(n, 0)) {
              if (getKey(reg, n) == key) return ?value(reg, n) else return null;
            };
            n;
          };
        };
      };

      assert false;
      null;
    };

    public func size() : Nat = Nat64.toNat(size_);

    public func share() : StableTrieState = {
      region = region();
      size = Nat64.toNat(size_);
    };

    public func unshare(data : StableTrieState) {
      switch (region_) {
        case (null) {
          region_ := ?data.region;
        };
        case (_) Debug.trap("Region is already initialized");
      };
      size_ := Nat64.fromNat(data.size);
    };
  };
};
