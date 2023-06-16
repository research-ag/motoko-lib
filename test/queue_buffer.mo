import Queue "../src/QueueBuffer";
import { Id } "../src/QueueBuffer";


var q = Queue.BufferedQueue<Nat>();
let n = 100;

assert q.peek() == null;


var i = 0;

while (i < n + n) {
  assert q.size() == i;
  assert q.push(i).val == i;
  assert q.peek() == ?0;
  i += 1;
};

assert not q.prune();

i := 0;

while (i < n) {
  assert q.size() == (n + n - i : Nat);
  assert q.peek() == ?i;
  assert q.pop() == ?i;
  i += 1;
};


assert (q.size() == n);

assert q.indexOf(Id 0) == ?#Buf(0);
assert q.indexOf(Id n) == ?#Que(0);
assert q.indexOf(Id(n * 2)) == null;

i := 0;

while (i < n) {
  assert q.get(Id i) == ?#Buf(i);
  i += 1;
};


i := 0;

while (i < n) {
  assert q.prune();
  i += 1;
};

assert q.indexOf(Id 0) == ?#Prun;

i := 0;

while (i < n) {
  assert q.get(Id i) == ?#Prun;
  i += 1;
};

assert q.get(Id(n * 2)) == null;


i := n;

while (i < n + n) {
  assert q.get(Id i) == ?#Que(i);
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
