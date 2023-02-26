# motoko-lib
Motoko general purpose libraries

See documentation here: https://research-ag.github.io/motoko-lib/

## Use this library

vessel.dhall:
```
{
  dependencies = [ "base", "mrr" ],
  compiler = Some "0.8.3"
}
```

package-set.dhall:
```
[ { dependencies = [] : List Text
  , name = "base"
  , repo = "https://github.com/dfinity/motoko-base.git"
  , version = "moc-0.8.2"
  }
, { dependencies = [ "base" ]
  , name = "mrr"
  , repo = "https://github.com/research-ag/motoko-lib"
  , version = "0.3"
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

#### Comparison

We measured the most commonly used sha256 implementations at between 48k - 52k cycles per chunk and the empty message at around 100k cycles.

### Enumeration

An append-only buffer of `Blob`s which enforces uniqueness of the `Blob` values, i.e. the same `Blob` can only be added once.
This creates an enumeration of the `Blobs` by consecutive numbers `0,1,2,..` in the order in which they are added.
The data structures also provides the inverse map which allows to lookup a given `Blob` and, if the `Blob` is present, returns its index.
Hence, if `N` `Blob`s have been added the Enumeration is an efficient bijective map `[0,N) -> Blob`.

The `lookup` direction of the map is implemented efficiently with a purpose-built simplified RBTree.

## Unit tests

```
cd test
make
```

Or, run individual tests by `make vector`, `make sha2`, etc.

## Benchmarks

Currently only for Vector and Sha2. The performance of Enumeration is the same as Buffer and RBTree from motoko-base for the two map directions.

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
import Sha256 "mo:mrr/Sha256";
import Blob "mo:base/Blob";

let b = Blob.fromArray([] : [Nat8]);
Sha256.fromBlob(#sha256,b)
```

https://embed.smartcontracts.org/motoko/g/5YAikwp8VvVu8AfcaT8L8ji7wBvpt7SX8vBTzLrVouknSbV7GVWT6HESKFfMmREbLYYEUowKobUxB1hQNo52ysC8AFF1JTS5AriGfgb7ur7QczG1tcYCYDYYqsJaU6xHgPXQAWMzEp7i8toUa9m9jqS1P3Bx6aNJZzMcSCsFRTc4PPYLSSyqprA9YbwLRm3bz?lines=7

### Enumeration

```
//@package mrr research-ag/motoko-lib/main/src
import Array "mo:base/Array";
import Enum "mo:mrr/Enumeration";
import Debug "mo:base/Debug";

let map = Enum.Enumeration();
let blobs : [Blob] = ["", "\01", "\00"];
for (b in blobs.vals()) {
  map.add(b);
};
Debug.print(debug_show map.share().1);
debug_show Array.map<Blob,?Nat>(blobs, map.lookup);
```

https://embed.smartcontracts.org/motoko/g/ErXSnfAra9mvwuXbkEcz5cAeADEuozpd4pS3RH7arZNJNxB6ds7HkXH9ZfsVYQe3dFaDLcQYd1ZSxaX3tHFGxY9PfudsLuiJ8FsRZbBj9uz7CEWtLHZ6TrnguHGCpEsenSpLG1LhCU1K6y3gwLG3wsLWFaE3uyPt9vyUJ8QbUs68ryNDSRkhpAkNc37YYMUDsnE2FocCC17eDzPuhykMXizhxCEchCMJszBvMLhVaQfncXrCWrsEmQfXGh7cBx5Xjjc2nobHD4rohvZyz5ZsTw46PJkttbzdKpuzdE2Rqm7BSdNadn2Bo4PZcSdWe?lines=13
