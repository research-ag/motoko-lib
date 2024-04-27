// @testmode wasi

import Prng "mo:prng";
import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Nat64 "mo:base/Nat64";
import Nat8 "mo:base/Nat8";

let key_size = 8;

let rng = Prng.Seiran128();
rng.init(0);

let arr = Array.tabulate<Blob>(
  1_300_000,
  func(i) {
    Blob.fromArray(Array.tabulate<Nat8>(key_size, func(j) = Nat8.fromNat(Nat64.toNat(rng.next()) % 256)));
  },
);

/*
let arr = Array.tabulate<Nat64>(
  100_000_000,
  func(i) = rng.next(),
);
*/
