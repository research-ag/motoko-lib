# motoko-lib
Motoko general purpose libraries

## Library contents
### Vector

Vector with O(sqrt(n)) memory waste based on paper "Resizable Arrays in Optimal Time and Space" by Brodnik, Carlsson, Demaine, Munro and Sedgewick (1999).

### Sha2

A new optimization of the whole Sha2 family. The supported algorithms are:

* sha224
* sha256
* sha512-224
* sha512-256
* sha384
* sha512

The incremental cost per block/chunk is:

* sha224/sha256: 27,596 cycles per chunk (64 bytes) or 431 cycles per byte
* sha512 variants: 40,128 cycles per chunk (128 bytes) or 313 cycles per byte

The sha256 have been measured to be approximately 80% faster than the most commonly used implementations. 

## Unit tests

```
cd test
make
```

Or, run individual tests by `make vector`, `make sha2`, etc.

## Benchmarks

```
dfx start --background --clean
cd bench
dfx build --check vector_bench && ic-repl ic-repl/vector.sh
dfx build --check sha2_bench && ic-repl ic-repl/sha2.sh
```

## Examples

### Vector

```
//@package mrr research-ag/motoko-lib/main/src
import Vector "mo:mrr/Vector";

let v = Vector.new<Nat>();
Vector.add(v,0);
Vector.add(v,1);
Vector.toArray(v);
```

https://embed.smartcontracts.org/motoko/g/9KrDof3FNdp1qgWFnTzABEdBZF9virfqsZ3Lf8ryFgR3toa4bV962Jiik3uV3dpn2ASmyatiiTJuuWNbttd8j2yqpjqNWr3svT5QPukqbDdDonPGpPsKvKfWTzuSPAM5YZwNbS3XZE4Pt16y9Y4nm4qNE229ERkrjTYYd4Z8Zzr?lines=8

### Sha2

```
//@package mrr research-ag/motoko-lib/main/src
import Sha2 "mo:mrr/Sha2";
import Blob "mo:base/Blob";

let b = Blob.fromArray([] : [Nat8]);
Sha2.fromBlob(#sha256,b)
```

https://embed.smartcontracts.org/motoko/g/22dBpZybfm9PtMARHfxM8RR3VkF7GDW1gXhkPVeGfjQFDAsPsWWiLnRcu32UHrXem316pQJxMb7J3grsrWBTmVhum5sLLu6dh6p734kyfiRhU8Wof1hzWeXehJMt4LdbJnFj25VPJATeLkDr8HCquWpyW1zRPsRzVX8JjXeLiRowhxu1czC4MLPtCJzRTi11?lines=7
