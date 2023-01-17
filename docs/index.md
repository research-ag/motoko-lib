# Motoko-lib
A library of Motoko packages that extend Motoko's base library.

Modules:

* Vector - a growable mutable array
* Sha2 - the complete Sha2 family of hash functions

## Vector

The Vector data structure is meant to be a replacement for Array when a growable and/or shrinkable data structure is needed.
It provides random access like Array and Buffer and can grow and shrink at the end like Buffer can.
Unlike Buffer the memory overhead for allocated but no yet used space is O(sqrt(n)) instead of O(n).

## Sha2

Sha2 provides all hash functions from the Sha2 family, those based on 32 byte state as well as those based on 64 byte state.
Unlike other packages, this package allows to hash types `Blob` and `Iter<Nat8>`. 
