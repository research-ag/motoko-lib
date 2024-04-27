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

let key_size = 8;

let rng = Prng.Seiran128();
rng.init(0);

let r = Region.new();
ignore Region.grow(r, 1);

let arr = Array.tabulate<Blob>(
  70_000_000,
  func(i) {
    Region.storeNat64(r, 0, rng.next());
    Region.loadBlob(r, 0, key_size);
  },
);

/*
let arr = Array.tabulate<Nat64>(
  100_000_000,
  func(i) = rng.next(),
);
*/
