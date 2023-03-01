import Queue "../src/Queue";

let q = Queue.Queue<Nat>();
let n = 100;

var i = 0;
while (i < n + n) {
  assert (q.size() == i);
  assert (q.enqueue(i) == i);
  i += 1;
};

i := 0;
while (i < n) {
  assert (q.size() == n + n - i);
  assert (q.dequeue() == ?i);
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
