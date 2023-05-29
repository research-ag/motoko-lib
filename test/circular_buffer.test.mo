import CircularBuffer "../src/CircularBuffer";
import Iter "mo:base/Iter";
import Debug "mo:base/Debug";
import {test; suite} "mo:test";

let c = CircularBuffer.CircularBuffer<Nat>(5);
suite("Circular Buffer", func() {

  test("Slice 0-2", func() {
    c.push(0);
    c.push(1);
    c.push(2);

    assert Iter.toArray(c.slice(0, 3)) == [0, 1, 2];
    assert Iter.toArray(c.slice(1, 3)) == [1, 2];
    assert Iter.toArray(c.slice(2, 3)) == [2];
    assert Iter.toArray(c.slice(0, 1)) == [0];
  });

  test("Slice 3-8", func() {
    c.push(3);
    c.push(4);
    c.push(5);
    c.push(6);
    c.push(7);
    c.push(8);

    let (a, b) = c.available();
    assert Iter.toArray(c.slice(a, b)) == [4, 5, 6, 7, 8];
    assert Iter.toArray(c.slice(a + 1, b - 1)) == [5, 6, 7];
  });
})
