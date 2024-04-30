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

    let subbyteLength = Nat64.bitcountTrailingZero(Nat64.fromIntWrap(children_number));
//    let subbytesInByte = 8 / subbyteLength;
    let subbyteMask = (1 << subbyteLength) - 1;
    let offsetMask : Nat64 = (1 << (POINTER_SIZE * 8 - 1)) - 1;
    let nodeSize : Nat = children_number * Nat64.toNat(POINTER_SIZE);
    var regionSpace = 0;
    let leafSize = key_size + value_size;
    let k_size : Nat64 = Nat64.fromIntWrap(key_size);

    func newInternalNode(state : StableTrieState) : Nat64 {
      if (nodeSize < regionSpace) {
        assert Region.grow(state.region, 1) != 0xFFFF_FFFF_FFFF_FFFF;
        regionSpace += 65536;
      };
      let pos = state.size;
      state.size += nodeSize;
      regionSpace -= nodeSize;
      Nat64.fromIntWrap(pos);
    };

    func newLeaf(state : StableTrieState, key : Blob, value : Blob) : Nat64 {
      if (leafSize < regionSpace) {
        assert Region.grow(state.region, 1) != 0xFFFF_FFFF_FFFF_FFFF;
        regionSpace += 65536;
      };
      let pos = state.size;
      state.size += leafSize;
      regionSpace -= leafSize;
      Region.storeBlob(state.region, Nat64.fromIntWrap(pos), key);
      Region.storeBlob(state.region, Nat64.fromIntWrap(pos + key_size), value);
      Nat64.fromIntWrap(pos) | (offsetMask + 1);
    };

    public func getChild(state : StableTrieState, node : Nat64, number : Nat64) : ?Nat64 {
      let child = Region.loadNat64(state.region, node + number * POINTER_SIZE);
      if (child == 0) null else ?child;
    };

    public func setChild(state : StableTrieState, node : Nat64, number : Nat64, child : Nat64) {
      Region.storeNat64(state.region, node + number * POINTER_SIZE, child);
    };

    public func loadAsValue(state : StableTrieState, offset : Nat64) : Blob {
      Region.loadBlob(state.region, offset, value_size);
    };

    public func storeValue(state : StableTrieState, offset : Nat64, value : Blob) {
      assert value_size == value_size;
// Bug:      Region.storeBlob(state.region, offset, value);
      //Region.storeBlob(state.region, offset & offsetMask + key_size, value);
      // TODO
      Region.storeBlob(state.region, offset + k_size, value);
    };

    public func isLeaf(offset : Nat64) : Bool {
      offset & (offsetMask + 1) > 0;
    };

    public func getKey(state : StableTrieState, offset : Nat64) : Blob {
      Region.loadBlob(state.region, offset & offsetMask, key_size);
    };

    public func value(state : StableTrieState, offset : Nat64) : Blob {
      Region.loadBlob(state.region, offset & offsetMask + k_size, value_size);
    };

    public func print(state : StableTrieState, offset : Nat64) {
      Debug.print(
        Nat64.toText(offset) # " node " # Text.join(
          " ",
          Iter.map<Nat, Text>(
            Iter.range(0, children_number - 1),
            func(x : Nat) : Text = switch (getChild(state, offset, Nat64.fromIntWrap(x))) {
              case (null) "null";
              case (?ch) if (isLeaf(ch)) debug_show (getKey(state, ch)) else Nat64.toText(ch);
            },
          ),
        )
      );
      for (x in Iter.range(0, children_number - 1)) {
        switch (getChild(state, offset, Nat64.fromIntWrap(x))) {
          case (null) {};
          case (?ch) if (not isLeaf(ch)) print(state, ch);
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

    func keyToBytes(key : Blob) : Iter.Iter<Nat64> {
      let bytes = Blob.toArray(key);
      assert bytes.size() == key_size;

      let iter = Iter.map(bytes.vals(), func(x : Nat8) : Nat64 = Nat64.fromNat(Nat8.toNat(x)));
      if (children_number == 256) return iter;
      let mask = children_number - 1;
      object {
        var byte : Nat64 = 1;

        public func next() : ?Nat64 {
          if (byte == 1) {
            switch (iter.next()) {
              case (?b) byte := b | 256;
              case (null) return null;
            };
          };
          let ret = byte & subbyteMask;
          byte >>= subbyteLength;
          ?ret;
        };
      };
    };

    public func add(key : Blob, value : Blob) : Bool {
      let s = state();

      var node : Nat64 = 0;
      var last : Nat64 = 256;

      var depth = 0;

      let bytes = keyToBytes(key);
      label l for (byte in bytes) {
        switch (getChild(s, node, byte)) {
          case (?n) {
            if (isLeaf(n)) {
              last := byte;
              break l;
            };
            node := n;
            depth += 1;
          };
          case (null) {
            last := byte;
            break l;
          };
        };
      };

      assert last != 256;

      switch (getChild(s, node, last)) {
        case (?old_leaf) {
          if (not isLeaf(old_leaf)) {
            assert false;
            return false;
          };

          let old_key = getKey(s, old_leaf);
          if (key == old_key) {
            return false;
          };

          let old_bytes = keyToBytes(old_key);
          for (i in Iter.range(0, depth : Int)) {
            ignore old_bytes.next();
          };
          label l while (true) {
            let add = newInternalNode(s);
            setChild(s, node, last, add);
            node := add;

            switch (bytes.next(), old_bytes.next()) {
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
        case (null) {
          setChild(s, node, last, newLeaf(s, key, value));
          true;
        };
      };
    };

    public func get(key : Blob) : ?Blob {
      let s = state();
      let bytes = keyToBytes(key);

      var node : Nat64 = 0;
      for (byte in bytes) {
        node := switch (getChild(s, node, byte)) {
          case (?n) {
            if (isLeaf(n)) {
              if (getKey(s, n) == key) return ?value(s, n) else return null;
            };
            n;
          };
          case (null) {
            return null;
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
