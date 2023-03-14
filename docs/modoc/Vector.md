# Vector
Resizable one-dimensional array with `O(sqrt(n))` memory waste.

## Type `Vector`
``` motoko
type Vector<X> = { var data_blocks : [var [var ?X]]; var i_block : Nat; var i_element : Nat }
```

Class `Vector<X>` provides a mutable list of elements of type `X`.
It is a substitution for `Buffer<X>` with `O(sqrt(n))` memory waste instead of `O(size)` where
n is the size of the data strucuture.
Based on the paper "Resizable Arrays in Optimal Time and Space" by Brodnik, Carlsson, Demaine, Munro and Sedgewick (1999).
Since this is internally a two-dimensional array the access times for put and get operations
will naturally be 2x slower than Buffer and Array. However, Array is not resizable and Buffer
has `O(size)` memory waste.

## Function `new`
``` motoko
func new<X>() : Vector<X>
```

Creates a new empty Vector for elements of type X.

Example:
```
let vec = Vector.new<Nat>(); // Creates a new Vector
```

## Function `init`
``` motoko
func init<X>(size : Nat, initValue : X) : Vector<X>
```

Create a Vector with `size` copies of the initial value.

```
let vec = Vector.init<Nat>(4, 2); // [2, 2, 2, 2]
```

Runtime: `O(size)`

## Function `addMany`
``` motoko
func addMany<X>(vec : Vector<X>, count : Nat, initValue : X)
```

Add to vector `count` copies of the initial value.

```
let vec = Vector.init<Nat>(4, 2); // [2, 2, 2, 2]
Vector.addMany(vec, 2, 1); // [2, 2, 2, 2, 1, 1]
```

Runtime: O(count)

## Function `clear`
``` motoko
func clear<X>(vec : Vector<X>)
```

Resets the vector to size 0, de-referencing all elements.

Example:
```

Vector.add(vec, 10);
Vector.add(vec, 11);
Vector.add(vec, 12);
Vector.clear(vec); // vector is now empty
Vector.toArray(vec) // => []
```

Runtime: `O(1)`

## Function `clone`
``` motoko
func clone<X>(vec : Vector<X>) : Vector<X>
```

Returns a copy of a Vector, with the same size.

Example:
```

vec.add(1);

let clone = Vector.clone(vec);
Vector.toArray(clone); // => [1]
```

Runtime: `O(size)`

## Function `size`
``` motoko
func size<X>(vec : Vector<X>) : Nat
```

Returns the current number of elements in the vector.

Example:
```
Vector.size(vec) // => 0
```

Runtime: `O(1)` (with some internal calculations)

## Function `add`
``` motoko
func add<X>(vec : Vector<X>, element : X)
```

Adds a single element to the end of a Vector,
allocating a new internal data block if needed,
and resizing the internal index block if needed.

Example:
```

Vector.add(vec, 0); // add 0 to vector
Vector.add(vec, 1);
Vector.add(vec, 2);
Vector.add(vec, 3);
Vector.toArray(vec) // => [0, 1, 2, 3]
```

Amortized Runtime: `O(1)`, Worst Case Runtime: `O(sqrt(n))`

## Function `removeLast`
``` motoko
func removeLast<X>(vec : Vector<X>) : ?X
```

Removes and returns the last item in the vector or `null` if
the vector is empty.

Example:
```

Vector.add(vec, 10);
Vector.add(vec, 11);
Vector.removeLast(vec); // => ?11
```

Amortized Runtime: `O(1)`, Worst Case Runtime: `O(sqrt(n))`

Amortized Space: `O(1)`, Worst Case Space: `O(sqrt(n))`

## Function `get`
``` motoko
func get<X>(vec : Vector<X>, index : Nat) : X
```

Returns the element at index `index`. Indexing is zero-based.
Traps if `index >= size`, error message may not be descriptive.

Example:
```

Vector.add(vec, 10);
Vector.add(vec, 11);
Vector.get(vec, 0); // => 10
```

Runtime: `O(1)`

## Function `getOpt`
``` motoko
func getOpt<X>(vec : Vector<X>, index : Nat) : ?X
```

Returns the element at index `index` as an option.
Returns `null` when `index >= size`. Indexing is zero-based.

Example:
```

Vector.add(vec, 10);
Vector.add(vec, 11);
let x = Vector.getOpt(vec, 0); // => ?10
let y = Vector.getOpt(vec, 2); // => null
```

Runtime: `O(1)`

## Function `put`
``` motoko
func put<X>(vec : Vector<X>, index : Nat, value : X)
```

Overwrites the current element at `index` with `element`. Traps if
`index` >= size. Indexing is zero-based.

Example:
```

Vector.add(vec, 10);
Vector.put(vec, 0, 20); // overwrites 10 at index 0 with 20
Vector.toArray(vec) // => [20]
```

Runtime: `O(1)`

## Function `indexOf`
``` motoko
func indexOf<X>(element : X, vec : Vector<X>, equal : (X, X) -> Bool) : ?Nat
```

Finds the first index of `element` in `vector` using equality of elements defined
by `equal`. Returns `null` if `element` is not found.

Example:
```

let vector = Vector.new<Nat>();
Vector.add(vec, 1);
Vector.add(vec, 2);
Vector.add(vec, 3);
Vector.add(vec, 4);

Vector.indexOf<Nat>(3, vector, Nat.equal); // => ?2
```

Runtime: `O(size)`

*Runtime and space assumes that `equal` runs in `O(1)` time and space.

## Function `lastIndexOf`
``` motoko
func lastIndexOf<X>(element : X, vec : Vector<X>, equal : (X, X) -> Bool) : ?Nat
```

Finds the last index of `element` in `vec` using equality of elements defined
by `equal`. Returns `null` if `element` is not found.

Example:
```
let vector = Vector.new<Nat>();
Vector.add(vec, 1);
Vector.add(vec, 2);
Vector.add(vec, 3);
Vector.add(vec, 4);
Vector.add(vec, 2);
Vector.add(vec, 2);

Vector.lastIndexOf<Nat>(2, vector, Nat.equal); // => ?5
```

Runtime: `O(size)`

*Runtime and space assumes that `equal` runs in `O(1)` time and space.

## Function `firstIndexWith`
``` motoko
func firstIndexWith<X>(vec : Vector<X>, predicate : X -> Bool) : ?Nat
```

Finds the index of the first element in `vec` for which `predicate` is true.
Returns `null` if no such element is found.

Example:
```

let vector = Vector.new<Nat>();
Vector.add(vec, 1);
Vector.add(vec, 2);
Vector.add(vec, 3);
Vector.add(vec, 4);

Vector.firstIndexWith<Nat>(vector, func(i) { i % 2 == 0 }); // => ?1
```

Runtime: `O(size)`

*Runtime and space assumes that `predicate` runs in `O(1)` time and space.

## Function `lastIndexWith`
``` motoko
func lastIndexWith<X>(vec : Vector<X>, predicate : X -> Bool) : ?Nat
```

Finds the index of the last element in `vec` for which `predicate` is true.
Returns `null` if no such element is found.

Example:
```

let vector = Vector.new<Nat>();
Vector.add(vec, 1);
Vector.add(vec, 2);
Vector.add(vec, 3);
Vector.add(vec, 4);

Vector.lastIndexWith<Nat>(vector, func(i) { i % 2 == 0 }); // => ?3
```

Runtime: `O(size)`

*Runtime and space assumes that `predicate` runs in `O(1)` time and space.

## Function `forAll`
``` motoko
func forAll<X>(vec : Vector<X>, predicate : X -> Bool) : Bool
```

Returns true iff every element in `vec` satisfies `predicate`.

Example:
```motoko include=initialize

Vector.add(vec, 2);
Vector.add(vec, 3);
Vector.add(vec, 4);

Vector.forAll<Nat>(vec, func x { x > 1 }); // => true
```

Runtime: `O(size)`

Space: `O(1)`

*Runtime and space assumes that `predicate` runs in O(1) time and space.

## Function `forSome`
``` motoko
func forSome<X>(vec : Vector<X>, predicate : X -> Bool) : Bool
```

Returns true iff some element in `vec` satisfies `predicate`.

Example:
```motoko include=initialize

Vector.add(vec, 2);
Vector.add(vec, 3);
Vector.add(vec, 4);

Vector.forSome<Nat>(vec, func x { x > 3 }); // => true
```

Runtime: O(size)

Space: O(1)

*Runtime and space assumes that `predicate` runs in O(1) time and space.

## Function `forNone`
``` motoko
func forNone<X>(vec : Vector<X>, predicate : X -> Bool) : Bool
```

Returns true iff no element in `vec` satisfies `predicate`.

Example:
```motoko include=initialize

Vector.add(vec, 2);
Vector.add(vec, 3);
Vector.add(vec, 4);

Vector.forNone<Nat>(vec, func x { x == 0 }); // => true
```

Runtime: O(size)

Space: O(1)

*Runtime and space assumes that `predicate` runs in O(1) time and space.

## Function `vals`
``` motoko
func vals<X>(vec : Vector<X>) : Iter.Iter<X>
```

Returns an Iterator (`Iter`) over the elements of a Vector.
Iterator provides a single method `next()`, which returns
elements in order, or `null` when out of elements to iterate over.

```

Vector.add(vec, 10);
Vector.add(vec, 11);
Vector.add(vec, 12);

var sum = 0;
for (element in Vector.vals(vec)) {
  sum += element;
};
sum // => 33
```

Note: This does not create a snapshot. If the returned iterator is not consumed at once,
and instead the consumption of the iterator is interleaved with other operations on the
Vector, then this may lead to unexpected results.

Runtime: `O(1)`

## Function `items`
``` motoko
func items<X>(vec : Vector<X>) : Iter.Iter<(X, Nat)>
```

Returns an Iterator (`Iter`) over the items, i.e. pairs of value and index of a Vector.
Iterator provides a single method `next()`, which returns
elements in order, or `null` when out of elements to iterate over.

```

Vector.add(vec, 10);
Vector.add(vec, 11);
Vector.add(vec, 12);
Iter.toArray(Vector.items(vec)); // [(10, 0), (11, 1), (12, 2)]
```

Note: This does not create a snapshot. If the returned iterator is not consumed at once,
and instead the consumption of the iterator is interleaved with other operations on the
Vector, then this may lead to unexpected results.

Runtime: `O(1)`

Warning: Allocates memory on the heap to store ?(X, Nat).

## Function `valsRev`
``` motoko
func valsRev<X>(vec : Vector<X>) : Iter.Iter<X>
```

Returns an Iterator (`Iter`) over the elements of a Vector in reverse order.
Iterator provides a single method `next()`, which returns
elements in reverse order, or `null` when out of elements to iterate over.

```

Vector.add(vec, 10);
Vector.add(vec, 11);
Vector.add(vec, 12);

var sum = 0;
for (element in Vector.vals(vec)) {
  sum += element;
};
sum // => 33
```

Note: This does not create a snapshot. If the returned iterator is not consumed at once,
and instead the consumption of the iterator is interleaved with other operations on the
Vector, then this may lead to unexpected results.

Runtime: `O(1)`

## Function `itemsRev`
``` motoko
func itemsRev<X>(vec : Vector<X>) : Iter.Iter<(X, Nat)>
```

Returns an Iterator (`Iter`) over the items in reverse order, i.e. pairs of value and index of a Vector.
Iterator provides a single method `next()`, which returns
elements in reverse order, or `null` when out of elements to iterate over.

```

Vector.add(vec, 10);
Vector.add(vec, 11);
Vector.add(vec, 12);
Iter.toArray(Vector.items(vec)); // [(12, 0), (11, 1), (10, 2)]
```

Note: This does not create a snapshot. If the returned iterator is not consumed at once,
and instead the consumption of the iterator is interleaved with other operations on the
Vector, then this may lead to unexpected results.

Runtime: `O(1)`

Warning: Allocates memory on the heap to store ?(X, Nat).

## Function `keys`
``` motoko
func keys<X>(vec : Vector<X>) : Iter.Iter<Nat>
```

Returns an Iterator (`Iter`) over the keys (indices) of a Vector.
Iterator provides a single method `next()`, which returns
elements in order, or `null` when out of elements to iterate over.

```

Vector.add(vec, 10);
Vector.add(vec, 11);
Vector.add(vec, 12);
Iter.toArray(Vector.items(vec)); // [0, 1, 2]
```

Note: This does not create a snapshot. If the returned iterator is not consumed at once,
and instead the consumption of the iterator is interleaved with other operations on the
Vector, then this may lead to unexpected results.

Runtime: O(1)

## Function `fromIter`
``` motoko
func fromIter<X>(iter : Iter.Iter<X>) : Vector<X>
```

Creates a Vector containing elements from `iter`.

Example:
```
import Nat "mo:base/Nat";

let array = [1, 1, 1];
let iter = array.vals();

let vec = Vector.fromIter<Nat>(iter); // => [1, 1, 1]
```

Runtime: `O(size)`

## Function `addFromIter`
``` motoko
func addFromIter<X>(vec : Vector<X>, iter : Iter.Iter<X>)
```

Adds elements to a Vector from `iter`.

Example:
```
import Nat "mo:base/Nat";

let array = [1, 1, 1];
let iter = array.vals();
let vec = Vector.init<Nat>(1, 2);

let vec = Vector.addFromIter<Nat>(vec, iter); // => [2, 1, 1, 1]
```

Runtime: `O(size)`, where n is the size of iter.

## Function `toArray`
``` motoko
func toArray<X>(vec : Vector<X>) : [X]
```

Creates an immutable array containing elements from a Vector.

Example:
```

Vector.add(vec, 1);
Vector.add(vec, 2);
Vector.add(vec, 3);

Vector.toArray<Nat>(vec); // => [1, 2, 3]

```

Runtime: `O(size)`

## Function `fromArray`
``` motoko
func fromArray<X>(array : [X]) : Vector<X>
```

Creates a Vector containing elements from an Array.

Example:
```
import Nat "mo:base/Nat";

let array = [2, 3];

let vec = Vector.fromArray<Nat>(array); // => [2, 3]
```

Runtime: `O(size)`

## Function `toVarArray`
``` motoko
func toVarArray<X>(vec : Vector<X>) : [var X]
```

Creates a mutable Array containing elements from a Vector.

Example:
```

Vector.add(vec, 1);
Vector.add(vec, 2);
Vector.add(vec, 3);

Vector.toVarArray<Nat>(vec); // => [1, 2, 3]

```

Runtime: O(size)

## Function `fromVarArray`
``` motoko
func fromVarArray<X>(array : [var X]) : Vector<X>
```

Creates a Vector containing elements from a mutable Array.

Example:
```
import Nat "mo:base/Nat";

let array = [var 2, 3];

let vec = Vector.fromVarArray<Nat>(array); // => [2, 3]
```

Runtime: `O(size)`

## Function `first`
``` motoko
func first<X>(vec : Vector<X>) : X
```

Returns the first element of `vec`. Traps if `vec` is empty.

Example:
```

let vec = Vector.init<Nat>(10, 1);

Vector.first(vec); // => 1
```

Runtime: `O(1)`

Space: `O(1)`

## Function `last`
``` motoko
func last<X>(vec : Vector<X>) : X
```

Returns the last element of `vec`. Traps if `vec` is empty.

Example:
```

let vec = Vector.fromArray<Nat>([1, 2, 3]);

Vector.last(vec); // => 3
```

Runtime: `O(1)`

Space: `O(1)`

## Function `iterate`
``` motoko
func iterate<X>(vec : Vector<X>, f : X -> ())
```

Applies `f` to each element in `vec`.

Example:
```
import Nat "mo:base/Nat";
import Debug "mo:base/Debug";

let vec = Vector.fromArray<Nat>([1, 2, 3]);

Vector.iterate<Nat>(vec, func (x) {
  Debug.print(Nat.toText(x)); // prints each element in vector
});
```

Runtime: `O(size)`

Space: `O(size)`

*Runtime and space assumes that `f` runs in O(1) time and space.

## Function `iterateRev`
``` motoko
func iterateRev<X>(vec : Vector<X>, f : X -> ())
```

Applies `f` to each element in `vec` in reverse order.

Example:
```
import Nat "mo:base/Nat";
import Debug "mo:base/Debug";

let vec = Vector.fromArray<Nat>([1, 2, 3]);

Vector.iterate<Nat>(vec, func (x) {
  Debug.print(Nat.toText(x)); // prints each element in vector in reverse order
});
```

Runtime: O(size)

Space: O(size)

*Runtime and space assumes that `f` runs in O(1) time and space.

## Value `Class`
``` motoko
let Class
```

Submodule with Vector as a class
This allows to use VectorClass as a drop-in replacement of Buffer

We provide all the functions of Buffer except for:
- sort
- insertBuffer
- insert
- append
- reserve
- capacity
- filterEntries
- remove
