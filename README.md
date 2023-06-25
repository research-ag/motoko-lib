# motoko-lib
Motoko general purpose libraries

See documentation here: https://research-ag.github.io/motoko-lib/

## Use this library

### Mops
mops.toml:
```
mrr = "https://github.com/research-ag/motoko-lib#main"
```


### Vessel

vessel.dhall:
```
{
  dependencies = [ "base", "mrr" ],
  compiler = Some "0.9.3"
}
```

package-set.dhall:
```
[ { dependencies = [] : List Text
  , name = "base"
  , repo = "https://github.com/dfinity/motoko-base.git"
  , version = "moc-0.9.3"
  }
, { dependencies = [ "base" ]
  , name = "mrr"
  , repo = "https://github.com/research-ag/motoko-lib"
  , version = "main"
  }
]
```

## Library contents
### Vector

Vector with `O(sqrt(n))` memory waste based on paper "Resizable Arrays in Optimal Time and Space" by Brodnik, Carlsson, Demaine, Munro and Sedgewick (1999).

### Queue

Simple queue implemented as singly linked list.

### TokenHandler

Library that allows a canister to detect deposits by individual users into per-user subaccounts on an ICRC1 ledger.

## Unit tests

```
cd test
make
```

Or, run individual tests by `make vector`, etc.

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
