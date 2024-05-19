import Blob "mo:base/Blob";
import Region "mo:base/Region";
import Nat64 "mo:base/Nat64";
import Nat8 "mo:base/Nat8";
import Nat16 "mo:base/Nat16";
import Debug "mo:base/Debug";
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
  };

  type StableData = (StableTrieState, Nat64, Nat64);

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

    assert root_size_ > 1 and Nat64.bitcountNonZero(root_size_) == 1 and Nat64.bitcountTrailingZero(root_size_) % bitlength_ == 0;
    let root_depth = Nat32.toNat16(Nat64.toNat32(Nat64.bitcountTrailingZero(root_size_) / bitlength_));
    assert Nat16.toNat(root_depth) <= Nat64.toNat(key_size_ * 8 / bitlength_);
    
    let node_size : Nat64 = children_number_ * pointer_size_;
    let leaf_size : Nat64 = key_size_ + value_size_;
    let empty_values : Bool = value_size == 0;

    var regions_ : ?StableTrieState = null;

    var leaf_count : Nat64 = 0;
    // node 0 stands for root
    var node_count : Nat64 = 1;

    func regions() : StableTrieState {
      switch (regions_) {
        case (?r) r;
        case (null) {
          let nodes : Region = {
            region = Region.new();
            var freeSpace = 0;
          };
          let pages = (root_size_ * pointer_size_ + (8 - pointer_size_) + 65536 - 1) / 65536 + 1;
          assert Region.grow(nodes.region, pages) != 0xFFFF_FFFF_FFFF_FFFF;
          nodes.freeSpace := pages * 65536 - ((8 - pointer_size_) + root_size_ * pointer_size_);

          let leaves : Region = {
            region = Region.new();
            var freeSpace = 0;
          };

          let ret = { nodes = nodes; leaves = leaves; };
          regions_ := ?ret;
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
      if (node != 0) {
        (root_size_ +% index) *% pointer_size_ +% ((node >> 1) -% 1) *% node_size;
      } else {
        index *% pointer_size_;
      }
    };

    public func getChild(region : Region, node : Nat64, index : Nat64) : Nat64 {
      Region.loadNat64(region.region, getOffset(node, index)) & loadMask;
    };

    public func setChild(region_: Region, node : Nat64, index : Nat64, child : Nat64) {
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

    func unwrap(x : ?Nat8) : Nat8 {
      let ?val = x else Debug.trap("shoud not happen");
      val;
    };

    func keyToIndices(key : Blob, depth : Nat16) : () -> Nat64 {
      let next_byte = key.vals().next;
      var byte : Nat16 = 0;

      func _next() : Nat64 {
        if (byte == 0) {
          if (depth == 0) {
            var skipBits = root_depth * bitlength;
            var length : Nat64 = 0;
            var result : Nat64 = 0;
            while (skipBits >= 8) {
              let b = unwrap(next_byte());
              result |= Nat32.toNat64(Nat16.toNat32(Nat8.toNat16(b))) << length;
              length +%= 8;
              skipBits -%= 8;
            };
            let first = unwrap(next_byte());
            result |= (Nat32.toNat64(Nat16.toNat32(Nat8.toNat16(first) & ((1 << skipBits) - 1)))) << length;
            byte := (Nat8.toNat16(first) | 256) >> skipBits;
            return result;
          } else {
            var skipBits : Nat16 = depth * bitlength;
            while (skipBits >= 8) {
              ignore next_byte();
              skipBits -%= 8;
            };
            let first = unwrap(next_byte());
            byte := (Nat8.toNat16(first) | 256) >> skipBits;
          };
        };
        if (byte == 1) {
          let b = unwrap(next_byte());
          byte := Nat8.toNat16(b) | 256;
        };
        let ret = byte & bitmask;
        byte >>= bitlength;
        return Nat32.toNat64(Nat16.toNat32(ret));
      };
    };

    public func add(key : Blob, value : Blob) : Bool {
      assert node_count <= max_nodes;
      let { leaves; nodes } = regions();

      var node : Nat64 = 0;
      var old_leaf : Nat64 = 0;
      var depth : Nat16 = root_depth;
      let next_idx = keyToIndices(key, 0);

      var last = label l : Nat64 loop {
        let idx = next_idx();
        switch (getChild(nodes, node, idx)) {
          case (0) {
            setChild(nodes, node, idx, newLeaf(leaves, key, value));
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
        setChild(nodes, node, last, add);
        node := add;

        let (a, b) = (next_idx(), next_old_idx());
        if (a == b) {
          last := a;
        } else {
          setChild(nodes, node, a, newLeaf(leaves, key, value));
          setChild(nodes, node, b, old_leaf);
          break l;
        };
      };
      true;
    };

    public func get(key : Blob) : ?Blob {
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
