import Nat64 "mo:base/Nat64";
import Array "mo:base/Array";
import Iter "mo:base/Iter";
import Prng "../src/Prng";

import Debug "mo:base/Debug";

// --- Seiran tests ---
let prng = Prng.Seiran128();
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

// --- SFC tests ---

let prng1 = Prng.SFC64a();
prng1.init();

//Debug.print("Testing SFC64 (default seed)");
for (v in [0xC85C4D72435E6052:Nat64,
           0x578AB8DCF2A49A64:Nat64,
           0x8F3B7045FBEE3B23:Nat64,
           0xC4BC2F2013F16994:Nat64,
     ]
       .vals()) {
    let n = prng1.next();
    assert(v == n);
};

let prng2 = Prng.SFC64a();
prng2.init3(1,2,3);

//Debug.print("Testing SFC64 (split seed)");
for (v in [0x43F18723CBD74146:Nat64,
           0x0274759CF623808D:Nat64,
           0x709CC2D648942177:Nat64,
           0x410445D3D048B085:Nat64,
     ]
       .vals()) {
    let n = prng2.next();
    assert(v == n);
};

let prng3 = Prng.SFC32a();
prng3.init();

//Debug.print("Testing SFC32 (default seed)");
for (v in [0xB1BE92EA:Nat32,
           0x35152DE6:Nat32,
           0xF57C4105:Nat32,
           0xD1F7B548:Nat32,
     ]
       .vals()) {
    let n = prng3.next();
    assert(v == n);
};

let prng4 = Prng.SFC32a();
prng4.init3(1,2,3);

//Debug.print("Testing SFC32 (split seed)");
for (v in [0x736A3B41:Nat32,
           0xB2E53014:Nat32,
           0x3D56E4C7:Nat32,
           0xEDA6A65F:Nat32,
     ]
       .vals()) {
    let n = prng4.next();
    assert(v == n);
};

//Debug.print("Testing SFC64 (numpy)");
let c = Prng.SFC64(24,11,3);
let s0 : Nat64 = 2223390581541855661;
let s1 : Nat64 = 13597181201486318797;
let s2 : Nat64 = 12893663211123683265;
c.init3(s0,s1,s2);
Array.tabulate<Nat64>(2,func(i){c.next()});
