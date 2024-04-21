import Blob "mo:base/Blob";
import Region "mo:base/Region";
import Nat64 "mo:base/Nat64";
import Nat8 "mo:base/Nat8";
import Iter "mo:base/Iter";

module {
  let CHILDERN_NUMBER = 256;
  let POINTER_SIZE = 8;

  type StableTrieState = {
    region : Region.Region;
    var size : Nat64;
  };

  public class StableTrie(key_size : Nat, value_size : Nat) {
    assert key_size >= 1;

    func newInternalNode(state : StableTrieState) : Node {
      let old_size = state.size;
      let new_size = state.size + Nat64.fromNat(CHILDERN_NUMBER * POINTER_SIZE);
      if (new_size > Region.size(state.region) * 2 ** 16) {
        assert Region.grow(state.region, 1) != 0xFFFF_FFFF_FFFF_FFFF;
      };
      state.size := new_size;
      Node(state, old_size);
    };

    func newLeaf(state : StableTrieState, value : Blob) : Node {
      let old_size = state.size;
      let new_size = state.size + Nat64.fromNat(value.size());
      if (new_size > Region.size(state.region) * 2 ** 16) {
        assert Region.grow(state.region, 1) != 0xFFFF_FFFF_FFFF_FFFF;
      };
      Region.storeBlob(state.region, old_size, value);
      state.size := new_size;
      Node(state, old_size);
    };

    class Node(state : StableTrieState, o : Nat64) {
      public let offset = o;

      public func getChild(number : Nat8) : ?Node {
        let child = Region.loadNat64(state.region, offset + Nat64.fromNat(Nat8.toNat(number)));
        if (child == 0) null else ?Node(state, child);
      };

      public func getOrCreateChild(number : Nat8) : Node {
        let childOffset = offset + Nat64.fromNat(Nat8.toNat(number));
        let child = Region.loadNat64(state.region, childOffset);
        if (child != 0) {
          return Node(state, child);
        };
        let old_size = state.size;
        let new_size = state.size + Nat64.fromNat(CHILDERN_NUMBER * POINTER_SIZE);
        if (new_size > Region.size(state.region) * 2 ** 16) {
          assert Region.grow(state.region, 1) != 0xFFFF_FFFF_FFFF_FFFF;
        };
        Region.storeNat64(state.region, childOffset, old_size);
        state.size := new_size;
        Node(state, old_size);
      };

      public func setChild(number : Nat8, node : Node) {
        let childOffset = offset + Nat64.fromNat(Nat8.toNat(number));
        let child = Region.storeNat64(state.region, childOffset, node.offset);
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
            var size = Nat64.fromNat(CHILDERN_NUMBER * POINTER_SIZE);
          };
          assert Region.grow(s.region, 1) != 0xFFFF_FFFF_FFFF_FFFF;
          state_ := ?s;
          s;
        };
      };
    };

    public func add(key : Blob, value : Blob) : Bool {
      let s = state();
      let bytes = Blob.toArray(key);
      assert bytes.size() == key_size;

      var node = Node(s, 0);
      for (i in Iter.range(0, key_size : Int - 2)) {
        node := switch (node.getChild(bytes[i])) {
          case (?n) n;
          case (null) {
            let child = newInternalNode(s);
            node.setChild(bytes[i], child);
            child;
          };
        };
      };
      switch (node.getChild(bytes[key_size - 1])) {
        case (?n) return false;
        case (null) {
          node.setChild(bytes[key_size - 1], newLeaf(s, value));
          true;
        };
      };
    };

    public func get(key : Blob) : ?Blob {
      let s = state();
      let bytes = Blob.toArray(key);
      assert bytes.size() == key_size;

      var node = Node(s, 0);
      for (byte in bytes.vals()) {
        node := switch (node.getChild(byte)) {
          case (?n) n;
          case (null) return null;
        };
      };

      ?node.loadAsValue();
    };
  };
};
