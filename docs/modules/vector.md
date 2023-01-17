# Vector

The Vector data structure is meant to be a replacement for Array when a growable and/or shrinkable data structure is needed.
It provides random access like Array and Buffer and can grow and shrink at the end like Buffer can.
Unlike Buffer the memory overhead for allocated but no yet used space is O(sqrt(n)) instead of O(n).

## Design

The data structure is based on the paper "Resizable Arrays in Optimal Time and Space" by Brodnik, Carlsson, Demaine, Munro and Sedgewick (1999) ([pdf](https://sedgewick.io/wp-content/themes/sedgewick/papers/1999Optimal.pdf)).

## Examples

<iframe src="https://embed.smartcontracts.org/motoko/g/DLr1Cy6mYjpKc4apwqWWSzBL6iYPq9EvGHUa5dDxt8wHhRUJJBCPZv6NdPU3fEvaaxG6iEdcybWdGHJ1sUFJADPeWmrv2WAgxwd35aesNfnqm6U5CfKJ2VM9iYjfj7udbiDNQLaEKSvmzpR4YoQBFVUt3pzMLoHiCk6wu8u5keX2JaE?lines=9" width="100%" height="336" style="border:0" title="Motoko code snippet" />
