import Nat64 "mo:base/Nat64";
import Array "mo:base/Array";
import Iter "mo:base/Iter";
import Prng "../src/Prng";

import Debug "mo:base/Debug";

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
for (v in [0x1DDF8D516FF6CEE8:Nat64,
           0x89FC16A8C6D86B58:Nat64,
           0x2EE4BE4A743AF170:Nat64,
           0xE853A27E54140AFF:Nat64
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

//Debug.print("Testing SFC64 (split seed)");
for (v in [0xD3A380E0:Nat32,
           0xCDE2FEEA:Nat32,
           0x9680253D:Nat32,
           0x69BE6DEE:Nat32,
     ]
       .vals()) {
    let n = prng4.next();
    assert(v == n);
};
