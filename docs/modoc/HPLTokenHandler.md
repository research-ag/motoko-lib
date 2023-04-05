# HPLTokenHandler

## Value `HPL`
``` motoko
let HPL
```


## Function `defaultHandlerStableData`
``` motoko
func defaultHandlerStableData() : StableData
```


## Type `TrackedCredit`
``` motoko
type TrackedCredit = Int
```


## Type `JournalRecord`
``` motoko
type JournalRecord = (Time.Time, Principal, {#newDeposit : Nat; #consolidated : { deducted : Nat; credited : Nat }; #debited : Nat; #credited : Nat; #feeUpdated : { old : Nat; new : Nat }; #error : Text; #consolidationError : Any; #withdraw : Any})
```


## Type `StableData`
``` motoko
type StableData = ([(Principal, TrackedCredit)], (Nat, [(Principal, Nat)]), Nat, (Nat, Nat), ([var ?JournalRecord], Nat, Int))
```


## Class `HPLTokenHandler`

``` motoko
class HPLTokenHandler(icrc1LedgerPrincipal : Principal, ownPrincipal : Principal, journalSize : Nat)
```


### Function `getFee`
``` motoko
func getFee() : Nat
```

query the fee


### Function `balance`
``` motoko
func balance(p : Principal) : Nat
```

query the usable balance


### Function `info`
``` motoko
func info(p : Principal) : TrackedCredit
```

query all tracked balances for debug purposes


### Function `queryJournal`
``` motoko
func queryJournal(startFrom : ?Nat) : ([JournalRecord], Nat)
```

query journal for debug purposes. Returns:
1) array of all items in order, starting from the oldest record in journal, but no earlier than "startFrom" if provided
2) the index of next upcoming journal log. Use this value as "startFrom" in your next journal query to fetch next entries


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

send tokens to another account
serialize tracking data


### Function `unshare`
``` motoko
func unshare(values : StableData)
```

deserialize tracking data
