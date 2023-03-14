# Enumeration

## Type `Tree`
``` motoko
type Tree = ?({#R; #B}, Tree, Nat, Tree)
```

Red-black tree of key `Nat`.

## Class `Enumeration`

``` motoko
class Enumeration()
```

Bidirectional enumeration of `Blob`s in order they are added.
For map from `Blob` to index `Nat` it's implemented as red-black tree, for map from index `Nat` to `Blob` the implementation is an array.
```
let e = Enumeration.Enumeration();
```

### Function `add`
``` motoko
func add(key : Blob) : Nat
```

Add `key` to enumeration. Returns `size` if the key in new to the enumeration and index of key in enumeration otherwise.
```
let e = Enumeration.Enumeration();
assert(e.add("abc") == 0);
assert(e.add("aaa") == 1);
assert(e.add("abc") == 0);
```
Runtime: O(log(n))


### Function `lookup`
``` motoko
func lookup(key : Blob) : ?Nat
```

Returns `?index` where `index` is the index of `key` in order it was added to enumeration, or `null` it `key` wasn't added.
```
let e = Enumeration.Enumeration();
assert(e.add("abc") == 0);
assert(e.add("aaa") == 1);
assert(e.lookup("abc") == ?0);
assert(e.lookup("aaa") == ?1);
assert(e.lookup("bbb") == null);
```
Runtime: O(log(n))


### Function `get`
``` motoko
func get(index : Nat) : Blob
```

Returns `Blob` with index `index`. Traps it index is out of bounds.
```
let e = Enumeration.Enumeration();
assert(e.add("abc") == 0);
assert(e.add("aaa") == 1);
assert(e.get(0) == "abc");
assert(e.get(1) == "aaa");
```
Runtime: O(1)


### Function `size`
``` motoko
func size() : Nat
```

Returns number of unique keys added to enumration.
```
let e = Enumeration.Enumeration();
assert(e.add("abc") == 0);
assert(e.add("aaa") == 1);
assert(e.size() == 2);
```
Runtime: O(1)


### Function `share`
``` motoko
func share() : (Tree, [var Blob], Nat)
```

Returns pair of red-black tree for map from `Blob` to `Nat` and array of `Blob` for map from `Nat` to `Blob`.
Returns number of unique keys added to enumration.
```
let e = Enumeration.Enumeration();
assert(e.add("abc") == 0);
assert(e.add("aaa") == 1);
e.unsafeUnshare(e.share()); // Nothing changed
```
Runtime: O(1)


### Function `unsafeUnshare`
``` motoko
func unsafeUnshare(data : (Tree, [var Blob], Nat))
```

Sets internal content from red-black tree for map from `Blob` to `Nat` and array of `Blob` for map from `Nat` to `Blob`.
`t` should be a valid red-black tree and correspond to array `a`. This function doesn't do validation.
```
let e = Enumeration.Enumeration();
assert(e.add("abc") == 0);
assert(e.add("aaa") == 1);
e.unsafeUnshare(e.share()); // Nothing changed
```
Runtime: O(1)
