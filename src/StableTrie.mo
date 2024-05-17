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
  type Region = {
    region : Region.Region;
    var freeSpace : Nat64;
  };

  type StableTrieState = (Region, Region);

  public class StableTrie(pointer_size : Nat, children_number : Nat, key_size : Nat, value_size : Nat) {

    assert pointer_size % 2 == 0 and 2 <= pointer_size and pointer_size <= 8;
    assert children_number == 2 or children_number == 4 or children_number == 16 or children_number == 256;
    assert key_size >= 1;

    let children_number_ = Nat64.fromNat(children_number);
    let key_size_ = Nat64.fromNat(key_size);
    let value_size_ = Nat64.fromNat(value_size);
    let pointer_size_ = Nat64.fromNat(pointer_size);
//    let address_bits = pointer_size_ * 8 - 1;
    let node_size : Nat64 = children_number_ * pointer_size_;
    let leaf_size : Nat64 = key_size_ + value_size_;
    let empty_values : Bool = value_size == 0;

    var regions_ : ?(Region, Region) = null;

    var leaf_count : Nat64 = 0;
    var node_count : Nat64 = 0;

    let loadMask : Nat64 = switch (pointer_size_) {
      case (8) 0xffff_ffff_ffff_ffff;
      case (6) 0xffff_ffff_ffff;
      case (4) 0xffff_ffff;
      case (2) 0xffff;
      case (_) 0;
    };

    let (bitlength, bitmask) : (Nat16, Nat16) = switch (children_number) {
      case (2) (1, 0x1);
      case (4) (2, 0x3);
      case (16) (4, 0xf);
      case (256) (8, 0xff);
      case (_) (0, 0);
    };

    func regions() : (Region, Region) {
      switch (regions_) {
        case (?r) r;
        case (null) {
          let tree : Region = {
            region = Region.new();
            var size = 0;
            var freeSpace = 65536 - (8 - pointer_size_);
          };
          assert Region.grow(tree.region, 1) != 0xFFFF_FFFF_FFFF_FFFF;
          assert newInternalNode(tree) == 0;

          let data : Region = {
            region = Region.new();
            var size = 0;
            var freeSpace = 0;
          };
          regions_ := ?(tree, data);
          (tree, data);
        };
      };
    };

    func allocate(region : Region, n : Nat64) {
      // TODO: assert treeSize >> address_bits == 0;
      if (region.freeSpace < n) {
        assert Region.grow(region.region, 1) != 0xFFFF_FFFF_FFFF_FFFF;
        region.freeSpace +%= 65536;
      };
      region.freeSpace -%= n;
    };

    func newInternalNode(region : Region) : Nat64 {
      allocate(region, node_size);
      let res = node_count << 1;
      node_count +%= 1;
      res
    };

    func newLeaf(region : Region, key : Blob, value : Blob) : Nat64 {
      allocate(region, leaf_size);
      let pos = leaf_count * leaf_size; 
      Region.storeBlob(region.region, pos, key);
      if (not empty_values) {
        Region.storeBlob(region.region, pos +% key_size_, value);
      };
      let res = leaf_count << 1 | 1;
      leaf_count +%= 1;
      res;
    };

    func getOffset(node : Nat64, index : Nat8) : Nat64 {
      (node >> 1) * node_size +% Nat64.fromIntWrap(Nat8.toNat(index)) * pointer_size_;
    };

    public func getChild(region : Region, node : Nat64, index : Nat8) : Nat64 {
      Region.loadNat64(region.region, getOffset(node, index)) & loadMask;
    };

    public func setChild(region_ : Region, node : Nat64, index : Nat8, child : Nat64) {
      let offset = getOffset(node, index);
      let region = region_.region;
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

    public func getKey(region : Region, offset : Nat64) : Blob {
      Region.loadBlob(region.region, (offset >> 1) * leaf_size, key_size);
    };

    public func value(region : Region, offset : Nat64) : Blob {
      if (empty_values) return "";
      Region.loadBlob(region.region, (offset >> 1) * leaf_size +% Nat64.fromIntWrap(key_size), value_size);
    };

    public func print() = print_(regions().0, regions().1, 0);

    func print_(tree : Region, data : Region, offset : Nat64) {
      Debug.print(
        Nat64.toText(offset) # " node " # Text.join(
          " ",
          Iter.map<Nat, Text>(
            Iter.range(0, children_number - 1),
            func(x : Nat) : Text = switch (getChild(tree, offset, Nat8.fromIntWrap(x))) {
              case (0) "null";
              case (ch) if (Nat64.bittest(ch, 0)) debug_show (getKey(data, ch)) else Nat64.toText(ch);
            },
          ),
        )
      );
      for (x in Iter.range(0, children_number - 1)) {
        switch (getChild(tree, offset, Nat8.fromIntWrap(x))) {
          case (0) {};
          case (ch) if (not Nat64.bittest(ch, 0)) print_(tree, data, ch);
        };
      };
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
      let (tree, data) = regions();
      var node : Nat64 = 0; // root node
      var old_leaf : Nat64 = 0;

      var depth : Nat16 = 0;

      let next_idx = keyToIndices(key, 0);
      var last = label l : Nat8 loop {
        let idx = next_idx();
        switch (getChild(tree, node, idx)) {
          case (0) {
            setChild(tree, node, idx, newLeaf(data, key, value));
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

      let old_key = getKey(data, old_leaf);
      if (key == old_key) {
        return false;
      };

      let next_old_idx = keyToIndices(old_key, depth +% 1);
      label l loop {
        let add = newInternalNode(tree);
        setChild(tree, node, last, add);
        node := add;

        let (a, b) = (next_idx(), next_old_idx());
        if (a == b) {
          last := a;
        } else {
          setChild(tree, node, a, newLeaf(data, key, value));
          setChild(tree, node, b, old_leaf);
          break l;
        };
      };
      true;
    };

    public func get(key : Blob) : ?Blob {
      let (tree, data) = regions();
      let next_idx = keyToIndices(key, 0);

      var node : Nat64 = 0;
      loop {
        let idx = next_idx();
        node := switch (getChild(tree, node, idx)) {
          case (0) {
            return null;
          };
          case (n) {
            if (Nat64.bittest(n, 0)) {
              if (getKey(data, n) == key) return ?value(data, n) else return null;
            };
            n;
          };
        };
      };

      assert false;
      null;
    };

    public func size() : Nat = Nat64.toNat(node_count * node_size + leaf_count * leaf_size);

    public func leafCount() : Nat = Nat64.toNat(leaf_count);

    public func nodeCount() : Nat = Nat64.toNat(node_count);

    public func share() : StableTrieState = regions();

    public func unshare(data : StableTrieState) {
      switch (regions_) {
        case (null) {
          regions_ := ?data;
        };
        case (_) Debug.trap("Region is already initialized");
      };
    };
  };
};
