# QueueBuffer

## Class `QueueBuffer<X>`

``` motoko
class QueueBuffer<X>()
```

A queue with fast random access, which preserves history of popped values

### Function `rewindIndex`
``` motoko
func rewindIndex() : Nat
```

get index of oldest item in queue history


### Function `headIndex`
``` motoko
func headIndex() : Nat
```

get index of oldest item in queue


### Function `nextIndex`
``` motoko
func nextIndex() : Nat
```

get next index which will be issued


### Function `queueSize`
``` motoko
func queueSize() : Nat
```

amount of items in the queue


### Function `fullSize`
``` motoko
func fullSize() : Nat
```

total amount of items in the queue and history


### Function `push`
``` motoko
func push(x : X) : Nat
```

append item to queue tail


### Function `pop`
``` motoko
func pop() : ?(Nat, X)
```

pop item from queue head


### Function `peek`
``` motoko
func peek() : ?(Nat, X)
```

get item from queue head


### Function `get`
``` motoko
func get(index : Nat) : ?X
```

get item by id


### Function `pruneAll`
``` motoko
func pruneAll()
```

clear history


### Function `pruneTo`
``` motoko
func pruneTo(n : Nat)
```

clear history up to provided item id


### Function `rewind`
``` motoko
func rewind()
```

restore whole history in the queue
