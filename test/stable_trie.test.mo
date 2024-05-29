// @testmode wasi

import Prng "mo:prng";
import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Nat8 "mo:base/Nat8";
import Nat64 "mo:base/Nat64";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Option "mo:base/Option";
import Debug "mo:base/Debug";
import StableTrieMap "../src/StableTrieMap";

let rng = Prng.Seiran128();
rng.init(0);

let n = 2 ** 11;
let key_size = 5;

func gen(n : Nat, size : Nat) : [Blob] {
  Array.tabulate<Blob>(
    n,
    func(i) {
      Blob.fromArray(Array.tabulate<Nat8>(size, func(j) = Nat8.fromNat(Nat64.toNat(rng.next()) % 256)));
    },
  );
};

let keys = gen(n, key_size);
let sorted = Array.sort<Blob>(keys, Blob.compare);
let revSorted = Array.reverse(sorted);
let keysAbsent = gen(n, key_size);

// Note: bits = 256 and pointers = 2 requires smaller n
let value_sizes = [0, 2];
let bits = [2, 4, 16];
let pointers = [2, 4, 5, 6, 8];
for (value_size in value_sizes.vals()) {
  let values = gen(n, value_size);
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

      let vals = Iter.toArray(Iter.map<(Blob, Blob), Blob>(trie.entries(), func((a, _)) = a));
      assert vals == sorted;

      let revVals = Iter.toArray(Iter.map<(Blob, Blob), Blob>(trie.entriesRev(), func((a, _)) = a));
      assert revVals == revSorted;
    };
  };
};

func pointerMaxSizeTest() {
  let trie = StableTrieMap.StableTrieMap(2, 2, 2, 2, 0);
  for (i in Iter.range(0, 32_000)) {
    let key = Blob.fromArray([Nat8.fromNat(i % 256), Nat8.fromNat(i / 256)]);
    if (trie.put(key, "") != ?i) {
      Debug.print(debug_show i);
      assert false;
    };
  };
};

pointerMaxSizeTest();

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
