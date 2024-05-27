import Blob "mo:base/Blob";
import Region "mo:base/Region";
import Nat64 "mo:base/Nat64";
import Nat8 "mo:base/Nat8";
import Nat16 "mo:base/Nat16";
import Debug "mo:base/Debug";
import Nat "mo:base/Nat";
import Nat32 "mo:base/Nat32";
import Array "mo:base/Array";
import Iter "mo:base/Iter";

module {
  type Region = {
    region : Region.Region;
    var freeSpace : Nat64;
  };

  type StableTrieMapState = {
    nodes : Region;
    leaves : Region;
  };

  type StableData = (StableTrieMapState, Nat64, Nat64);

  public class StableTrieMap(pointer_size : Nat, aridity : Nat, root_aridity : Nat, key_size : Nat, value_size : Nat) {

    assert switch (pointer_size) {
      case (2 or 4 or 5 or 6 or 8) true;
      case (_) false;
    };
    assert switch (aridity) {
      case (2 or 4 or 16 or 256) true;
      case (_) false;
    };
    assert key_size >= 1;

    let aridity_ = Nat64.fromNat(aridity);
    let key_size_ = Nat64.fromNat(key_size);
    let value_size_ = Nat64.fromNat(value_size);
    let pointer_size_ = Nat64.fromNat(pointer_size);
    let root_aridity_ = Nat64.fromNat(root_aridity);

    let loadMask : Nat64 = switch (pointer_size_) {
      case (8) 0xffff_ffff_ffff_ffff;
      case (6) 0xffff_ffff_ffff;
      case (5) 0xffff_ffff_ff;
      case (4) 0xffff_ffff;
      case (2) 0xffff;
      case (_) 0;
    };

    let (bitlength, bitmask) : (Nat16, Nat16) = switch (aridity) {
      case (2) (1, 0x1);
      case (4) (2, 0x3);
      case (16) (4, 0xf);
      case (256) (8, 0xff);
      case (_) (0, 0);
    };
    let bitlength_ = Nat32.toNat64(Nat16.toNat32(bitlength));

    let max_address = 2 ** (pointer_size_ * 8 - 1);

    assert Nat64.bitcountNonZero(root_aridity_) == 1; // 2-power
    let root_bitlength_ = Nat64.bitcountTrailingZero(root_aridity_);
    assert root_bitlength_ > 0 and root_bitlength_ % bitlength_ == 0; // => root_bitlength_ >= bitlength_
    assert root_bitlength_ <= key_size_ * 8;

    let root_depth = Nat32.toNat16(Nat64.toNat32(root_bitlength_ / bitlength_));
    let root_bitlength = Nat32.toNat16(Nat64.toNat32(root_bitlength_));

    let node_size : Nat64 = aridity_ * pointer_size_;
    let leaf_size : Nat64 = key_size_ + value_size_;
    let root_size : Nat64 = root_aridity_ * pointer_size_;
    let offset_base : Nat64 = root_size - node_size;
    let padding : Nat64 = 8 - pointer_size_;
    let empty_values : Bool = value_size == 0;

    var regions_ : ?StableTrieMapState = null;

    var leaf_count : Nat64 = 0;
    var node_count : Nat64 = 0;

    var storePointer : (offset : Nat64, child : Nat64) -> () = func(_, _) {};

    func regions() : StableTrieMapState {
      switch (regions_) {
        case (?r) r;
        case (null) {
          let nodes_region = Region.new();
          let nodes : Region = {
            region = nodes_region;
            var freeSpace = 0;
          };
          let pages = (root_size + padding + 65536 - 1) / 65536;
          assert Region.grow(nodes.region, pages) != 0xFFFF_FFFF_FFFF_FFFF;
          nodes.freeSpace := pages * 65536 - root_size - padding;
          node_count := 1;

          let leaves : Region = {
            region = Region.new();
            var freeSpace = 0;
          };

          let ret = { nodes = nodes; leaves = leaves };
          regions_ := ?ret;
          storePointer := switch (pointer_size_) {
            case (8) func(offset, child) = Region.storeNat64(nodes_region, offset, child);
            case (6) func(offset, child) {
              Region.storeNat32(nodes_region, offset, Nat32.fromNat64(child & 0xffff_ffff));
              Region.storeNat16(nodes_region, offset +% 4, Nat16.fromNat32(Nat32.fromNat64(child >> 32)));
            };
            case (5) func(offset, child) {
              Region.storeNat32(nodes_region, offset, Nat32.fromNat64(child & 0xffff_ffff));
              Region.storeNat8(nodes_region, offset +% 4, Nat8.fromNat16(Nat16.fromNat32(Nat32.fromNat64(child >> 32))));
            };
            case (4) func(offset, child) = Region.storeNat32(nodes_region, offset, Nat32.fromNat64(child));
            case (2) func(offset, child) = Region.storeNat16(nodes_region, offset, Nat16.fromNat32(Nat32.fromNat64(child)));
            case (_) Debug.trap("Can never happen");
          };

          ret;
        };
      };
    };

    // allocate can only be used for n <= 65536
    func allocate(region : Region, n : Nat64) {
      if (region.freeSpace < n) {
        assert Region.grow(region.region, 1) != 0xFFFF_FFFF_FFFF_FFFF;
        region.freeSpace +%= 65536;
      };
      region.freeSpace -%= n;
    };

    func newInternalNode(region : Region) : ?Nat64 {
      if (node_count == max_address) return null;

      allocate(region, node_size);
      let nc = node_count;
      node_count +%= 1;
      ?(nc << 1);
    };

    func newLeaf(region : Region, key : Blob) : ?Nat64 {
      if (leaf_count == max_address) return null;

      allocate(region, leaf_size);
      let lc = leaf_count;
      let pos = leaf_count *% leaf_size;
      leaf_count +%= 1;
      Region.storeBlob(region.region, pos, key);
      ?((lc << 1) | 1);
    };

    func getOffset(node : Nat64, index : Nat64) : Nat64 {
      let delta = index *% pointer_size_;
      if (node == 0) return delta; // root node
      (offset_base +% (node >> 1) *% node_size) +% delta;
    };

    public func getChild(region : Region, node : Nat64, index : Nat64) : Nat64 {
      Region.loadNat64(region.region, getOffset(node, index)) & loadMask;
    };

    public func setChild(node : Nat64, index : Nat64, child : Nat64) {
      let offset = getOffset(node, index);
      storePointer(offset, child);
    };

    public func getKey(region : Region, index : Nat64) : Blob {
      Region.loadBlob(region.region, index * leaf_size, key_size);
    };

    public func getValue(region : Region, index : Nat64) : Blob {
      if (empty_values) return "";
      Region.loadBlob(region.region, index * leaf_size +% Nat64.fromIntWrap(key_size), value_size);
    };

    public func setValue(region : Region, index : Nat64, value : Blob) {
      if (empty_values) return;
      Region.storeBlob(region.region, index * leaf_size +% Nat64.fromIntWrap(key_size), value);
    };

    func keyToIndices_(key : Blob, depth : Nat16) : () -> Nat64 {
      let bytes = Blob.toArray(key);
      var pos : Nat16 = depth * bitlength;

      func _next() : Nat64 {
        // if applicable, calculate the root index
        if (depth == 0 and pos == 0) {
          pos := root_bitlength;
          // read last byte first
          var byte_pos : Nat16 = pos >> 3;
          let last_byte = Nat8.toNat16(bytes[Nat16.toNat(byte_pos)]);
          let masked = last_byte & (0xff00 <<> (pos & 0x7));
          var root_index = Nat64.fromIntWrap(Nat16.toNat(masked));
          // read full bytes in reverse order
          while (byte_pos > 0) {
            byte_pos -%= 1;
            root_index <<= 8;
            root_index |= Nat64.fromIntWrap(Nat8.toNat(bytes[Nat16.toNat(byte_pos)]));
          };
          // return result
          return root_index;
        };
        // calculate next non-root index
        let ret = (Nat8.toNat16(bytes[Nat16.toNat(pos >> 3)]) >> (pos & 0x7)) & bitmask;
        pos +%= bitlength;
        return Nat64.fromIntWrap(Nat16.toNat(ret));
      };
    };

    public func keyToIndices(key : Blob, depth : Nat16) : () -> Nat64 {
      let bytes = Blob.toArray(key);
      var pos : Nat16 = 0;

      func _next() : Nat64 {
        if (pos == 0) {
          if (depth == 0) {
            var skipBits = root_bitlength;
            var length : Nat64 = 0;
            var result : Nat64 = 0;
            var i = 0;
            while (skipBits >= 8) {
              let b = bytes[i];
              i += 1;
              result |= Nat32.toNat64(Nat16.toNat32(Nat8.toNat16(b))) << length;
              length +%= 8;
              skipBits -%= 8;
            };
            result |= (Nat32.toNat64(Nat16.toNat32(Nat8.toNat16(bytes[i]) & ((1 << skipBits) - 1)))) << length;
            pos := root_bitlength;
            return result;
          } else {
            pos := depth * bitlength;
          };
        };
        let ret = (Nat8.toNat16(bytes[Nat16.toNat(pos >> 3)]) >> (pos & 0x7)) & bitmask;
        pos +%= bitlength;
        return Nat64.fromIntWrap(Nat16.toNat(ret));
      };
    };

    func put_(nodes : Region, leaves : Region, key : Blob, value : Blob) : ?Nat64 {
      assert key.size() == key_size and value.size() == value_size;

      var node : Nat64 = 0;
      var old_leaf : Nat64 = 0;
      var depth : Nat16 = root_depth;
      let next_idx = keyToIndices(key, 0);

      var last = label l : Nat64 loop {
        let idx = next_idx();
        switch (getChild(nodes, node, idx)) {
          case (0) {
            let ?leaf = newLeaf(leaves, key) else return null;

            setChild(node, idx, leaf);
            return ?(leaf >> 1);
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

      let index = old_leaf >> 1;
      let old_key = getKey(leaves, index);
      if (key == old_key) {
        return ?index;
      };

      let next_old_idx = keyToIndices(old_key, depth);
      label l loop {
        let ?add = newInternalNode(nodes) else {
          setChild(node, last, old_leaf);
          return null;
        };
        setChild(node, last, add);
        node := add;

        let (a, b) = (next_idx(), next_old_idx());
        if (a == b) {
          last := a;
        } else {
          setChild(node, b, old_leaf);
          let ?leaf = newLeaf(leaves, key) else return null;
          setChild(node, a, leaf);
          return ?(leaf >> 1);
        };
      };
      Debug.trap("Unreacheable");
    };

    public func put(key : Blob, value : Blob) : ?Nat {
      let { leaves; nodes } = regions();

      let ?leaf = put_(nodes, leaves, key, value) else return null;
      setValue(leaves, leaf, value);
      ?Nat64.toNat(leaf);
    };

    public func lookupOrPut(key : Blob, value : Blob) : ?(Blob, Nat) {
      let { leaves; nodes } = regions();

      let ?leaf = put_(nodes, leaves, key, value) else return null;
      let ret_value = if (leaf == leaf_count - 1) {
        setValue(leaves, leaf, value);
        value;
      } else {
        getValue(leaves, leaf);
      };
      ?(ret_value, Nat64.toNat(leaf));
    };

    public func lookup(key : Blob) : ?(Blob, Nat) {
      assert key.size() == key_size;
      let { leaves; nodes } = regions();
      let next_idx = keyToIndices(key, 0);

      var node : Nat64 = 0;
      loop {
        let idx = next_idx();
        node := switch (getChild(nodes, node, idx)) {
          case (0) {
            return null;
          };
          case (n) {
            if (n & 1 == 1) {
              let index = n >> 1;
              return if (getKey(leaves, index) == key) ?(getValue(leaves, index), Nat64.toNat(index)) else null;
            };
            n;
          };
        };
      };

      Debug.trap("Can never happen");
    };

    public func get(index : Nat) : ?(Blob, Blob) {
      let { leaves } = regions();
      let index_ = Nat64.fromNat(index);
      if (index_ >= leaf_count) return null;
      ?(getKey(leaves, index_), getValue(leaves, index_));
    };

    public func slice(left : Nat, right : Nat) : [(Blob, Blob)] {
      let { leaves } = regions();
      let l = Nat64.fromNat(left);
      let r = Nat64.fromNat(right);
      if (not (l < r and r <= leaf_count)) return [];
      Array.tabulate<(Blob, Blob)>(
        right - left,
        func(i) {
          let index = Nat64.fromNat(i);
          (getKey(leaves, index), getValue(leaves, index));
        },
      );
    };

    public func vals() : Iter.Iter<(Blob, Blob)> {
      object {
        let stack = Array.init<(Nat64, Nat64)>(key_size * 8 / Nat16.toNat(bitlength), (0, 0));
        var depth = 1;
        stack[0] := (0, 0);
        let { nodes; leaves } = regions();

        public func next() : ?(Blob, Blob) {
          let leaf = label l : ?Nat64 loop {
            let (node, i) = stack[depth - 1];
            let max = if (depth > 1) aridity_ else root_aridity_;
            if (i < max) {
              let child = getChild(nodes, node, i);
              if (child == 0) {
                stack[depth - 1] := (node, i + 1);
                continue l;
              };
              if (child & 1 == 1) {
                stack[depth - 1] := (node, i + 1);
                break l(?(child >> 1));
              };
              stack[depth] := (child, 0);
              depth += 1;
            } else {
              if (depth == 1) break l null;
              depth -= 1;
              let (prev_node, prev_i) = stack[depth - 1];
              stack[depth - 1] := (prev_node, prev_i + 1);
            };
          };
          let ?leaf_ = leaf else return null;
          ?(getKey(leaves, leaf_), getValue(leaves, leaf_));
        };
      };
    };

    public func size() : Nat = Nat64.toNat(root_size + (node_count - 1) * node_size + leaf_count * leaf_size);

    public func leafCount() : Nat = Nat64.toNat(leaf_count);

    public func nodeCount() : Nat = Nat64.toNat(node_count);

    public func share() : StableData = (regions(), node_count, leaf_count);

    public func unshare(leaves : StableData) {
      switch (regions_) {
        case (null) {
          regions_ := ?leaves.0;
          node_count := leaves.1;
          leaf_count := leaves.2;
        };
        case (_) Debug.trap("Region is already initialized");
      };
    };
  };
};
