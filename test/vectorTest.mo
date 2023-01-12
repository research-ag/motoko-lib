import Vector "../src/vector";

import Suite "mo:matchers/Suite";
import T "mo:matchers/Testable";
import M "mo:matchers/Matchers";

import Prim "mo:⛔";
import Iter "mo:base/Iter";
import Buffer "mo:base/Buffer";
import Option "mo:base/Option";
import Debug "mo:base/Debug";
import Nat "mo:base/Nat";
import Array "mo:base/Array";
import Nat32 "mo:base/Nat32";

let { run; test; suite } = Suite;

let n = 100;
let vector = Vector.new<Nat>();

let sizes = Buffer.Buffer<Nat>(0);
for (i in Iter.range(0, n)) {
    sizes.add(Vector.size(vector));
    Vector.add(vector, i);
};
sizes.add(Vector.size(vector));

run(
    suite(
        "add",
        [
            test(
                "sizes",
                Buffer.toArray(sizes),
                M.equals(T.array(T.natTestable, Iter.toArray(Iter.range(0, n + 1)))),
            ),
            test("elements",
                Vector.toArray(vector),
                M.equals(T.array(T.natTestable, Iter.toArray(Iter.range(0, n)))),
            )
        ],
    ),
);

run(
    suite(
        "iterator",
        [
            test("elements",
                Iter.toArray(Vector.vals(vector)),
                M.equals(T.array(T.natTestable, Iter.toArray(Iter.range(0, n)))),
            )
        ],
    ),
);

for (i in Iter.range(0, n)) {
    Vector.put(vector, i, n - i);
};

run(
    suite(
        "put",
        [
            test(
                "size",
                Vector.size(vector),
                M.equals(T.nat(n + 1)),
            ),
            test("elements",
                Vector.toArray(vector),
                M.equals(T.array(T.intTestable, Iter.toArray(Iter.revRange(n, 0)))),
            )
        ],
    ),
);

let removed = Buffer.Buffer<Nat>(0);
for (i in Iter.range(0, n)) {
    removed.add(Option.unwrap(Vector.removeLast(vector)));
};

run(
    suite(
        "removeLast",
        [
            test(
                "size",
                Vector.size(vector),
                M.equals(T.nat(0)),
            ),
            test("elements",
                Buffer.toArray(removed),
                M.equals(T.array(T.natTestable, Iter.toArray(Iter.range(0, n)))),
            ),
        ],
    ),
);

for (i in Iter.range(0, n)) {
    Vector.add(vector, i);
};

run(
    suite(
        "addAfterRemove",
        [
            test("elements",
                Vector.toArray(vector),
                M.equals(T.array(T.natTestable, Iter.toArray(Iter.range(0, n)))),
            )
        ],
    ),
);

func locate_readable<X>(index : Nat) : ?(Nat, Nat) {
    // index is any Nat except for 
    if (index >= 2 ** 32 - 1) {
        // We should check if index == 2 ** 32 - 1
        return null;
    };
    // it's convinient to work with index + 1
    // because (blocks before super block s) + 1 == 2 ** s
    let i = Nat32.fromNat(index) + 1;
    let lz = Nat32.bitcountLeadingZero(i);
    // super block s = bit length - 1 = (32 - leading zeros) - 1
    // i in binary = zeroes; 1; bits blocks mask; bits element mask
    // bit lengths =     lz; 1;     floor(s / 2);       ceil(s / 2)
    let s = 31 - lz;
    // floor(s / 2)
    let down = s >> 1;
    // ceil(s / 2) = floor((s + 1) / 2)
    let up = (s + 1) >> 1;
    // element mask = ceil(s / 2) ones in binary
    let e_mask = 1 << up - 1;
    //block mask = floor(s / 2) ones in binary 
    let b_mask = 1 << down - 1;
    // data blocks in even super blocks before current = 2 ** ceil(s / 2) - 1
    // data blocks in odd super blocks before current = 2 ** floor(s / 2) - 1
    // data blocks before the super block = element mask + block mask
    // elements before the super block = 2 ** s - 1, in case of (index + 1) = 2 ** s
    // first floor(s / 2) bits in (index + 1) after the highest bit = index of data block in super block
    // the next floor(s / 2) to the end of binary representation of (index + 1) = index of element in data block
    ?(Nat32.toNat(e_mask + b_mask + (i >> up) & b_mask), Nat32.toNat(i & e_mask));
};

// this was optimized in terms of cycles
func locate_optimal<X>(index : Nat) : (Nat, Nat) {
    // super block s = bit length - 1 = (32 - leading zeros) - 1
    // it's convinient to work with index + 1
    // because (blocks before super block s) + 1 == 2 ** s
    let i = Nat32.fromNat(index) +% 1;
    let lz = Nat32.bitcountLeadingZero(i);
    let lz2 = lz >> 1;
    // we split into cases to apply different optimizations in each one
    if (lz & 1 == 0) {
        // check index == 2 ** 32 - 1 as late as possible
        if (i == 0) Prim.trap("Error");
        // ceil(s / 2)  = 16 - lz2
        // floor(s / 2) = 15 - lz2
        // i in binary = zeroes; 1; bits blocks mask; bits element mask
        // bit lengths =     lz; 1;         15 - lz2;          16 - lz2
        // blocks before = 2 ** ceil(s / 2) - 1 + 2 ** floor(s / 2) - 1 =
        //               = (2 ** ceil(s / 2) - 2) + 2 ** floor(s / 2)
        //               = (mask ^ 1) + (1 << blocks mask length)
        //                              so we don't need to clean this bit from i >> ceil(s / 2)
        // element mask = 2 ** (16 - lz2) = (1 << 16) >> lz2 = 0xFFFF >> lz2
        // data block in super block + (1 << blocks mask length) = i >> (16 - lz2) = (i << lz2) >> 16
        let mask = 0xFFFF >> lz2;
        (Nat32.toNat((mask ^ 1) +% (i << lz2) >> 16), Nat32.toNat(i & mask));
    } else {
        // s / 2 = ceil(s / 2) = floor(s / 2) = 15 - lz2
        // i in binary = zeroes; 1; bits blocks mask; bits element mask
        // bit lengths =     lz; 1;         15 - lz2;          15 - lz2
        // block mask = element mask = mask = 2 ** (s / 2) - 1 = 2 ** (15 - lz2) - 1 = (1 << 15) >> lz2 = 0x7FFF >> lz2
        // blocks before = 2 * 2 ** (s / 2) - 2 = mask << 1
        // data block in super block = (i >> (s / 2)) & mask = (i >> (15 - lz2)) & mask = ((i << lz2) >> 15) & mask

        // we can't repeat the same trick as with even leading zeros, 
        // because of the corner case index = 0 => i = 1, mask = 0, blocks before = 0
        let mask = 0x7FFF >> lz2;
        (Nat32.toNat(mask << 1 +% ((i << lz2) >> 15) & mask), Nat32.toNat(i & mask));
    };
};

let locate_n = 1_000_000;
var i = 0;
while (i < locate_n) {
    assert(Option.unwrap(locate_readable(i)) == locate_optimal(i));
    assert(Option.unwrap(locate_readable(1_000_000_000 + i)) == locate_optimal(1_000_000_000 + i));
    assert(Option.unwrap(locate_readable(2 ** 32 - 2 - i)) == locate_optimal(2 ** 32 - 2 - i));
    i += 1;
};