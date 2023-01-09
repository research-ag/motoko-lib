import Iter "mo:base/Iter";

import Vector "../src/vector";

import Suite "mo:matchers/Suite";
import T "mo:matchers/Testable";
import M "mo:matchers/Matchers";
import Buffer "mo:base/Buffer";
import Option "mo:base/Option";
import Debug "mo:base/Debug";
import Nat "mo:base/Nat";
import Array "mo:base/Array";

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
