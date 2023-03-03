import Nat64 "mo:base/Nat64";
import Array "mo:base/Array";
import Iter "mo:base/Iter";
import PRNG_Seiran128 "../src/Prng_Seiran128";

import Debug "mo:base/Debug";

let prng = PRNG_Seiran128.PRNG();
prng.init(401);

//Debug.print("Testing first values");
for (v in [0x8D4E3629D245305F:Nat64,
           0x941C2B08EB30A631:Nat64,
           0x4246BDC17AD8CA1E:Nat64,
           0x5D5DA3E87E82EB7C:Nat64]
       .vals()) {
    let n = prng.next();
    assert(v == n);
};

//Debug.print("Testing value after jump32");
prng.jump32();
assert(prng.next() == 0x3F6239D7246826A9);

//Debug.print("Testing value after jump64");
prng.jump64();
assert(prng.next() == 0xD780EC14D59D2D33);

//Debug.print("Testing value after jump96");
prng.jump96();
assert(prng.next() == 0x7DA59A41DC8721F2);
