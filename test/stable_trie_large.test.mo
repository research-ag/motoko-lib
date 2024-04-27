// @testmode wasi

import Prng "mo:prng";
import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Nat8 "mo:base/Nat8";
import Nat16 "mo:base/Nat16";
import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";

let key_size = 8;

let rng = Prng.Seiran128();
rng.init(0);

let arr = Array.tabulate<Blob>(
  30_000_000,
  func(i) {
    let x = rng.next();
    let l32 = Nat64.toNat32(x >> 32);
    let r32 = Nat64.toNat32(x & 0xffffffff);
    let ll16 = Nat32.toNat16(l32 >> 16);
    let lr16 = Nat32.toNat16(l32 & 0xffff);
    let rl16 = Nat32.toNat16(r32 >> 16);
    let rr16 = Nat32.toNat16(r32 & 0xffff);
    Blob.fromArray([
      Nat16.toNat8(ll16 >> 8),
      Nat16.toNat8(ll16 & 0xff),
      Nat16.toNat8(lr16 >> 8),
      Nat16.toNat8(lr16 & 0xff),
      Nat16.toNat8(rl16 >> 8),
      Nat16.toNat8(rl16 & 0xff),
      Nat16.toNat8(rr16 >> 8),
      Nat16.toNat8(rr16 & 0xff),
    ]);
  },
);

/*
let arr = Array.tabulate<Nat64>(
  100_000_000,
  func(i) = rng.next(),
);
*/
