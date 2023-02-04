# motoko-lib
Motoko general purpose libraries

## Use this library

vessel.dhall:
```
{
  dependencies = [ "base", "mrr" ],
  compiler = Some "0.7.6"
}
```

package-set.dhall:
```
[ { dependencies = [] : List Text
  , name = "base"
  , repo = "https://github.com/dfinity/motoko-base.git"
  , version = "moc-0.7.6"
  }
, { dependencies = [ "base" ]
  , name = "mrr"
  , repo = "https://github.com/research-ag/motoko-lib"
  , version = "0.1"
  }
]
```

example.mo
```
import Sha2 "mo:mrr/Sha2";
import Vec "mo:mrr/Vector";

actor {
  let v = Vec.new<Nat8>();

  public query func greet() : async Blob  {
    Sha2.fromIter(#sha256, Vec.vals(v));
  };
};
```

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

The cost for hashing the empty message is:

* sha256: 66,659 cycles
* sha512: 110,881 cycles

This means the per message overhead (setting up the Digest class, padding, length bytes, and extraction of the digest) is:

* sha256: 39,063 cycles (equivalent to 1.41 chunks)
* sha512: 70,753 cycles (equivalent to 1.76 chunks)

### Comparison

We measured the most commonly used sha256 implementations as follows:

* incremental cost per block/chunk: 48,818-49,717 cycles (ours is ~55% of that)
* cost for hashing empty message: 94,384-98,924 cycles (ours is ~70% of that) 

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
