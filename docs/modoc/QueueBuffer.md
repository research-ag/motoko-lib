# QueueBuffer

## Class `QueueBuffer<X>`

``` motoko
class QueueBuffer<X>()
```

A queue with fast random access, which preserves history of popped values

### Function `histId`
``` motoko
func histId() : Nat
```

get id of oldest item in queue history


### Function `headId`
``` motoko
func headId() : Nat
```

get id of oldest item in queue


### Function `nextId`
``` motoko
func nextId() : Nat
```

get next id which will be issued


### Function `size`
``` motoko
func size() : Nat
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
