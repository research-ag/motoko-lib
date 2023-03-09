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
// The seed values were created with numpy like this:
//   import numpy
//   ss = numpy.random.SeedSequence(0)
//   ss.generate_state(3, dtype='uint64')
// produces output:
//   array([15793235383387715774, 12390638538380655177,  2361836109651742017], dtype=uint64)
// Then the next() values were created with numpy like this:
//   bg = numpy.random.SFC64(ss)
//   bg.random_raw(2)
// produces output:
//   array([10490465040999277362,  4331856608414834465], dtype=uint64)
let c = Prng.SFC64(24,11,3);
c.init3(15793235383387715774, 12390638538380655177, 2361836109651742017);
assert([c.next(), c.next()] == [10490465040999277362, 4331856608414834465]);
