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
  , version = "0.2"
  }
]
```

example.mo
```
import Sha256 "mo:mrr/Sha256";
import Vec "mo:mrr/Vector";

actor {
  let v = Vec.new<Nat8>();

  public query func greet() : async Blob  {
    Sha256.fromIter(#sha256, Vec.vals(v));
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

The cost per block/chunk is:

* sha224/sha256: 34,642 cycles per chunk (64 bytes) or 541 cycles per byte
* sha512 variants: 53,930 cycles per chunk (128 bytes) or 421 cycles per byte

The cost for hashing the empty message is:

* sha256: 36,940 cycles
* sha512: 56,233 cycles

This means the per message overhead for setting up the Digest class, padding, length bytes, and extraction of the digest is not noticeable.

### Comparison

We measured the most commonly used sha256 implementations at between 48k - 52k cycles per chunk and the empty message at around 100k cycles.

## Unit tests

```
cd test
make
```

Or, run individual tests by `make vector`, `make sha2`, etc.

## Benchmarks

```
cd bench
dfx start --background --clean
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
import Sha2 "mo:mrr/Sha256";
import Blob "mo:base/Blob";

let b = Blob.fromArray([] : [Nat8]);
Sha256.fromBlob(#sha256,b)
```

https://embed.smartcontracts.org/motoko/g/5YAikwp8VvVu8AfcaT8L8ji7wBvptRDc6F2bXWX8uZ4DoAiuzL7EJyQYuYmcgxdCRDjWPbuBwU4Z35LTeh84xJtH57Jrt2HjkjmCDVWhuX4QmhxVd1MmwnyYn5mBeWR3JVS2Adswf9MPtkbkkHKzXyg85kFo1FGiAWawAmUTcVNg7rZLFBdtdzoPc9UD9yk5P?lines=7
