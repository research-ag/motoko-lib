import CircularBuffer "../src/CircularBuffer";
import Iter "mo:base/Iter";
import Debug "mo:base/Debug";

let c = CircularBuffer.CircularBuffer<Nat>(5);

c.push(0);
c.push(1);
c.push(2);

assert Iter.toArray(c.range(0, 2)) == [0, 1, 2];
assert Iter.toArray(c.range(1, 2)) == [1, 2];
assert Iter.toArray(c.range(2, 2)) == [2];
assert Iter.toArray(c.range(0, 0)) == [0];

assert Iter.toArray(c.range(2, 1)) == [];
assert Iter.toArray(c.range(0, 3)) == [];

c.push(3);
c.push(4);
c.push(5);
c.push(6);
c.push(7);
c.push(8);

assert Iter.toArray(c.range(3, 5)) == [];

let ?(a, b) = c.available() else Debug.trap "No elements available";
assert Iter.toArray(c.range(a, b)) == [4, 5, 6, 7, 8];
assert Iter.toArray(c.range(a + 1, b - 1)) == [5, 6, 7];

let z = CircularBuffer.CircularBuffer<Nat>(1);

z.push(0);
let ?(x, y) = z.available() else Debug.trap "No elements available";


assert Iter.toArray(z.range(x, y)) == [0];
assert Iter.toArray(z.range(1, 0)) == [];


let e = CircularBuffer.CircularBuffer<Nat>(0);

e.push(42);
assert e.available() == null;
assert Iter.toArray(e.range(42, 7)) == [];
