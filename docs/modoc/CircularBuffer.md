# CircularBuffer

## Class `CircularBuffer<T>`

``` motoko
class CircularBuffer<T>(capacity : Nat)
```


### Function `pushesAmount`
``` motoko
func pushesAmount() : Nat
```

Number of items that were ever pushed to the buffer


### Function `push`
``` motoko
func push(item : T)
```

Insert value into the buffer


### Function `available`
``` motoko
func available() : (Nat, Nat)
```

Return interval `[start, end)` of indices of elements available.


### Function `get`
``` motoko
func get(index : Nat) : ?T
```

Returns single element added with number `index` or null if element is not available or index out of bounds.


### Function `slice`
``` motoko
func slice(from : Nat, to : Nat) : Iter.Iter<T>
```

Return iterator to values added with numbers in interval `[from; to)`.
`from` should be not more then `to`. Both should be not more then `pushes`.


### Function `share`
``` motoko
func share() : ([var ?T], Nat, Int)
```

Share stable content


### Function `unshare`
``` motoko
func unshare(data : ([var ?T], Nat, Nat))
```

Unshare from stable content

## Type `CircularBufferStableState`
``` motoko
type CircularBufferStableState = { length : Nat; capacity : Nat; index : Region; var start : Nat; var count : Nat; data : Region; var start_data : Address; var count_data : Nat; var pushes : Nat }
```


## Class `CircularBufferStable<T>`

``` motoko
class CircularBufferStable<T>(serialize : T -> Blob, deserialize : Blob -> T, capacity : Nat, length : Nat)
```


### Function `assert_no_waste`
``` motoko
func assert_no_waste()
```

Assert no waste in regions memory


### Function `reset`
``` motoko
func reset()
```

Reset circular buffer state


### Function `pushesAmount`
``` motoko
func pushesAmount() : Nat
```

Number of items that were ever pushed to the buffer


### Function `deleteTo`
``` motoko
func deleteTo(index : Nat)
```



### Function `pop`
``` motoko
func pop() : ?T
```



### Function `push`
``` motoko
func push(item : T) : Bool
```

Insert value into the buffer


### Function `push_force`
``` motoko
func push_force(item : T)
```

Insert value into the buffer with overwriting


### Function `available`
``` motoko
func available() : (Nat, Nat)
```

Return interval `[start, end)` of indices of elements available.


### Function `get`
``` motoko
func get(index : Nat) : ?T
```

Returns single element added with number `index` or null if element is not available or index out of bounds.


### Function `slice`
``` motoko
func slice(from : Nat, to : Nat) : Iter.Iter<T>
```

Return iterator to values added with numbers in interval `[from; to)`.
`from` should be not more then `to`. Both should be not more then `pushes`.


### Function `share`
``` motoko
func share() : CircularBufferStableState
```

Share stable content


### Function `unshare`
``` motoko
func unshare(data : CircularBufferStableState)
```

Unshare from stable content
