# TokenHandler

## Function `toSubaccount`
``` motoko
func toSubaccount(p : Principal) : ICRC1.Subaccount
```

Convert Principal to ICRC1.Subaccount

## Function `toPrincipal`
``` motoko
func toPrincipal(subaccount : ICRC1.Subaccount) : ?Principal
```

Convert ICRC1.Subaccount to Principal

## Type `Info`
``` motoko
type Info = { var deposit : Nat; var credit : Int }
```


## Type `StableData`
``` motoko
type StableData = ([(Principal, Info)], (Nat, [(Principal, Nat)]), Nat, ([var ?JournalRecord], Nat, Int))
```


## Class `TokenHandler`

``` motoko
class TokenHandler(icrc1LedgerPrincipal : Principal, ownPrincipal : Principal, fee : Nat, journalSize : Nat)
```


### Function `balance`
``` motoko
func balance(p : Principal) : Nat
```

query the usable balance


### Function `info`
``` motoko
func info(p : Principal) : Info and { var usable_balance : Nat }
```

query all tracked balances for debug purposes


### Function `queryJournal`
``` motoko
func queryJournal() : [JournalRecord]
```

query journal for debug purposes


### Function `isFrozen`
``` motoko
func isFrozen() : Bool
```

retrieve the current freeze state


### Function `backlogSize`
``` motoko
func backlogSize() : Nat
```

retrieve the current size of consolidation backlog


### Function `backlogFunds`
``` motoko
func backlogFunds() : Nat
```

retrieve the estimated sum of all balances in the backlog


### Function `consolidatedFunds`
``` motoko
func consolidatedFunds() : Nat
```

retrieve the sum of all successful consolidations


### Function `debit`
``` motoko
func debit(p : Principal, amount : Nat) : Bool
```

deduct amount from P’s usable balance. Return false if the balance is insufficient.


### Function `credit`
``` motoko
func credit(p : Principal, amount : Nat) : Bool
```

 add amount to P’s usable balance (the credit is created out of thin air)


### Function `notify`
``` motoko
func notify(p : Principal) : async* ?(Nat, Nat)
```

The handler will call icrc1_balance(S:P) to query the balance. It will detect if it has increased compared
to the last balance seen. If it has increased then it will adjust the deposit (and hence the usable_balance).
It will also schedule or trigger a “consolidation”, i.e. moving the newly deposited funds from S:P to S:0.
Returns the newly detected deposit and total usable balance if success, otherwise null


### Function `processBacklog`
``` motoko
func processBacklog() : async* ()
```

process first account from backlog


### Function `share`
``` motoko
func share() : StableData
```

serialize tracking data


### Function `unshare`
``` motoko
func unshare(values : StableData)
```

deserialize tracking data
