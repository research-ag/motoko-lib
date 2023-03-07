import Nat64 "mo:base/Nat64";
import Array "mo:base/Array";
import Iter "mo:base/Iter";
import Prng "../src/Prng";

import Debug "mo:base/Debug";

let prng = Prng.SFC(24,11,3);
prng.init();

Debug.print("Testing first values");
for (v in [0xC85C4D72435E6052:Nat64,
           0x578AB8DCF2A49A64:Nat64,
           0x8F3B7045FBEE3B23:Nat64,
           0xC4BC2F2013F16994:Nat64,
     ]
       .vals()) {
    let n = prng.next();
    assert(v == n);
};
