import QueueBuffer "../src/QueueBuffer";
import Iter "mo:base/Iter";
import Debug "mo:base/Debug";
import Nat "mo:base/Nat";

let buf = QueueBuffer.QueueBuffer<Text>();

// test defaults
assert buf.rewindIndex() == 0;
assert buf.headIndex() == 0;
assert buf.nextIndex() == 0;
assert buf.queueSize() == 0;
assert buf.fullSize() == 0;

// test that empty buffer will not crash:
buf.rewind();
buf.pruneAll();
ignore buf.peek();
ignore buf.get(123);
ignore buf.pop();

// add some values:
assert buf.push("a") == 0;
assert buf.push("b") == 1;
assert buf.push("c") == 2;
assert buf.push("d") == 3;
assert buf.push("e") == 4;
assert buf.push("f") == 5;

assert buf.nextIndex() == 6;
assert buf.queueSize() == 6;
assert buf.fullSize() == 6;

// test peek
assert buf.peek() == ?(0, "a");
assert buf.peek() == ?(0, "a");

assert buf.queueSize() == 6;
assert buf.rewindIndex() == 0;
assert buf.headIndex() == 0;
assert buf.nextIndex() == 6;

// test get value in the middle
assert buf.get(2) == ?"c";

// test dequeue
assert buf.pop() == ?(0, "a");
assert buf.pop() == ?(1, "b");
assert buf.pop() == ?(2, "c");

assert buf.peek() == ?(3, "d");
assert buf.rewindIndex() == 0;
assert buf.headIndex() == 3;
assert buf.nextIndex() == 6;
assert buf.queueSize() == 3;
assert buf.fullSize() == 6;

// test dequeue and trigger rotation
assert buf.pop() == ?(3, "d");

assert buf.peek() == ?(4, "e");
assert buf.rewindIndex() == 0;
assert buf.headIndex() == 4;
assert buf.nextIndex() == 6;
assert buf.queueSize() == 2;
assert buf.fullSize() == 6;

// test adding values after rotation
assert buf.push("g") == 6;

assert buf.peek() == ?(4, "e");
assert buf.rewindIndex() == 0;
assert buf.headIndex() == 4;
assert buf.nextIndex() == 7;
assert buf.queueSize() == 3;
assert buf.fullSize() == 7;

// test rewinding
buf.rewind();

assert buf.peek() == ?(0, "a");
assert buf.queueSize() == 7;
assert buf.fullSize() == 7;

// test pruning history
assert buf.pop() == ?(0, "a");
assert buf.pop() == ?(1, "b");
assert buf.pop() == ?(2, "c");
buf.pruneAll();

assert buf.peek() == ?(3, "d");
assert buf.rewindIndex() == 3;
assert buf.headIndex() == 3;
assert buf.nextIndex() == 7;
assert buf.queueSize() == 4;
assert buf.fullSize() == 4;


// test add many values
for (i in Iter.range(1, 10000)) {
  ignore buf.push("test");
};
assert buf.peek() == ?(3, "d");
assert buf.rewindIndex() == 3;
assert buf.headIndex() == 3;
assert buf.nextIndex() == 10007;
assert buf.queueSize() == 10004;
assert buf.fullSize() == 10004;

// test pop many values
for (i in Iter.range(1, 5000)) {
  ignore buf.pop();
};
assert buf.peek() == ?(5003, "test");
assert buf.rewindIndex() == 3;
assert buf.headIndex() == 5003;
assert buf.nextIndex() == 10007;
assert buf.queueSize() == 5004;
assert buf.fullSize() == 10004;

// test prune partially
buf.pruneTo(2503);
assert buf.peek() == ?(5003, "test");
assert buf.rewindIndex() == 2503;
assert buf.headIndex() == 5003;
assert buf.nextIndex() == 10007;
assert buf.queueSize() == 5004;
assert buf.fullSize() == 7504;

// test get value in the middle
assert buf.get(1) == null;
assert buf.get(1000000) == null;
assert buf.get(3000) == ?"test"; // got from history
assert buf.get(6000) == ?"test"; // got from regualr part of the queue
