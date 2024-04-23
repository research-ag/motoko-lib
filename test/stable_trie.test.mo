// @testmode wasi

import Prng "mo:prng";
import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Nat64 "mo:base/Nat64";
import Nat8 "mo:base/Nat8";
import Debug "mo:base/Debug";
import StableTrie "../src/StableTrie";

let n = 100;
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

let bits = [2, 4, 16, 256];
for (bit in bits.vals()) {
  let trie = StableTrie.StableTrie(bit, key_size, 0);

  for (key in keys.vals()) {
    assert trie.add(key, "");
  };

  for (key in keys.vals()) {
    assert (trie.get(key) == ?"");
  };

  for (key in keysAbsent.vals()) {
    assert trie.get(key) == null;
  };
};
