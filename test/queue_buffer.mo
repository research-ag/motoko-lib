import Array "mo:base/Array";
import List "mo:base/List";
import { range } "mo:base/Iter";

import Queue "../src/QueueBuffer";
import { } "../src/QueueBuffer";


var q = Queue.BufferedQueue<Nat>();
let n = 100;

assert q.peek() == null;


for (i in range(0, n * 2 - 1)) {
  assert q.queueSize() == i;
  assert q.push(i) == i;
  assert q.peek() == ?0;
};

assert not q.prune();

for (i in range(0, n - 1)) {
  assert q.queueSize() == (n + n - i : Nat);
  assert q.peek() == ?i;
  assert q.pop() == ?i;
};


assert (q.queueSize() == n);

assert q.indexOf(0) == ?#Buf(0);
assert q.indexOf(n) == ?#Que(0);
assert q.indexOf(n * 2) == null;

for (i in range(0, n - 1)) {
  assert q.get(i) == ?#Buf(i);
};


for (i in range(0, n - 1)) {
  assert q.prune();
};

assert q.indexOf(0) == ?#Prun;

for (i in range(0, n - 1)) {
  assert q.get(i) == ?#Prun;
};

assert q.get(n * 2) == null;


for (i in range(n, n * 2 - 1)) {
  assert q.get(i) == ?#Que(i);
};

q := Queue.BufferedQueue<Nat>();
assert q.queueSize() == 0;

for (i in range(0, 4)) {
  q.put(i);
  assert q.queueSize() == 1;
  ignore q.pop();
  assert q.queueSize() == 0;
};

assert q.get(3) == ?#Buf(3);
assert q.pruneTo(3);
assert q.get(3) == ?#Prun;
assert q.get(4) == ?#Buf(4);
q.pruneAll();
assert q.get(4) == ?#Prun;


q := Queue.BufferedQueue<Nat>();

var values : List.List<Nat> = null;
for (value in range(0, n)) values := ?(value, values);

assert q.pushValues(List.toIter values) ==  values;
assert q.popValues 5 == ?List.fromArray([96, 97, 98, 99, 100]);
q.putValues(Array.vals([1, 2, 3, 4, 5]));
ignore q.popValues 90;
assert q.peekValues 11 == ?List.fromArray([5, 4, 3, 2, 1, 0, 1, 2, 3, 4, 5]);
