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
// 8 pages = 512 kB (64k keys)
let rnd1 = Region.new();
let rnd2 = Region.new();
let buf = Region.new();
assert Region.grow(rnd1, 8) != 0xffff_ffff_ffff_ffff;
assert Region.grow(rnd2, 8) != 0xffff_ffff_ffff_ffff;
assert Region.grow(buf, 1) != 0xffff_ffff_ffff_ffff;

do {
  var n = 2 ** 16;
  var pos : Nat64 = 0;
  while (n > 0) {
    Region.storeNat64(rnd1, pos, rng.next());
    Region.storeNat64(rnd2, pos, rng.next());
    n -= 1;
    pos += 8;
  };
};

let trie = StableTrie.StableTrie(4, key_size, 0);

let max = 500;
var n1 = max;
var pos1 : Nat64 = 0;
// only works for key size 8
while (n1 > 0) {
  let key1 = Region.loadNat64(rnd1, pos1);
  var n2 = max;
  var pos2 : Nat64 = 0;
  while (n2 > 0) {
    let key2 = Region.loadNat64(rnd2, pos2);
    Region.storeNat64(buf, 0, key1 ^ key2);
    let key = Region.loadBlob(buf, 0, 8);
    n2 -= 1;
    pos2 += 8;
    assert trie.add(key, "");
  };
  n1 -= 1;
  pos1 += 8;
};


Debug.print("trie size: " # debug_show trie.size());
Debug.print("trie keys: " # debug_show (max * max));
Debug.print("bytes per key: " # debug_show (trie.size() / (max * max)));
