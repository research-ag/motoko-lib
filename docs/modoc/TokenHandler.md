# TokenHandler

## Type `StableTrackingInfo`
``` motoko
type StableTrackingInfo = { deposit_balance : Nat; credit_balance : Int }
```


## Type `Icrc1LedgerInterface`
``` motoko
type Icrc1LedgerInterface = Icrc1Interface.Icrc1LedgerInterface
```


## Class `TokenHandler`

``` motoko
class TokenHandler(icrc1LedgerPrincipal : Principal, ownPrincipal : Principal)
```


### Function `notify`
``` motoko
func notify(p : Principal) : async* ()
```

The handler will call icrc1_balance(S:P) to query the balance. It will detect if it has increased compared
to the last balance seen. If it has increased then it will adjust the deposit_balance (and hence the usable_balance).
It will also schedule or trigger a “consolidation”, i.e. moving the newly deposited funds from S:P to S:0.
Note: concurrent notify() for the same P have to be handled with locks.


### Function `debit`
``` motoko
func debit(p : Principal, amount : Nat) : Bool
```

deduct amount from P’s usable balance. Return false if the balance is insufficient.


### Function `credit`
``` motoko
func credit(p : Principal, amount : Nat) : ()
```

 add amount to P’s usable balance (the credit is created out of thin air)


### Function `balance`
``` motoko
func balance(p : Principal) : Nat
```

query the usable balance


### Function `info`
``` motoko
func info(p : Principal) : StableTrackingInfo and { usable_balance : Nat }
```

query all tracked balances for debug purposes


### Function `processConsolidationBacklog`
``` motoko
func processConsolidationBacklog() : async ()
```

process first account, which was failed to consolidate last time


### Function `share`
``` motoko
func share() : [(Principal, StableTrackingInfo)]
```

serialize tracking data


### Function `unshare`
``` motoko
func unshare(values : [(Principal, StableTrackingInfo)])
```

deserialize tracking data


### Function `principalToSubaccount`
``` motoko
func principalToSubaccount(p : Principal) : Icrc1Interface.Subaccount
```



### Function `obtainTrackingInfoLock`
``` motoko
func obtainTrackingInfoLock(p : Principal) : Bool
```



### Function `releaseTrackingInfoLock`
``` motoko
func releaseTrackingInfoLock(p : Principal)
```

