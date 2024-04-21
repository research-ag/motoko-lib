// @testmode wasi

import Prng "mo:prng";
import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Nat64 "mo:base/Nat64";
import Nat8 "mo:base/Nat8";
import StableTrie "../src/StableTrie";

let n = 100;
let key_size = 5;

let rng = Prng.Seiran128();
rng.init(0);

let keys = Array.tabulate<Blob>(n, func (i) {
  Blob.fromArray(Array.tabulate<Nat8>(key_size, func (j) = Nat8.fromNat(Nat64.toNat(rng.next()) % 256)))
});

let keysAbsent = Array.tabulate<Blob>(n, func (i) {
  Blob.fromArray(Array.tabulate<Nat8>(key_size, func (j) = Nat8.fromNat(Nat64.toNat(rng.next()) % 256)))
});

let trie = StableTrie.StableTrie(key_size, 0);

for (key in keys.vals()) {
  assert trie.add(key, "");
};

for (key in keys.vals()) {
  assert trie.get(key) == ?"";
};

for (key in keysAbsent.vals()) {
  assert trie.get(key) == null;
};
