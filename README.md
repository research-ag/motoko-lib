# motoko-lib
Motoko general purpose libraries

## vector

Vector with O(sqrt(n)) memory waste based on paper "Resizable Arrays in Optimal Time and Space" by Brodnik, Carlsson, Demaine, Munro and Sedgewick (1999).

## sha2

A new optimization of the whole Sha2 family. We benchmarked the incremental cost per block/chunk to be the following:

sha224/sha256: 27,596 cycles per chunk (64 bytes) or 431 cycles per byte
sha512 variants: 40,128 cycles per chunk (128 bytes) or 313 cycles per byte

This is about 80% faster than most other implementations that are being used right now.  