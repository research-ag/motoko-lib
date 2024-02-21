# TokenHandler

## Module `ICRC1`

``` motoko
module ICRC1
```


### Type `Subaccount`
``` motoko
type Subaccount = Blob
```



### Type `Account`
``` motoko
type Account = { owner : Principal; subaccount : ?Subaccount }
```



### Type `TransferArgs`
``` motoko
type TransferArgs = { from_subaccount : ?Subaccount; to : Account; amount : Nat; fee : ?Nat; memo : ?Blob; created_at_time : ?Nat64 }
```



### Type `TransferError`
``` motoko
type TransferError = {#BadFee : { expected_fee : Nat }; #BadBurn : { min_burn_amount : Nat }; #InsufficientFunds : { balance : Nat }; #TooOld; #CreatedInFuture : { ledger_time : Nat64 }; #Duplicate : { duplicate_of : Nat }; #TemporarilyUnavailable; #GenericError : { error_code : Nat; message : Text }}
```



### Type `ICRC1Ledger`
``` motoko
type ICRC1Ledger = actor { icrc1_balance_of : shared (Account) -> async (Nat); icrc1_transfer : shared (TransferArgs) -> async ({#Ok : Nat; #Err : TransferError}) }
```


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

## Function `defaultHandlerStableData`
``` motoko
func defaultHandlerStableData() : StableData
```


## Type `Info`
``` motoko
type Info = { var deposit : Nat; var credit : Int }
```


## Type `JournalRecord`
``` motoko
type JournalRecord = (Time.Time, Principal, {#newDeposit : Nat; #consolidated : { deducted : Nat; credited : Nat }; #debited : Nat; #credited : Nat; #feeUpdated : { old : Nat; new : Nat }; #error : Text; #consolidationError : ICRC1.TransferError or {#CallIcrc1LedgerError}; #withdraw : { to : ICRC1.Account; amount : Nat }})
```


## Type `StableData`
``` motoko
type StableData = ([(Principal, Info)], (Nat, [(Principal, Nat)]), Nat, Nat, (Nat, Nat), ([var ?JournalRecord], Nat, Nat))
```


## Class `TokenHandler`

``` motoko
class TokenHandler(icrc1LedgerPrincipal_ : Principal, ownPrincipal : Principal, journalSize : Nat)
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
func info(p : Principal) : Info and { var usable_balance : Nat }
```

query all tracked balances for debug purposes


### Function `queryJournal`
``` motoko
func queryJournal(startFrom : ?Nat) : ([JournalRecord], Nat)
```

query journal for debug purposes. Returns:
1) array of all items in order, starting from the oldest record in journal, but no earlier than "startFrom" if provided
2) the index of next upcoming journal log. Use this value as "startFrom" in your next journal query to fetch next entries


### Function `icrc1LedgerPrincipal`
``` motoko
func icrc1LedgerPrincipal() : Principal
```

retrieve the ICRC1 ledger principal


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


### Function `totalConsolidated`
``` motoko
func totalConsolidated() : Nat
```

retrieve the sum of all successful consolidations


### Function `backlogFunds`
``` motoko
func backlogFunds() : Nat
```

retrieve the estimated sum of all balances in the backlog


### Function `depositedFunds`
``` motoko
func depositedFunds() : Nat
```

retrieve the sum of all deposits. This value is nearly the same as backlogFunds(), but includes
entries, which could not be added to backlog, for instance when balance less than fee.
It's always >= backlogFunds()


### Function `creditedFunds`
``` motoko
func creditedFunds() : Int
```

retrieve the sum of all user credit balances.
It can be negative because user can spend deposited funds before consolidation


### Function `usableFunds`
``` motoko
func usableFunds() : Nat
```

retrieve the sum of all user usable balances. It's tricky to cache it
because of excluding deposits, smaller than fee, from the usable balance.


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
func processBacklog() : async ()
```

process first account from backlog


### Function `withdraw`
``` motoko
func withdraw(to : ICRC1.Account, amount : Nat) : async* Result.Result<(transactionIndex : Nat, withdrawnAmount : Nat), ICRC1.TransferError or {#CallIcrc1LedgerError; #TooLowQuantity}>
```

send tokens to another account, return ICRC1 transaction index and amount of transferred tokens (fee excluded)


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
