import Blob "mo:base/Blob";
import Region "mo:base/Region";
import Nat64 "mo:base/Nat64";
import Nat8 "mo:base/Nat8";
import Iter "mo:base/Iter";
import Debug "mo:base/Debug";
import Text "mo:base/Text";
import Nat "mo:base/Nat";
import Option "mo:base/Option";

module {
  let POINTER_SIZE : Nat64 = 8;

  type StableTrieState = {
    region : Region.Region;
    var size : Nat;
  };

  public class StableTrie(children_number : Nat, key_size : Nat, value_size : Nat) {
    assert children_number == 2 or children_number == 4 or children_number == 16 or children_number == 256;
    assert key_size >= 1;

    let leafBit : Nat = Nat64.toNat(POINTER_SIZE) * 8 - 1;
    let nodeSize : Nat = children_number * Nat64.toNat(POINTER_SIZE);
    let leafSize : Nat = key_size + value_size;

    let key_size_64 : Nat64 = Nat64.fromIntWrap(key_size);

    var regionSpace = 0;

    func newInternalNode(state : StableTrieState) : Nat64 {
      if (regionSpace < nodeSize) {
        assert Region.grow(state.region, 1) != 0xFFFF_FFFF_FFFF_FFFF;
        regionSpace += 65536;
      };
      let pos = Nat64.fromIntWrap(state.size);
      state.size += nodeSize;
      regionSpace -= nodeSize;
      pos;
    };

    func newLeaf(state : StableTrieState, key : Blob, value : Blob) : Nat64 {
      if (regionSpace < leafSize) {
        assert Region.grow(state.region, 1) != 0xFFFF_FFFF_FFFF_FFFF;
        regionSpace += 65536;
      };
      let pos = Nat64.fromIntWrap(state.size);
      state.size += leafSize;
      regionSpace -= leafSize;
      Region.storeBlob(state.region, pos, key);
      Region.storeBlob(state.region, pos + key_size_64, value);
      Nat64.bitset(pos, leafBit);
    };

    public func getChild(state : StableTrieState, node : Nat64, index : Nat8) : Nat64 {
      Region.loadNat64(state.region, node + Nat64.fromIntWrap(Nat8.toNat(index)) * POINTER_SIZE);
    };

    public func setChild(state : StableTrieState, node : Nat64, index : Nat8, child : Nat64) {
      Region.storeNat64(state.region, node + Nat64.fromIntWrap(Nat8.toNat(index)) * POINTER_SIZE, child);
    };

    public func isLeaf(offset : Nat64) : Bool {
      Nat64.bittest(offset, leafBit);
    };

    public func getKey(state : StableTrieState, offset : Nat64) : Blob {
      Region.loadBlob(state.region, Nat64.bitclear(offset, leafBit), key_size);
    };

    public func value(state : StableTrieState, offset : Nat64) : Blob {
      Region.loadBlob(state.region, Nat64.bitclear(offset, leafBit) + Nat64.fromIntWrap(key_size), value_size);
    };

    public func print(state : StableTrieState, offset : Nat64) {
      Debug.print(
        Nat64.toText(offset) # " node " # Text.join(
          " ",
          Iter.map<Nat, Text>(
            Iter.range(0, children_number - 1),
            func(x : Nat) : Text = switch (getChild(state, offset, Nat8.fromIntWrap(x))) {
              case (0) "null";
              case (ch) if (isLeaf(ch)) debug_show (getKey(state, ch)) else Nat64.toText(ch);
            },
          ),
        )
      );
      for (x in Iter.range(0, children_number - 1)) {
        switch (getChild(state, offset, Nat8.fromIntWrap(x))) {
          case (0) {};
          case (ch) if (not isLeaf(ch)) print(state, ch);
        };
      };
    };

    var state_ : ?StableTrieState = null;

    func state() : StableTrieState {
      switch (state_) {
        case (?s) s;
        case (null) {
          let s = {
            region = Region.new();
            var size = children_number * Nat64.toNat(POINTER_SIZE);
          };
          assert Region.grow(s.region, 1) != 0xFFFF_FFFF_FFFF_FFFF;
          state_ := ?s;
          s;
        };
      };
    };

    let (bitlength, bitmask) : (Nat16, Nat16) = switch (children_number) {
      case (2) (1, 0x1);
      case (4) (2, 0x3);
      case (16) (4, 0xf);
      case (_) (0, 0x0);
    };

    func keyToIndices(key : Blob) : Iter.Iter<Nat8> {
      let iter = key.vals();
      if (children_number == 256) return iter;
      object {
        var byte : Nat16 = 1;
        public func next(): ?Nat8 { 
          if (byte == 1) {
            switch (iter.next()) {
              case (?b) byte := Nat8.toNat16(b) | 256;
              case (null) return null;
            };
          } else {
            byte := byte >> bitlength;
          };
          return ?Nat8.fromNat16(byte & bitmask);
        };
      };
    };

    public func add(key : Blob, value : Blob) : Bool {
      let s = state();

      var node : Nat64 = 0; // root node
      var last : Nat8 = 0;

      var depth = 0;

      let indices = keyToIndices(key);
      label l for (idx in indices) {
        switch (getChild(s, node, idx)) {
          case (0) {
            last := idx;
            break l;
          };
          case (n) {
            if (isLeaf(n)) {
              last := idx;
              break l;
            };
            node := n;
            depth += 1;
          };
        };
      };

      switch (getChild(s, node, last)) {
        case (0) {
          setChild(s, node, last, newLeaf(s, key, value));
          true;
        };
        case (old_leaf) {
          if (not isLeaf(old_leaf)) {
            assert false;
            return false;
          };

          let old_key = getKey(s, old_leaf);
          if (key == old_key) {
            return false;
          };

          let old_indices = keyToIndices(old_key);
          for (i in Iter.range(0, depth : Int)) {
            ignore old_indices.next();
          };
          label l loop {
            let add = newInternalNode(s);
            setChild(s, node, last, add);
            node := add;

            switch (indices.next(), old_indices.next()) {
              case (?a, ?b) {
                if (a == b) {
                  last := a;
                } else {
                  setChild(s, node, a, newLeaf(s, key, value));
                  setChild(s, node, b, old_leaf);
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
      };
    };

    public func get(key : Blob) : ?Blob {
      let s = state();
      let indices = keyToIndices(key);

      var node : Nat64 = 0;
      for (idx in indices) {
        node := switch (getChild(s, node, idx)) {
          case (0) {
            return null;
          };
          case (n) {
            if (isLeaf(n)) {
              if (getKey(s, n) == key) return ?value(s, n) else return null;
            };
            n;
          };
        };
      };

      assert false;
      null;
    };

    public func size() : Nat = state().size;

    public func share() : StableTrieState = state();

    public func unshare(data : StableTrieState) {
      assert Option.isNull(state_);
      state_ := ?data;
    };
  };
};
