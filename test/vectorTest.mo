import Iter "mo:base/Iter";

import Vector "../src/vector";

import Suite "mo:matchers/Suite";
import T "mo:matchers/Testable";
import M "mo:matchers/Matchers";

let { run; test; suite } = Suite;

let n = 100;
let vector = Vector.new<Nat>();

for (i in Iter.range(0, n)) {
    Vector.add(vector, i);
};


run(
    suite(
        "add",
        [
            test(
                "size",
                Vector.size(vector),
                M.equals(T.nat(n + 1)),
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