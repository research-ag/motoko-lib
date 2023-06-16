import { range } "mo:base/Iter";

import Queue "../src/QueueBuffer";
import { Id } "../src/QueueBuffer";


var q = Queue.BufferedQueue<Nat>();
let n = 100;

assert q.peek() == null;


for (i in range(0, n * 2 - 1)) {
  assert q.size() == i;
  assert q.push(i).val == i;
  assert q.peek() == ?0;
};

assert not q.prune();

for (i in range(0, n - 1)) {
  assert q.size() == (n + n - i : Nat);
  assert q.peek() == ?i;
  assert q.pop() == ?i;
};


assert (q.size() == n);

assert q.indexOf(Id 0) == ?#Buf(0);
assert q.indexOf(Id n) == ?#Que(0);
assert q.indexOf(Id(n * 2)) == null;

for (i in range(0, n - 1)) {
  assert q.get(Id i) == ?#Buf(i);
};


for (i in range(0, n - 1)) {
  assert q.prune();
};

assert q.indexOf(Id 0) == ?#Prun;

for (i in range(0, n - 1)) {
  assert q.get(Id i) == ?#Prun;
};

assert q.get(Id(n * 2)) == null;


for (i in range(n, n * 2 - 1)) {
  assert q.get(Id i) == ?#Que(i);
};

q := Queue.BufferedQueue<Nat>();
assert q.size() == 0;

for (i in range(0, 4)) {
  q.put(i);
  assert q.size() == 1;
  ignore q.pop();
  assert q.size() == 0;
};

assert q.get(Id 3) == ?#Buf(3);
assert q.pruneTo(Id 3);
assert q.get(Id 3) == ?#Prun;
assert q.get(Id 4) == ?#Buf(4);
q.pruneAll();
assert q.get(Id 4) == ?#Prun;
