import CircularBuffer "../src/CircularBuffer";
import Iter "mo:base/Iter";
import Debug "mo:base/Debug";

let c = CircularBuffer.CircularBuffer<Nat>(5);

c.push(0);
c.push(1);
c.push(2);

assert Iter.toArray(c.slice(0, 3)) == [0, 1, 2];
assert Iter.toArray(c.slice(1, 3)) == [1, 2];
assert Iter.toArray(c.slice(2, 3)) == [2];
assert Iter.toArray(c.slice(0, 1)) == [0];

c.push(3);
c.push(4);
c.push(5);
c.push(6);
c.push(7);
c.push(8);

let (a, b) = c.available();
assert Iter.toArray(c.slice(a, b)) == [4, 5, 6, 7, 8];
assert Iter.toArray(c.slice(a + 1, b - 1)) == [5, 6, 7];
