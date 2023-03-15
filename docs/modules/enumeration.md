# Enumeration

Enumeration of `Blob`s in order they are added.
The data structure supports two maps: 

- `lookup` function from `Blob` to `Nat`, which returns number in which given `Blob` was added or null if there is no such `Blob`. Works in `O(log(n))`.

- `get` function from `Nat` to `Blob`, which returns `Blob` with given index. Works in `O(1)`

For the map from `Blob` to index `Nat` it's implemented as red-black tree, for map from index `Nat` to `Blob` the implementation is an array.
`Blob`s are stored once, in the array, while in red-black tree we store index of a `Blob`.

The data structure does not support the delition of `Blob`s.