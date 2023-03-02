import Vector "../src/Vector";

import Suite "mo:matchers/Suite";
import T "mo:matchers/Testable";
import M "mo:matchers/Matchers";

import Prim "mo:⛔";
import Iter "mo:base/Iter";
import Buffer "mo:base/Buffer";
import Option "mo:base/Option";
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
    "clone",
    [
      test(
        "clone",
        Vector.toArray(Vector.clone(vector)),
        M.equals(T.array(T.natTestable, Vector.toArray(vector))),
      ),
    ],
  ),
); 

run(
  suite(
    "add",
    [
      test(
        "sizes",
        Buffer.toArray(sizes),
        M.equals(T.array(T.natTestable, Iter.toArray(Iter.range(0, n + 1)))),
      ),
      test(
        "elements",
        Vector.toArray(vector),
        M.equals(T.array(T.natTestable, Iter.toArray(Iter.range(0, n)))),
      ),
    ],
  ),
);

run(
  suite(
    "iterator",
    [
      test(
        "elements",
        Iter.toArray(Vector.vals(vector)),
        M.equals(T.array(T.natTestable, Iter.toArray(Iter.range(0, n)))),
      ),
      test(
        "revElements",
        Iter.toArray(Vector.valsRev(vector)),
        M.equals(T.array(T.intTestable, Iter.toArray(Iter.revRange(n, 0)))),
      )
    ],
  ),
);

let for_add_many = Vector.init<Nat>(n, 0);
Vector.addMany(for_add_many, n, 0);

run(
  suite(
    "init",
    [
      test(
        "init with toArray",
        Vector.toArray(Vector.init<Nat>(n, 0)),
        M.equals(T.array(T.natTestable, Array.tabulate<Nat>(n, func(_) = 0))),
      ),
      test(
        "init with vals",
        Iter.toArray(Vector.vals(Vector.init<Nat>(n, 0))),
        M.equals(T.array(T.natTestable, Array.tabulate<Nat>(n, func(_) = 0))),
      ),
      test(
        "add many with toArray",
        Vector.toArray(for_add_many),
        M.equals(T.array(T.natTestable, Array.tabulate<Nat>(2 * n, func(_) = 0))),
      ),
      test(
        "add many with vals",
        Iter.toArray(Vector.vals(for_add_many)),
        M.equals(T.array(T.natTestable, Array.tabulate<Nat>(2 * n, func(_) = 0))),
      ),
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
      test(
        "elements",
        Vector.toArray(vector),
        M.equals(T.array(T.intTestable, Iter.toArray(Iter.revRange(n, 0)))),
      ),
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
      test(
        "elements",
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
      test(
        "elements",
        Vector.toArray(vector),
        M.equals(T.array(T.natTestable, Iter.toArray(Iter.range(0, n)))),
      ),
    ],
  ),
);

run(
  suite(
    "firstAndLast",
    [
      test(
        "first",
        [Vector.first(vector)],
        M.equals(T.array(T.natTestable, [0])),
      ),
      test(
        "last of len N",
        [Vector.last(vector)],
        M.equals(T.array(T.natTestable, [n])),
      ),
      test(
        "last of len 1",
        [Vector.last(Vector.init<Nat>(1,1))],
        M.equals(T.array(T.natTestable, [1])),
      ),
    ],
  )
);

var sumN = 0;
Vector.iterate<Nat>(vector, func(i){ sumN += i});
var sum1 = 0;
Vector.iterate<Nat>(Vector.init<Nat>(1,1), func(i){ sum1 += i});
var sum0 = 0;
Vector.iterate<Nat>(Vector.new<Nat>(), func(i){ sum0 += i});

run(
  suite(
    "iterate",
    [
      test(
        "sumN",
        [sumN],
        M.equals(T.array(T.natTestable, [n*(n+1)/2])),
      ),
      test(
        "sum1",
        [sum1],
        M.equals(T.array(T.natTestable, [1])),
      ),
      test(
        "sum0",
        [sum0],
        M.equals(T.array(T.natTestable, [0])),
      ),
    ],
  )
);

func locate_readable<X>(index : Nat) : (Nat, Nat) {
  // index is any Nat32 except for
  // blocks before super block s == 2 ** s
  let i = Nat32.fromNat(index);
  // element with index 0 located in data block with index 1
  if (i == 0) {
    return (1, 0);
  };
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
  // data blocks in even super blocks before current = 2 ** ceil(s / 2)
  // data blocks in odd super blocks before current = 2 ** floor(s / 2)
  // data blocks before the super block = element mask + block mask
  // elements before the super block = 2 ** s
  // first floor(s / 2) bits in index after the highest bit = index of data block in super block
  // the next ceil(s / 2) to the end of binary representation of index + 1 = index of element in data block
  (Nat32.toNat(e_mask + b_mask + 2 + (i >> up) & b_mask), Nat32.toNat(i & e_mask));
};

// this was optimized in terms of cycles
func locate_optimal<X>(index : Nat) : (Nat, Nat) {
  // super block s = bit length - 1 = (32 - leading zeros) - 1
  // blocks before super block s == 2 ** s
  let i = Nat32.fromNat(index);
  let lz = Nat32.bitcountLeadingZero(i);
  let lz2 = lz >> 1;
  // we split into cases to apply different optimizations in each one
  if (lz & 1 == 0) {
    // ceil(s / 2)  = 16 - lz2
    // floor(s / 2) = 15 - lz2
    // i in binary = zeroes; 1; bits blocks mask; bits element mask
    // bit lengths =     lz; 1;         15 - lz2;          16 - lz2
    // blocks before = 2 ** ceil(s / 2) + 2 ** floor(s / 2)

    // so in order to calculate index of the data block
    // we need to shift i by 16 - lz2 and set bit with number 16 - lz2, bit 15 - lz2 is already set

    // element mask = 2 ** (16 - lz2) = (1 << 16) >> lz2 = 0xFFFF >> lz2
    let mask = 0xFFFF >> lz2;
    (Nat32.toNat(((i << lz2) >> 16) ^ (0x10000 >> lz2)), Nat32.toNat(i & (0xFFFF >> lz2)));
  } else {
    // s / 2 = ceil(s / 2) = floor(s / 2) = 15 - lz2
    // i in binary = zeroes; 1; bits blocks mask; bits element mask
    // bit lengths =     lz; 1;         15 - lz2;          15 - lz2
    // block mask = element mask = mask = 2 ** (s / 2) - 1 = 2 ** (15 - lz2) - 1 = (1 << 15) >> lz2 = 0x7FFF >> lz2
    // blocks before = 2 * 2 ** (s / 2)

    // so in order to calculate index of the data block
    // we need to shift i by 15 - lz2, set bit with number 16 - lz2 and unset bit 15 - lz2

    let mask = 0x7FFF >> lz2;
    (Nat32.toNat(((i << lz2) >> 15) ^ (0x18000 >> lz2)), Nat32.toNat(i & (0x7FFF >> lz2)));
  };
};

let locate_n = 1_000;
var i = 0;
while (i < locate_n) {
  assert (locate_readable(i) == locate_optimal(i));
  assert (locate_readable(1_000_000 + i) == locate_optimal(1_000_000 + i));
  assert (locate_readable(1_000_000_000 + i) == locate_optimal(1_000_000_000 + i));
  assert (locate_readable(2_000_000_000 + i) == locate_optimal(2_000_000_000 + i));
  assert (locate_readable(2 ** 32 - 1 - i) == locate_optimal(2 ** 32 - 1 - i));
  i += 1;
};
