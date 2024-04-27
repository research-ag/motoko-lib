// @testmode wasi

import Prng "mo:prng";
import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Nat8 "mo:base/Nat8";
import Nat16 "mo:base/Nat16";
import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";
import Region "mo:base/Region";
import Debug "mo:base/Debug";
import StableTrie "../src/StableTrie";

let key_size = 8;

let rng = Prng.Seiran128();
rng.init(0);

// Region full of random data
// 128 pages = 8 MB
let rnd = Region.new();
Debug.print(debug_show Region.grow(rnd, 128));

var n = 2 ** 20;
var pos : Nat64 = 0;
while (n > 0) {
  Region.storeNat64(rnd, pos, rng.next());
  n -= 1;
  pos += 8;
};

let trie = StableTrie.StableTrie(16, key_size, 0);

n := 1_000_000;
pos := 0;
while (n > 0) {
  let key = Region.loadBlob(rnd, pos, key_size);
  n -= 1;
  pos += 1;
  assert trie.add(key, "");
};

Debug.print("trie size: " # debug_show trie.size());
