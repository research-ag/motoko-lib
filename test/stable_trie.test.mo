// @testmode wasi

import Prng "mo:prng";
import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Nat8 "mo:base/Nat8";
import Nat64 "mo:base/Nat64";
import Debug "mo:base/Debug";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import StableTrie "../src/StableTrie";

let n = 2 ** 11;
let key_size = 5;

let rng = Prng.Seiran128();
rng.init(0);

func gen() : [Blob] {
  Array.tabulate<Blob>(
    n,
    func(i) {
      Blob.fromArray(Array.tabulate<Nat8>(key_size, func(j) = Nat8.fromNat(Nat64.toNat(rng.next()) % 256)));
    },
  );
};

let keys = gen();

let keysAbsent = gen();

// Note: bits = 256 and pointers = 2 requires smaller n
let bits = [2, 4, 16];
let pointers = [2, 4, 6, 8];
for (bit in bits.vals()) {
  for (pointer in pointers.vals()) {
    let trie = StableTrie.StableTrie(pointer, bit, bit, key_size, 0);

    for (key in keys.vals()) {
      assert trie.add(key, "");
    };

    // trie.print();

    for (key in keys.vals()) {
      assert (trie.get(key) == ?"");
    };

    for (key in keysAbsent.vals()) {
      assert trie.get(key) == null;
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
      let trie = StableTrie.StableTrie(8, k, k, key_size, 0);
      let second = Iter.map<Nat, Text>(
        Iter.range(0, n),
        func(i) {
          if (i == 0) {
            ignore trie.add(keys[0], "");
          } else {
            for (j in Iter.range(2 ** (i - 1), 2 ** i - 1)) {
              assert trie.add(keys[j], "");
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
