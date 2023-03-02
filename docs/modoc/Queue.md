# Queue

## Type `Id`
``` motoko
type Id = Nat
```

Unique `Id` of element added to the `Queue`.

## Class `Queue<X>`

``` motoko
class Queue<X>()
```

FIFO queue implemented as singly linked list.

Example:
```motoko
let queue = Queue.Queue<Nat>();
```

### Function `get`
``` motoko
func get(id : Id) : ?X
```

Returns element with `id` in queue and `null` if the element was already deleted.

Example:
```motoko
let queue = Queue.Queue<Nat>();
ignore queue.enqueue(0);
let id = queue.enqueue(1);
ignore queue.dequeue();
assert queue.get(id) == ?1;
```

Runtime: `O(n)` where `n` is the number of elements in the queue.


### Function `index_of`
``` motoko
func index_of(id : Id) : ?Nat
```

Returns position from the beginning of an element with `id` returned by `enqueue`.

Example:
```motoko
let queue = Queue.Queue<Nat>();
assert queue.index_of(queue.enqueue(1)) == ?0;
```

Runtime: `O(1)`.


### Function `enqueue`
``` motoko
func enqueue(value : X) : Id
```

Inserts element to the back of the queue.
Returns unique among all the `enqueue` opertions `id` of the inserted element.

Example:
```motoko
let queue = Queue.Queue<Nat>();
ignore queue.enqueue(1);
assert queue.dequeue() == ?1;
```

Runtime: `O(1)`.


### Function `peek`
``` motoko
func peek() : ?X
```

Returns `null` if `queue` is empty. Otherwise, it returns first element in the queue.

Example:
```motoko
let queue = Queue.Queue<Nat>();
ignore queue.enqueue(1);
assert queue.peek() == ?1;
```

Runtime: `O(1)`.


### Function `dequeue`
``` motoko
func dequeue() : ?X
```

Remove the element on the front end of a queue.
Returns `null` if `queue` is empty. Otherwise, it returns removed element.

Example:
```motoko
let queue = Queue.Queue<Nat>();
ignore queue.enqueue(1);
assert queue.dequeue() == ?1;
```

Runtime: `O(1)`.


### Function `size`
``` motoko
func size() : Nat
```

Returns number of elements in the queue.

Example:
```motoko
let queue = Queue.Queue<Nat>();
ignore queue.enqueue(1);
assert queue.size() == 1;
```

Runtime: `O(1)`.
