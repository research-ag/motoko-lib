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
    var size : Nat64;
  };

  public class StableTrie(children_number : Nat, key_size : Nat, value_size : Nat) {
    assert children_number == 2 or children_number == 4 or children_number == 16 or children_number == 256;
    assert key_size >= 1;

    func newInternalNode(state : StableTrieState) : Node {
      let old_size = state.size;
      let new_size = state.size + Nat64.fromNat(children_number) * POINTER_SIZE;
      if (new_size > Region.size(state.region) * 2 ** 16) {
        assert Region.grow(state.region, 1) != 0xFFFF_FFFF_FFFF_FFFF;
      };
      state.size := new_size;
      Node(state, old_size);
    };

    func newLeaf(state : StableTrieState, key : Blob, value : Blob) : Node {
      let old_size = state.size;
      let new_size = old_size + Nat64.fromNat(key_size + value_size);
      if (new_size >= Region.size(state.region) * 2 ** 16) {
        assert Region.grow(state.region, 1) != 0xFFFF_FFFF_FFFF_FFFF;
      };
      Region.storeBlob(state.region, old_size, key);
      Region.storeBlob(state.region, old_size + Nat64.fromNat(key_size), value);
      state.size := new_size;
      Node(state, old_size | (1 << (POINTER_SIZE * 8 - 1)));
    };

    class Node(state : StableTrieState, o : Nat64) {
      public let offset = o;

      func getOffset(number : Nat) : Nat64 {
        offset + Nat64.fromNat(number) * POINTER_SIZE;
      };

      public func getChild(number : Nat) : ?Node {
        let child = Region.loadNat64(state.region, getOffset(number));
        if (child == 0) null else ?Node(state, child);
      };

      public func setChild(number : Nat, node : Node) {
        Region.storeNat64(state.region, getOffset(number), node.offset);
      };

      public func loadAsValue() : Blob {
        Region.loadBlob(state.region, offset, value_size);
      };

      public func storeValue(value : Blob) {
        assert value_size == value_size;
        Region.storeBlob(state.region, offset, value);
        Region.storeBlob(state.region, offset & ((1 << (POINTER_SIZE * 8 - 1)) - 1) + Nat64.fromNat(key_size), value);
      };

      public func isLeaf() : Bool {
        offset & (1 << 63) > 0;
      };

      public func key() : Blob {
        Region.loadBlob(state.region, offset & ((1 << (POINTER_SIZE * 8 - 1)) - 1), key_size);
      };

      public func value() : Blob {
        Region.loadBlob(state.region, offset & ((1 << (POINTER_SIZE * 8 - 1)) - 1) + Nat64.fromNat(key_size), value_size);
      };

      public func print() {
        Debug.print(
          Nat64.toText(offset) # " node " # Text.join(
            " ",
            Iter.map<Nat, Text>(
              Iter.range(0, children_number - 1),
              func(x : Nat) : Text = switch (getChild(x)) {
                case (null) "null";
                case (?ch) if (ch.isLeaf()) debug_show (ch.key()) else Nat64.toText(ch.offset);
              },
            ),
          )
        );
        for (x in Iter.range(0, children_number - 1)) {
          switch (getChild(x)) {
            case (null) {};
            case (?ch) if (not ch.isLeaf()) ch.print();
          };
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
            var size = Nat64.fromNat(children_number) * POINTER_SIZE;
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

      if (children_number == 256) return Iter.map(bytes.vals(), func(x : Nat8) : Nat = Nat8.toNat(x));
      object {
        var byte = 0;
        var subbyte = 0;

        public func next() : ?Nat {
          if (byte == bytes.size()) return null;
          let x = Nat8.toNat(bytes[byte]);
          subbyte += 1;
          if (children_number ** subbyte == 256) {
            subbyte := 0;
            byte += 1;
          };
          ?(x / children_number ** subbyte % children_number);
        };
      };
    };

    public func add(key : Blob, value : Blob) : Bool {
      let s = state();

      var node = Node(s, 0);
      var last = 256;

      var depth = 0;

      label l for (byte in keyToBytes(key)) {
        switch (node.getChild(byte)) {
          case (?n) {
            if (n.isLeaf()) {
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

      switch (node.getChild(last)) {
        case (?old_leaf) {
          if (not old_leaf.isLeaf()) {
            assert false;
            return false;
          };

          let old_key = old_leaf.key();
          if (key == old_key) {
            return false;
          };

          let bytes = keyToBytes(key);
          let old_bytes = keyToBytes(old_key);
          for (i in Iter.range(0, depth : Int)) {
            ignore old_bytes.next();
            ignore bytes.next();
          };
          label l while (true) {
            let add = newInternalNode(s);
            node.setChild(last, add);
            node := add;

            switch (bytes.next(), old_bytes.next()) {
              case (?a, ?b) {
                if (a == b) {
                  last := a;
                } else {
                  node.setChild(a, newLeaf(s, key, value));
                  node.setChild(b, old_leaf);
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
          node.setChild(last, newLeaf(s, key, value));
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
          case (?n) {
            if (n.isLeaf()) {
              if (n.key() == key) return ?n.value() else return null;
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

    public func size() : Nat {
      Nat64.toNat(state().size);
    };

    public func share() : StableTrieState = state();

    public func unshare(data : StableTrieState) {
      assert Option.isNull(state_);
      state_ := ?data;
    };
  };
};
