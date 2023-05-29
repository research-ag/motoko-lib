import Queue "../src/Queue";
import {test; suite} "mo:test";

var q = Queue.Queue<Nat>();
let n = 100;

suite("Queue", func() {
  test("test", func() {
    assert (q.peek() == null);

    var i = 0;
    while (i < n + n) {
      assert (q.size() == i);
      assert (q.push(i) == i);
      assert (q.peek() == ?0);
      i += 1;
    };

    i := 0;
    while (i < n) {
      assert (q.size() == (n + n - i : Nat));
      assert (q.peek() == ?i);
      assert (q.pop() == ?i);
      i += 1;
    };

    assert (q.size() == n);

    i := 0;
    while (i < n) {
      assert (q.get(i) == null);
      i += 1;
    };

    i := n;
    while (i < n + n) {
      assert (q.get(i) == ?i);
      i += 1;
    };

    q := Queue.Queue<Nat>();
    i := 0;
    while (i < 5) {
      ignore q.push(1);
      assert q.size() == 1;
      ignore q.pop();
      assert q.size() == 0;
      i += 1;
    };
  });
})
