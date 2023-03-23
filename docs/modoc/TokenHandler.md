# TokenHandler

## Value `ICRC1Interface`
``` motoko
let ICRC1Interface
```


## Type `TrackingInfo`
``` motoko
type TrackingInfo = { deposit_balance : Nat; credit_balance : Int }
```


## Class `TokenHandler`

``` motoko
class TokenHandler(icrc1LedgerPrincipal : Principal, ownPrincipal : Principal)
```


### Function `notify`
``` motoko
func notify(principal : Principal) : async* ()
```

The handler will call icrc1_balance(S:P) to query the balance. It will detect if it has increased compared
to the last balance seen. If it has increased then it will adjust the deposit_balance (and hence the usable_balance).
It will also schedule or trigger a “consolidation”, i.e. moving the newly deposited funds from S:P to S:0.
Note: concurrent notify() for the same P have to be handled with locks.


### Function `debit`
``` motoko
func debit(principal : Principal, amount : Nat) : Bool
```

deduct amount from P’s usable balance. Return false if the balance is insufficient.


### Function `credit`
``` motoko
func credit(principal : Principal, amount : Nat) : ()
```

 add amount to P’s usable balance (the credit is created out of thin air)


### Function `balance`
``` motoko
func balance(principal : Principal) : Nat
```

query the usable balance


### Function `info`
``` motoko
func info(principal : Principal) : TrackingInfo and { usable_balance : Nat }
```

query all tracked balances for debug purposes


### Function `processConsolidationBacklog`
``` motoko
func processConsolidationBacklog() : async ()
```

process first account, which was failed to consolidate last time


### Function `share`
``` motoko
func share() : [(Principal, TrackingInfo)]
```

serialize tracking data


### Function `unshare`
``` motoko
func unshare(values : [(Principal, TrackingInfo)])
```

deserialize tracking data


### Function `toSubaccount`
``` motoko
func toSubaccount(principal : Principal) : ICRC1Interface.Subaccount
```

Convert Principal to ICRC1Interface.Subaccount


### Function `toPrincipal`
``` motoko
func toPrincipal(subaccount : ICRC1Interface.Subaccount) : Principal
```

Convert ICRC1Interface.Subaccount to Principal
