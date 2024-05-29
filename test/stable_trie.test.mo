// @testmode wasi

import Prng "mo:prng";
import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Nat8 "mo:base/Nat8";
import Nat64 "mo:base/Nat64";
import Debug "mo:base/Debug";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Nat16 "mo:base/Nat16";
import Option "mo:base/Option";
import StableTrieMap "../src/StableTrieMap";

let rng = Prng.Seiran128();
rng.init(0);

// func keyToIndices(aridity : Nat, root_aridity : Nat, key : Blob, depth : Nat16) : () -> Nat64 {
//   let bytes = Blob.toArray(key);
//   var first = true;
//   var x : Nat64 = 0;
//   for (i in Iter.range(0, key.size() - 1 : Int)) {
//     x <<= 8;
//     x |= Nat64.fromNat(Nat8.toNat(bytes[i]));
//   };

//   let aridity_ = Nat64.fromNat(aridity);
//   let root_aridity_ = Nat64.fromNat(root_aridity);

//   let aridity_bits = Nat64.bitcountTrailingZero(aridity_);
//   let root_aridity_bits = Nat64.bitcountTrailingZero(root_aridity_);

//   func() : Nat64 {
//     let b = if (first and depth == 0) root_aridity_bits else aridity_bits;

//     if (first and depth != 0) x <<= aridity_bits * Nat64.fromNat(Nat16.toNat(depth));
//     first := false;

//     let ret = x >> (64 - b);
//     x <<= b;
//     ret;
//   };
// };

// func testKeyToIndices() {
//   let bits = [2, 4, 16, 256];
//   let key_size = 8;
//   let pointer_size = 2;
//   let rnd_key = Blob.fromArray(Array.tabulate<Nat8>(key_size, func(j) = Nat8.fromNat(Nat64.toNat(rng.next()) % 256)));

//   for (bit in bits.vals()) {
//     let length = key_size * 8 / Nat64.toNat(Nat64.bitcountTrailingZero(Nat64.fromNat(bit)));
//     label l for (key in Iter.range(1, length)) {
//       let root_aridity = bit ** key;
//       if (pointer_size * root_aridity >= 2 ** 64) break l;
//       let trie = StableTrieMap.StableTrieMap(pointer_size, bit, root_aridity, key_size, 0);
//       let next = trie.keyToIndices(rnd_key, 0);
//       let test_next = keyToIndices(bit, bit ** key, rnd_key, 0);
//       let cnt = length - key : Nat + 1;
//       for (i in Iter.range(0, cnt - 1)) {
//         let a = next();
//         let b = test_next();
//         if (a != b) {
//           Debug.print(debug_show (bit, key, i, a, b));
//           assert false;
//         };
//       };
//     };
//   };
// };

// testKeyToIndices();

// let trie = StableTrieMap.StableTrieMap(2, 2, 256, 1, 0);
// ignore trie.keyToIndices("a" : Blob, 0)();

let n = 2 ** 11;
let key_size = 5;

func gen(size : Nat) : [Blob] {
  Array.tabulate<Blob>(
    n,
    func(i) {
      Blob.fromArray(Array.tabulate<Nat8>(size, func(j) = Nat8.fromNat(Nat64.toNat(rng.next()) % 256)));
    },
  );
};

let keys = gen(key_size);
let sorted = Array.sort<Blob>(keys, Blob.compare);
let revSorted = Array.reverse(sorted);
let keysAbsent = gen(key_size);

// Note: bits = 256 and pointers = 2 requires smaller n
let value_sizes = [0, 2];
let bits = [2, 4, 16];
let pointers = [2, 4, 5, 6, 8];
for (value_size in value_sizes.vals()) {
  let values = gen(value_size);
  for (bit in bits.vals()) {
    for (pointer in pointers.vals()) {
      let trie = StableTrieMap.StableTrieMap(pointer, bit, bit * bit * bit, key_size, value_size);

      var i = 0;
      for (key in keys.vals()) {
        assert trie.put(key, values[i]) == ?i;
        i += 1;
      };

      i := 0;
      for (key in keys.vals()) {
        assert trie.get(i) == ?(key, values[i]);
        i += 1;
      };

      i := 0;

      for (key in keys.vals()) {
        assert (trie.lookup(key) == ?(values[i], i));
        i += 1;
      };

      for (key in keysAbsent.vals()) {
        assert trie.lookup(key) == null;
      };

      let vals = Iter.toArray(Iter.map<(Blob, Blob), Blob>(trie.vals(), func ((a, _)) = a));
      assert vals == sorted;

      let revVals = Iter.toArray(Iter.map<(Blob, Blob), Blob>(trie.revVals(), func ((a, _)) = a));
      assert revVals == revSorted;
    };
  };
};

func profile() {
  let children_number = [2, 4, 16, 256];

  let key_size = 8;
  let n = 20;
  let rng = Prng.Seiran128();
  rng.init(0);
  let keys = Array.tabulate<Blob>(
    2 ** n,
    func(i) {
      Blob.fromArray(Array.tabulate<Nat8>(key_size, func(j) = Nat8.fromNat(Nat64.toNat(rng.next()) % 256)));
    },
  );
  let rows = Iter.map<Nat, (Text, Iter.Iter<Text>)>(
    children_number.vals(),
    func(k) {
      let first = Nat.toText(k);
      let trie = StableTrieMap.StableTrieMap(8, k, k, key_size, 0);
      let second = Iter.map<Nat, Text>(
        Iter.range(0, n),
        func(i) {
          if (i == 0) {
            ignore trie.put(keys[0], "");
          } else {
            for (j in Iter.range(2 ** (i - 1), 2 ** i - 1)) {
              assert Option.isSome(trie.put(keys[j], ""));
            };
          };
          "";
          // Nat.toText(trie.size() / 2 ** i);
        },
      );
      (first, second);
    },
  );
};

// profile();
