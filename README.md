# Contents
Motoko general purpose libraries

## vector

Vector with O(sqrt(n)) memory waste based on paper "Resizable Arrays in Optimal Time and Space" by Brodnik, Carlsson, Demaine, Munro and Sedgewick (1999).

## sha2

A new optimization of the whole Sha2 family. The incremental cost per block/chunk is:

* sha224/sha256: 27,596 cycles per chunk (64 bytes) or 431 cycles per byte
* sha512 variants: 40,128 cycles per chunk (128 bytes) or 313 cycles per byte

(For comparison this is roughly 80% faster than most other implementations that are being widely used right now.) 

# Run unit tests

```
cd test
make
```

Or, run individual test by `make vector`, `make sha2`, etc.

# Run benchmark

```
dfx start --background --clean
cd bench
dfx build --check vector_bench && ic-repl ic-repl/vector.sh
```
or
```
dfx build --check sha2_bench && ic-repl ic-repl/sha2.sh
```
