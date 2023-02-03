# Contents
Motoko general purpose libraries

## vector

Vector with O(sqrt(n)) memory waste based on paper "Resizable Arrays in Optimal Time and Space" by Brodnik, Carlsson, Demaine, Munro and Sedgewick (1999).

## sha2

A new optimization of the whole Sha2 family. The incremental cost per block/chunk is:

* sha224/sha256: 27,596 cycles per chunk (64 bytes) or 431 cycles per byte
* sha512 variants: 40,128 cycles per chunk (128 bytes) or 313 cycles per byte

(Roughly 80% faster than some other popular implementations.) 

# Unit tests

```
cd test
make
```

Or, run individual tests by `make vector`, `make sha2`, etc.

# Benchmarks

```
dfx start --background --clean
cd bench
dfx build --check vector_bench && ic-repl ic-repl/vector.sh
dfx build --check sha2_bench && ic-repl ic-repl/sha2.sh
```

# Examples

## Vector

<iframe src="https://embed.smartcontracts.org/motoko/g/9KrDof3FNdp1qgWFnTzABEdBZF9virfqsZ3Lf8ryFgR3toa4bV962Jiik3uV3dpn2ASmyatiiTJuuWNbttd8j2yqpjqNWr3svT5QPukqbDdDonPGpPsKvKfWTzuSPAM5YZwNbS3XZE4Pt16y9Y4nm4qNE229ERkrjTYYd4Z8Zzr?lines=8" width="100%" height="312" style="border:0" title="Motoko code snippet" />

## Sha2

