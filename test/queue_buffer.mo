import Queue "../src/QueueBuffer";
import { Idx } "../src/QueueBuffer";

import { print } "mo:base/Debug";
import { toText } "mo:base/Nat";


var q = Queue.BufferedQueue<Nat>();
let n = 100;

assert (q.peek() == null);


var i = 0;

while (i < n + n) {
  assert (q.size() == i);
  assert (q.push(i).val == i);
  assert (q.peek() == ?0);
  i += 1;
};

assert not q.prune();

i := 0;

while (i < n) {
  assert (q.size() == (n + n - i : Nat));
  assert (q.peek() == ?i);
  assert (q.pop() == ?i);
  i += 1;
};


assert (q.size() == n);

assert q.indexOf(Idx<None, Nat>(0, func (x, y) = x + y)) == ?#Buf(0);
assert q.indexOf(Idx<None, Nat>(n, func (x, y) = x + y)) == ?#Que(0);
assert q.indexOf(Idx<None, Nat>(n * 2,  func (x, y) = x + y)) == null;

i := 0;

while (i < n) {
  assert (q.get(Idx<None, Nat>(i, func (x, y) = x + y)) == ?#Buf(i));
  i += 1;
};


i := 0;

while (i < n) {
  assert q.prune();
  i += 1;
};

assert q.indexOf(Idx<None, Nat>(0, func (x, y) = x + y)) == ?#Prun;

i := 0;

while (i < n) {
  assert (q.get(Idx<None, Nat>(i, func (x, y) = x + y)) == ?#Prun);
  i += 1;
};

assert (q.get(Idx<None, Nat>(n * 2, func (x, y) = x + y)) == null);


i := n;

while (i < n + n) {
  assert (q.get(Idx<None, Nat>(i, func (x, y) = x + y)) == ?#Que(i));
  i += 1;
};

q := Queue.BufferedQueue<Nat>();
assert q.size() == 0;
i := 0;

label iter while (i < 5) {
  q.put(i);
  assert q.size() == 1;
  ignore q.pop();
  assert q.size() == 0;
  i += 1;
};
