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

  type StableTrieState = {
    nodes : Region;
    leaves : Region;
    root : Region.Region;
  };

  public class StableTrie(pointer_size : Nat, children_number : Nat, root_size : Nat, key_size : Nat, value_size : Nat) {

    assert pointer_size % 2 == 0 and 2 <= pointer_size and pointer_size <= 8;
    assert children_number == 2 or children_number == 4 or children_number == 16 or children_number == 256;
    assert key_size >= 1;
    let children_number_ = Nat64.fromNat(children_number);
    let key_size_ = Nat64.fromNat(key_size);
    let value_size_ = Nat64.fromNat(value_size);
    let pointer_size_ = Nat64.fromNat(pointer_size);
    let root_size_ = Nat64.fromNat(root_size);

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
    let bitlength_ = Nat32.toNat64(Nat16.toNat32(bitlength));

    let max_nodes = 2 ** (pointer_size_ * 8 - 1) - key_size_ * 8 / bitlength_ + 1;
    assert Nat64.bitcountNonZero(root_size_) == 1 and Nat64.bitcountTrailingZero(root_size_) % bitlength_ == 0;
    let root_depth = Nat32.toNat16(Nat64.toNat32(Nat64.bitcountTrailingZero(root_size_) / bitlength_));
    //assert root depth <= key depth
    let node_size : Nat64 = children_number_ * pointer_size_;
    let leaf_size : Nat64 = key_size_ + value_size_;
    let empty_values : Bool = value_size == 0;

    var regions_ : ?StableTrieState = null;

    var leaf_count : Nat64 = 0;
    var node_count : Nat64 = 0;

    func regions() : StableTrieState {
      switch (regions_) {
        case (?r) r;
        case (null) {
          let nodes : Region = {
            region = Region.new();
            var size = 0;
            var freeSpace = 65536 - (8 - pointer_size_);
          };
          assert Region.grow(nodes.region, 1) != 0xFFFF_FFFF_FFFF_FFFF;
          // 0 pointer stands for null
          assert newInternalNode(nodes) == 0;

          let leaves : Region = {
            region = Region.new();
            var size = 0;
            var freeSpace = 0;
          };

          let root = Region.new();
          assert Region.grow(root, (root_size_ * pointer_size_ + (8 - pointer_size_) + 65536 - 1) / 65536) != 0xFFFF_FFFF_FFFF_FFFF;

          let ret = { nodes = nodes; leaves = leaves; root = root };
          regions_ := ?ret;
          ret;
        };
      };
    };

    // allocate can only be used for n <= 65536
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
      let nc = node_count;
      node_count +%= 1;
      nc << 1;
    };

    func newLeaf(region : Region, key : Blob, value : Blob) : Nat64 {
      allocate(region, leaf_size);
      let lc = leaf_count;
      let pos = leaf_count *% leaf_size;
      leaf_count +%= 1;
      Region.storeBlob(region.region, pos, key);
      if (not empty_values) {
        Region.storeBlob(region.region, pos +% key_size_, value);
      };
      (lc << 1) | 1;
    };

    func getOffset(node : Nat64, index : Nat64) : Nat64 {
      (node >> 1) *% node_size +% index *% pointer_size_;
    };

    public func getChild(region : Region, root : Region.Region, node : Nat64, index : Nat64) : Nat64 {
      if (node != 0) {
        Region.loadNat64(region.region, getOffset(node, index)) & loadMask;
      } else {
        Region.loadNat64(root, index * pointer_size_) & loadMask;
      };
    };

    public func setChild(region_ : Region, root : Region.Region, node : Nat64, index : Nat64, child : Nat64) {
      let (offset, region) = if (node != 0) {
        (getOffset(node, index), region_.region);
      } else {
        (index * pointer_size_, root);
      };
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

    // public func print() = print_(regions().0, regions().1, 0);

    // func print_(nodes : Region, leaves : Region, offset : Nat64) {
    //   Debug.print(
    //     Nat64.toText(offset) # " node " # Text.join(
    //       " ",
    //       Iter.map<Nat, Text>(
    //         Iter.range(0, children_number - 1),
    //         func(x : Nat) : Text = switch (getChild(nodes, offset, Nat8.fromIntWrap(x))) {
    //           case (0) "null";
    //           case (ch) if (Nat64.bittest(ch, 0)) debug_show (getKey(leaves, ch)) else Nat64.toText(ch);
    //         },
    //       ),
    //     )
    //   );
    //   for (x in Iter.range(0, children_number - 1)) {
    //     switch (getChild(nodes, offset, Nat8.fromIntWrap(x))) {
    //       case (0) {};
    //       case (ch) if (not Nat64.bittest(ch, 0)) print_(nodes, leaves, ch);
    //     };
    //   };
    // };

    func indexInRoot(key : Blob) : Nat64 {
      let iter = key.vals();
      var skipBits = Nat64.bitcountTrailingZero(root_size_);
      var length : Nat64 = 0;
      var result : Nat64 = 0;
      while (skipBits >= 8) {
        switch (iter.next()) {
          case (?b) {
            result |= Nat32.toNat64(Nat16.toNat32(Nat8.toNat16(b))) << length;
            length += 8;
            skipBits -= 8;
          };
          case (null) Debug.trap("shoud not happen");
        };
      };
      let ?first = iter.next() else Debug.trap("shoud not happen");
      result |= (Nat32.toNat64(Nat16.toNat32(Nat8.toNat16(first))) & ((1 << skipBits) - 1)) << length;
      result;
    };

    func keyToIndices(key : Blob, depth : Nat16) : () -> Nat64 {
      let iter = key.vals();
      func next() : Nat8 {
        let ?res = iter.next() else Debug.trap("shoud not happen");
        res;
      };
      var byte : Nat16 = 0;

      func _next() : Nat64 {
        if (byte == 0) {
          if (depth == 0) {
            var skipBits = root_depth * bitlength;
            var length : Nat64 = 0;
            var result : Nat64 = 0;
            while (skipBits >= 8) {
              let b = next();
              result |= Nat32.toNat64(Nat16.toNat32(Nat8.toNat16(b))) << length;
              length +%= 8;
              skipBits -%= 8;
            };
            let first = next();
            result |= (Nat32.toNat64(Nat16.toNat32(Nat8.toNat16(first) & ((1 << skipBits) - 1)))) << length;
            byte := (Nat8.toNat16(first) | 256) >> skipBits;
            return result;
          } else {
            var skipBits : Nat16 = depth * bitlength;
            while (skipBits >= 8) {
              ignore iter.next();
              skipBits -%= 8;
            };
            let first = next();
            byte := (Nat8.toNat16(first) | 256) >> skipBits;
          };
        };
        if (byte == 1) {
          byte := Nat8.toNat16(next()) | 256;
        };
        let ret = byte & bitmask;
        byte >>= bitlength;
        return Nat32.toNat64(Nat16.toNat32(ret));
      };
    };

    public func add(key : Blob, value : Blob) : Bool {
      assert node_count <= max_nodes;
      let { leaves; root; nodes } = regions();

      var node : Nat64 = 0;
      var old_leaf : Nat64 = 0;
      var depth : Nat16 = root_depth;
      let next_idx = keyToIndices(key, 0);

      var last = label l : Nat64 loop {
        let idx = next_idx();
        switch (getChild(nodes, root, node, idx)) {
          case (0) {
            setChild(nodes, root, node, idx, newLeaf(leaves, key, value));
            return true;
          };
          case (n) {
            if (n & 1 == 1) {
              old_leaf := n;
              break l idx;
            };
            node := n;
            depth +%= 1;
          };
        };
      };

      let old_key = getKey(leaves, old_leaf);
      if (key == old_key) {
        return false;
      };

      let next_old_idx = keyToIndices(old_key, depth);
      label l loop {
        let add = newInternalNode(nodes);
        setChild(nodes, root, node, last, add);
        node := add;

        let (a, b) = (next_idx(), next_old_idx());
        if (a == b) {
          last := a;
        } else {
          setChild(nodes, root, node, a, newLeaf(leaves, key, value));
          setChild(nodes, root, node, b, old_leaf);
          break l;
        };
      };
      true;
    };

    public func get(key : Blob) : ?Blob {
      let { leaves; root; nodes } = regions();
      let next_idx = keyToIndices(key, 0);

      var node : Nat64 = 0;
      loop {
        let idx = next_idx();
        node := switch (getChild(nodes, root, node, idx)) {
          case (0) {
            return null;
          };
          case (n) {
            if (n & 1 == 1) {
              if (getKey(leaves, n) == key) return ?value(leaves, n) else return null;
            };
            n;
          };
        };
      };

      assert false;
      null;
    };

    public func size() : Nat = Nat64.toNat(root_size_ * pointer_size_ + node_count * node_size + leaf_count * leaf_size);

    public func leafCount() : Nat = Nat64.toNat(leaf_count);

    public func nodeCount() : Nat = Nat64.toNat(node_count);

    public func share() : StableTrieState = regions();

    public func unshare(leaves : StableTrieState) {
      switch (regions_) {
        case (null) {
          regions_ := ?leaves;
        };
        case (_) Debug.trap("Region is already initialized");
      };
    };
  };
};
