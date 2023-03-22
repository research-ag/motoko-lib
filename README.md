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

We measured the most commonly used sha256 implementations at between 48k - 52k cycles per chunk and the empty message at around 100k cycles.

### Enumeration

Enumeration of `Blob`s in order they are added, i.e. bidirectional map from `Blob` to number it was added, and inverse.

### Queue

Simple queue implemented as singly linked list.

### Prng

Several pseudo random number generators.


### TokenHandler

Library that allows a canister to detect deposits by individual users into per-user subaccounts on an ICRC1 ledger. 
Works asynchronously.

##### Responsibilities:
 - track the available balance for each user
 - consolidate the funds from the subaccounts into a main account but credit the user appropriately to always know an accurate number for the user’s spendable balance.
 - provide functionality to debit/credit user

##### Interface
- **Constructor** `TokenHandler(icrc1LedgerPrincipal : Principal, ownPrincipal : Principal)`
<br>
`icrc1LedgerPrincipal` is a principal of ICRC1 canister, used for tracking accounts and transferring tokens during consolidation
<br>
`ownPrincipal` is a principal of own canister, which should be registered in ICRC1 ledger and used by users to send tokens

- **Notify** `notify(p : Principal) : async* ()`
<br>
This function should be called after user sent some tokens to the appropriate subaccount, which belongs to us.
The handler will call icrc1_balance(S:P) to query the balance. It will detect if it has increased compared
to the last balance seen. If it has increased then it will adjust the deposit_balance (and hence the usable_balance).
It will also trigger a “consolidation”, i.e. moving the newly deposited funds from S:P to S:0.
Concurrent notify() for the same P are handled with locks.

- **Debit** `debit(p : Principal, amount : Nat) : Bool`
<br>
Deducts amount from P’s usable balance. Returns false if the balance is insufficient.

- **Credit** `credit(p : Principal, amount : Nat) : ()`
<br>
Adds amount to P’s usable balance

- **Query balance** `balance(p : Principal) : Nat`
<br>
Queries the usable balance

- **Balances info (for debug)** `info(p : Principal) : { deposit_balance : Nat; credit_balance : Int; }`
<br>
Queries all tracked balances

- **Get ICRC1 subaccount for principal** `principalToSubaccount(p : Principal) : Icrc1Interface.Subaccount`
<br>
This function returns corresponding subaccount for client. Use this function to inform user where to send tokens to.
The user has to send tokens to ICRC1 account
`(<this canister principal>, principalToSubaccount(<user's principal>))`

- **Process consolidation backlog** `processConsolidationBacklog() : async ()`
<br>
If some consolidation process has been failed, the account would have been added to the backlog, this function
will take one account from the backlog and retry the consolidation. Backlog works like a FIFO queue.
It is useful to call this function with some timer

- **Share** `share() : [(Principal, { deposit_balance : Nat; credit_balance : Int; })]`
<br>
This function returns the tracking info data in sharable format. This function has to be called before canister 
upgrade and value stored in stable memory

- **Unshare** `unshare(values : [(Principal, { deposit_balance : Nat; credit_balance : Int; })]) : ()`
<br>
This function consumes the shared tracking info and overwrites own tracking info storage with the data from it. 
This function has to be called after canister upgrade with provided data from stable memory


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
