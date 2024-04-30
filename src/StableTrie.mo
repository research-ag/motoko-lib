import Blob "mo:base/Blob";
import Region "mo:base/Region";
import Nat64 "mo:base/Nat64";
import Nat8 "mo:base/Nat8";
import Nat16 "mo:base/Nat16";
import Iter "mo:base/Iter";
import Debug "mo:base/Debug";
import Text "mo:base/Text";
import Nat "mo:base/Nat";

module {
  let POINTER_SIZE : Nat64 = 8;

  type StableTrieState = {
    region : Region.Region;
    size : Nat;
  };

  public class StableTrie(children_number : Nat, key_size : Nat, value_size : Nat) {
    assert children_number == 2 or children_number == 4 or children_number == 16 or children_number == 256;
    assert key_size >= 1;

    // initialize the state
    var region = Region.new();
    var size_ = children_number * Nat64.toNat(POINTER_SIZE);

    assert Region.grow(region, 1) != 0xFFFF_FFFF_FFFF_FFFF;

    let leafBit : Nat = Nat64.toNat(POINTER_SIZE) * 8 - 1;
    let nodeSize : Nat = children_number * Nat64.toNat(POINTER_SIZE);
    let leafSize : Nat = key_size + value_size;

    let key_size_64 : Nat64 = Nat64.fromIntWrap(key_size);

    var regionSpace = 0;

    func newInternalNode() : Nat64 {
      if (regionSpace < nodeSize) {
        assert Region.grow(region, 1) != 0xFFFF_FFFF_FFFF_FFFF;
        regionSpace += 65536;
      };
      let pos = Nat64.fromIntWrap(size_);
      size_ += nodeSize;
      regionSpace -= nodeSize;
      pos;
    };

    func newLeaf(key : Blob, value : Blob) : Nat64 {
      if (regionSpace < leafSize) {
        assert Region.grow(region, 1) != 0xFFFF_FFFF_FFFF_FFFF;
        regionSpace += 65536;
      };
      let pos = Nat64.fromIntWrap(size_);
      size_ += leafSize;
      regionSpace -= leafSize;
      Region.storeBlob(region, pos, key);
      Region.storeBlob(region, pos + key_size_64, value);
      Nat64.bitset(pos, leafBit);
    };

    public func getChild(node : Nat64, index : Nat8) : Nat64 {
      Region.loadNat64(region, node + Nat64.fromIntWrap(Nat8.toNat(index)) * POINTER_SIZE);
    };

    public func setChild(node : Nat64, index : Nat8, child : Nat64) {
      Region.storeNat64(region, node + Nat64.fromIntWrap(Nat8.toNat(index)) * POINTER_SIZE, child);
    };

    public func getKey(offset : Nat64) : Blob {
      Region.loadBlob(region, Nat64.bitclear(offset, leafBit), key_size);
    };

    public func value(offset : Nat64) : Blob {
      Region.loadBlob(region, Nat64.bitclear(offset, leafBit) + Nat64.fromIntWrap(key_size), value_size);
    };

    public func print(offset : Nat64) {
      Debug.print(
        Nat64.toText(offset) # " node " # Text.join(
          " ",
          Iter.map<Nat, Text>(
            Iter.range(0, children_number - 1),
            func(x : Nat) : Text = switch (getChild(offset, Nat8.fromIntWrap(x))) {
              case (0) "null";
              case (ch) if (Nat64.bittest(ch, leafBit)) debug_show (getKey(ch)) else Nat64.toText(ch);
            },
          ),
        )
      );
      for (x in Iter.range(0, children_number - 1)) {
        switch (getChild(offset, Nat8.fromIntWrap(x))) {
          case (0) {};
          case (ch) if (not Nat64.bittest(ch, leafBit)) print(ch);
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

    func keyToIndices(key : Blob) : Iter.Iter<Nat8> {
      let iter = key.vals();
      if (children_number == 256) return iter;
      object {
        var byte : Nat16 = 1;
        public func next() : ?Nat8 {
          if (byte == 1) {
            switch (iter.next()) {
              case (?b) byte := Nat8.toNat16(b) | 256;
              case (null) return null;
            };
          };
          let ret = Nat8.fromNat16(byte & bitmask);
          byte >>= bitlength;
          return ?ret;
        };
      };
    };

    public func add(key : Blob, value : Blob) : Bool {
      var node : Nat64 = 0; // root node
      var old_leaf : Nat64 = 0;

      var depth = 0;

      let indices = keyToIndices(key);
      var last = label l : Nat8 loop {
        let ?idx = indices.next() else Debug.trap("cannot happen");
        switch (getChild(node, idx)) {
          case (0) {
            setChild(node, idx, newLeaf(key, value));
            return true;
          };
          case (n) {
            if (Nat64.bittest(n, leafBit)) {
              old_leaf := n;
              break l idx;
            };
            node := n;
            depth += 1;
          };
        };
      };

      let old_key = getKey(old_leaf);
      if (key == old_key) {
        return false;
      };

      let old_indices = keyToIndices(old_key);
      var i = depth + 1;
      while (i != 0) {
        ignore old_indices.next();
        i -= 1;
      };
      label l loop {
        let add = newInternalNode();
        setChild(node, last, add);
        node := add;

        switch (indices.next(), old_indices.next()) {
          case (?a, ?b) {
            if (a == b) {
              last := a;
            } else {
              setChild(node, a, newLeaf(key, value));
              setChild(node, b, old_leaf);
              break l;
            };
          };
          case (_, _) {
            assert false;
            break l;
          };
        };
      };
      true;
    };

    public func get(key : Blob) : ?Blob {
      let indices = keyToIndices(key);

      var node : Nat64 = 0;
      for (idx in indices) {
        node := switch (getChild(node, idx)) {
          case (0) {
            return null;
          };
          case (n) {
            if (Nat64.bittest(n, leafBit)) {
              if (getKey(n) == key) return ?value(n) else return null;
            };
            n;
          };
        };
      };

      assert false;
      null;
    };

    public func size() : Nat = size_;

    public func share() : StableTrieState = { region = region; size = size_ };

    public func unshare(data : StableTrieState) {
      region := data.region;
      size_ := data.size;
    };
  };
};
