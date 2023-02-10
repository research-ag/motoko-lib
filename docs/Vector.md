# Vector
Resizable one-dimensional array with `O(sqrt(n))` memory waste.

## Type `Vector`
```
type Vector<X> = { var data_blocks : [var [var ?X]]; var i_block : Nat; var i_element : Nat }
```

Class `Vector<X>` provides a mutable list of elements of type `X`.
It is a substitution for `Buffer<X>` with `O(sqrt(n))` memory waste instead of `O(n)` where
n is the size of the data strucuture.
Based on the paper "Resizable Arrays in Optimal Time and Space" by Brodnik, Carlsson, Demaine, Munro and Sedgewick (1999). 
Since this is internally a two-dimensional array the access times for put and get operations
will naturally be 2x slower than Buffer and Array. However, Array is not resizable and Buffer
has O(n) memory waste.

## Function `new`
```
func new<X>() : Vector<X>
```

Creates a new empty Vector for elements of type X.

Example:
```
let vec = Vector.new<Nat>(); // Creates a new Vector
```

## Function `clear`
```
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

Runtime: O(1)

## Function `clone`
```
func clone<X>(vec : Vector<X>) : Vector<X>
```

Returns a copy of a Vector, with the same size.

Example:
```

vec.add(1);

let clone = Vector.clone(vec);
Vector.toArray(clone); // => [1]
```

Runtime: O(n)

## Function `size`
```
func size<X>(vec : Vector<X>) : Nat
```

Returns the current number of elements in the vector.

Example:
```
Vector.size(vec) // => 0
```

Runtime: O(1) (with some internal calculations)

## Function `add`
```
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

Amortized Runtime: O(1), Worst Case Runtime: O(sqrt(n))

## Function `removeLast`
```
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

Amortized Runtime: O(1), Worst Case Runtime: O(sqrt(n))

Amortized Space: O(1), Worst Case Space: O(sqrt(n))

## Function `get`
```
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

Runtime: O(1) 

## Function `getOpt`
```
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

Runtime: O(1) 

## Function `put`
```
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

Runtime: O(1) 

## Function `vals`
```
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

Runtime: O(1)

## Function `fromIter`
```
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

Runtime: O(n)

## Function `toArray`
```
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

Runtime: O(n)

## Function `fromArray`
```
func fromArray<X>(array : [X]) : Vector<X>
```

Creates a Vector containing elements from an Array.

Example:
```
import Nat "mo:base/Nat";

let array = [2, 3];

let vec = Vector.fromArray<Nat>(array); // => [2, 3]
```

Runtime: O(n)

## Function `toVarArray`
```
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

Runtime: O(n)

## Function `fromVarArray`
```
func fromVarArray<X>(array : [var X]) : Vector<X>
```

Creates a Vector containing elements from a mutable Array.

Example:
```
import Nat "mo:base/Nat";

let array = [var 2, 3];

let vec = Vector.fromVarArray<Nat>(array); // => [2, 3]
```

Runtime: O(n)
