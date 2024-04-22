import Blob "mo:base/Blob";
import Region "mo:base/Region";
import Nat64 "mo:base/Nat64";
import Nat8 "mo:base/Nat8";
import Iter "mo:base/Iter";
import Debug "mo:base/Debug";

module {
  let POINTER_SIZE = 8;

  type StableTrieState = {
    region : Region.Region;
    var size : Nat64;
  };

  public class StableTrie(children_bits : Nat, key_size : Nat, value_size : Nat) {
    assert key_size >= 1;

    func newInternalNode(state : StableTrieState) : Node {
      let old_size = state.size;
      let new_size = state.size + Nat64.fromNat(children_bits * POINTER_SIZE);
      if (new_size > Region.size(state.region) * 2 ** 16) {
        assert Region.grow(state.region, 1) != 0xFFFF_FFFF_FFFF_FFFF;
      };
      state.size := new_size;
      Node(state, old_size);
    };

    func newLeaf(state : StableTrieState, value : Blob) : Node {
      let old_size = state.size;
      let new_size = old_size + Nat64.fromNat(value.size());
      if (new_size >= Region.size(state.region) * 2 ** 16) {
        assert Region.grow(state.region, 1) != 0xFFFF_FFFF_FFFF_FFFF;
      };
      Region.storeBlob(state.region, old_size, value);
      state.size := new_size;
      Node(state, old_size);
    };

    class Node(state : StableTrieState, o : Nat64) {
      public let offset = o;

      func getOffset(number : Nat) : Nat64 {
        offset + Nat64.fromNat(number * POINTER_SIZE);
      };

      public func getChild(number : Nat) : ?Node {
        let child = Region.loadNat64(state.region, getOffset(number));
        if (child == 0) null else ?Node(state, child);
      };

      public func getOrCreateChild(number : Nat) : Node {
        let childOffset = getOffset(number);
        let child = Region.loadNat64(state.region, childOffset);
        if (child != 0) {
          return Node(state, child);
        };
        let old_size = state.size;
        let new_size = old_size + Nat64.fromNat(children_bits * POINTER_SIZE);
        if (new_size > Region.size(state.region) * 2 ** 16) {
          assert Region.grow(state.region, 1) != 0xFFFF_FFFF_FFFF_FFFF;
        };
        Region.storeNat64(state.region, childOffset, old_size);
        state.size := new_size;
        Node(state, old_size);
      };

      public func setChild(number : Nat, node : Node) {
        let child = Region.storeNat64(state.region, getOffset(number), node.offset);
      };

      public func loadAsValue() : Blob {
        Region.loadBlob(state.region, offset, value_size);
      };

      public func storeAsValue(value : Blob) {
        assert value.size() == value_size;
        Region.storeBlob(state.region, offset, value);
      };
    };

    var state_ : ?StableTrieState = null;

    func state() : StableTrieState {
      switch (state_) {
        case (?s) s;
        case (null) {
          let s = {
            region = Region.new();
            var size = Nat64.fromNat(children_bits * POINTER_SIZE);
          };
          assert Region.grow(s.region, 1) != 0xFFFF_FFFF_FFFF_FFFF;
          state_ := ?s;
          s;
        };
      };
    };

    func keyToBytes(key : Blob) : Iter.Iter<Nat> {
      let bytes = Blob.toArray(key);
      assert bytes.size() == key_size;

      if (children_bits == 256) return Iter.map(bytes.vals(), func(x : Nat8) : Nat = Nat8.toNat(x));
      object {
        var byte = 0;
        var subbyte = 0;

        public func next() : ?Nat {
          if (byte == bytes.size()) return null;
          let x = Nat8.toNat(bytes[byte]);
          subbyte += 1;
          if (children_bits ** subbyte == 256) {
            subbyte := 0;
            byte += 1;
          };
          ?(x / children_bits ** subbyte % children_bits);
        };
      };
    };

    public func add(key : Blob, value : Blob) : Bool {
      let s = state();
      let bytes = keyToBytes(key);

      var node = Node(s, 0);
      var previous = 256;
      for (byte in bytes) {
        if (previous != 256) {
          node := switch (node.getChild(previous)) {
            case (?n) n;
            case (null) {
              let child = newInternalNode(s);
              node.setChild(previous, child);
              child;
            };
          };
        };

        previous := byte;
      };

      switch (node.getChild(previous)) {
        case (?n) return false;
        case (null) {
          node.setChild(previous, newLeaf(s, value));
          true;
        };
      };
    };

    public func get(key : Blob) : ?Blob {
      let s = state();
      let bytes = keyToBytes(key);

      var node = Node(s, 0);
      for (byte in bytes) {
        node := switch (node.getChild(byte)) {
          case (?n) n;
          case (null) return null;
        };
      };

      ?node.loadAsValue();
    };
  };
};
