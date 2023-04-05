# Circular buffer

Circular buffer with fixed capacity which allows for pushing the element inside with overriding the earliest added element and querying slices of stored data.

Especially useful for storing logs, when the lost of information isn't sensitive.

Typical use case:

- construct class with `capacity`.

- `push` some number of elements.

- query `available` interval of indices stored.

- use `get` to access single elements of the buffer.

- or `slice` some interval of elements. The interval must not exceed that returned by `available` function.