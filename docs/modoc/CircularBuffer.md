# CircularBuffer

## Class `CircularBuffer<T>`

``` motoko
class CircularBuffer<T>(capacity : Nat)
```

Circular buffer, which preserves amount of pushed values

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
func unshare(data : ([var ?T], Nat, Int))
```

Unshare from stable content
