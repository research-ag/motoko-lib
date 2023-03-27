# motoko-lib
Motoko general purpose libraries

See documentation here: https://research-ag.github.io/motoko-lib/

## Use this library

vessel.dhall:
```
{
  dependencies = [ "base", "mrr" ],
  compiler = Some "0.8.4"
}
```

package-set.dhall:
```
[ { dependencies = [] : List Text
  , name = "base"
  , repo = "https://github.com/dfinity/motoko-base.git"
  , version = "moc-0.8.4"
  }
, { dependencies = [ "base" ]
  , name = "mrr"
  , repo = "https://github.com/research-ag/motoko-lib"
  , version = "main"
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

Vector with `O(sqrt(n))` memory waste based on paper "Resizable Arrays in Optimal Time and Space" by Brodnik, Carlsson, Demaine, Munro and Sedgewick (1999).

### Sha2

A new optimization of the whole Sha2 family.


#### Comparison

We measured the most commonly used sha256 implementations at between 48k - 52k instructions per chunk and the empty message at around 100k instructions.

### Enumeration

Enumeration of `Blob`s in order they are added, i.e. bidirectional map from `Blob` to number it was added, and inverse.

### Queue

Simple queue implemented as singly linked list.

### Prng

Several pseudo random number generators.


### TokenHandler

Library that allows a canister to detect deposits by individual users into per-user subaccounts on an ICRC1 ledger.

## Unit tests

```
cd test
make
```

Or, run individual tests by `make vector`, `make sha2`, etc.

## Benchmarks

See: https://github.com/research-ag/canister-profiling

## Docs

In project folder:
```
cd docs
make
cd ..
mkdocs serve
```

To deploy to `github.io`
```
mkdocs gh-deploy
```
