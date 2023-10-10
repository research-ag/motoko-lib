# HPLTokenHandler

## Module `HPL`

``` motoko
module HPL
```


### Type `AssetId`
``` motoko
type AssetId = Nat
```



### Type `SubaccountId`
``` motoko
type SubaccountId = Nat
```



### Type `VirtualAccountId`
``` motoko
type VirtualAccountId = Nat
```



### Type `Asset`
``` motoko
type Asset = (id : AssetId, quantity : Nat)
```



### Type `Expiration`
``` motoko
type Expiration = {#None; #Timestamp : Nat64}
```



### Type `VirtualAccountState`
``` motoko
type VirtualAccountState = { asset : Asset; backingSubaccountId : SubaccountId; remotePrincipal : Principal; expiration : Expiration }
```



### Type `BalanceUpdate`
``` motoko
type BalanceUpdate = {#Set : Nat; #Increment : Nat; #Decrement : Nat}
```



### Type `VirtualAccountUpdateObject`
``` motoko
type VirtualAccountUpdateObject = { backingSubaccountId : ?SubaccountId; balance : ?BalanceUpdate; expiration : ?Expiration }
```



### Type `TxWithMemos`
``` motoko
type TxWithMemos = { memo : [Blob] }
```



### Type `TxInputV1`
``` motoko
type TxInputV1 = TxWithMemos and { map : [ContributionInput] }
```



### Type `TxInput`
``` motoko
type TxInput = {#v1 : TxInputV1}
```



### Type `AccountReference`
``` motoko
type AccountReference = {#sub : SubaccountId; #vir : (Principal, VirtualAccountId)}
```



### Type `ContributionInput`
``` motoko
type ContributionInput = ContributionBody and { owner : ?Principal }
```



### Type `GlobalId`
``` motoko
type GlobalId = (streamId : Nat, queueNumber : Nat)
```



### Type `ProcessingError`
``` motoko
type ProcessingError = {#TooLargeAssetId; #TooLargeFtQuantity; #TooLargeSubaccountId; #TooLargeVirtualAccountId; #TooLargeMemo; #TooManyFlows; #TooManyContributions; #NonZeroAssetSum; #UnknownPrincipal; #UnknownSubaccount; #UnknownVirtualAccount; #DeletedVirtualAccount; #UnknownFtAsset; #MismatchInAsset; #MismatchInRemotePrincipal; #InsufficientFunds; #NotAController}
```



### Type `SubmitAndExecuteError`
``` motoko
type SubmitAndExecuteError = ProcessingError or {#NotApproved}
```



### Type `Ledger`
``` motoko
type Ledger = actor { openVirtualAccount : shared (state : VirtualAccountState) -> async R.Result<VirtualAccountId, ?{#UnknownPrincipal; #UnknownSubaccount; #MismatchInAsset; #NoSpaceForAccount; #InvalidExpirationTime}>; updateVirtualAccount : shared (vid : VirtualAccountId, updates : VirtualAccountUpdateObject) -> async R.Result<{ balance : Nat; delta : Int }, ?{#UnknownPrincipal; #UnknownVirtualAccount; #DeletedVirtualAccount; #UnknownSubaccount; #MismatchInAsset; #InsufficientFunds; #InvalidExpirationTime}>; virtualAccount : shared (vid : VirtualAccountId) -> async R.Result<VirtualAccountState, ?{#UnknownPrincipal; #UnknownVirtualAccount; #DeletedVirtualAccount}>; submitAndExecute : shared (tx : TxInput) -> async R.Result<(GlobalId, {#ftTransfer : { amount : Nat; fee : Nat }}), ?SubmitAndExecuteError> }
```


## Function `defaultHandlerStableData`
``` motoko
func defaultHandlerStableData() : StableData
```


## Type `Info`
``` motoko
type Info = { var credit : Nat; var virtualAccountId : ?HPL.VirtualAccountId }
```


## Type `StableInfo`
``` motoko
type StableInfo = { credit : Nat; virtualAccountId : ?HPL.VirtualAccountId }
```


## Type `JournalRecord`
``` motoko
type JournalRecord = (Time.Time, Principal, {#credited : Nat; #debited : Nat; #error : Any; #openAccountError : {#UnknownPrincipal; #UnknownSubaccount; #MismatchInAsset; #NoSpaceForAccount}; #sweepIn : Nat; #sweepOut : Nat; #withdraw : { to : (Principal, HPL.VirtualAccountId); amount : Nat }; #deposit : { from : (Principal, HPL.VirtualAccountId); amount : Nat }})
```


## Type `StableData`
``` motoko
type StableData = ([(Principal, StableInfo)], Nat, (Nat, Nat), ([var ?JournalRecord], Nat, Int))
```


## Class `TokenHandler`

``` motoko
class TokenHandler(hplLedgerPrincipal : Principal, assetId : HPL.AssetId, backingSubaccountId : HPL.SubaccountId, ownPrincipal : Principal, journalSize : Nat)
```


### Function `getAccountReferenceFor`
``` motoko
func getAccountReferenceFor(p : Principal) : async* (Principal, HPL.VirtualAccountId)
```

Returns reference to registered virtual account for P.
If not registered yet, registers it automatically
We pass through any call Error instead of catching it


### Function `balance`
``` motoko
func balance(p : Principal) : ?Nat
```

query the usable balance


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


### Function `sweepIn`
``` motoko
func sweepIn(p : Principal) : async* ?(Nat, Nat)
```

The handler will turn the balance of virtual account, previously opened for P, to zero.
If there was non-zero amount (deposit), the handler will add the deposit to the credit of P.
Returns the newly detected deposit and total usable balance if success, otherwise null
We pass through any call Error instead of catching it


### Function `sweepOut`
``` motoko
func sweepOut(p : Principal) : async* ?Nat
```

The handler will increment the balance of virtual account, previously opened for P, with user credit.
Returns total usable balance if success (available balance in the virtual account), otherwise null
We pass through any call Error instead of catching it


### Function `deposit`
``` motoko
func deposit(from : (Principal, HPL.VirtualAccountId), amount : Nat) : async* ()
```

receive tokens from user's virtual account, where remotePrincipal == ownPrincipal
We pass through any call Error instead of catching it


### Function `withdraw`
``` motoko
func withdraw(to : (Principal, HPL.VirtualAccountId), withdrawAmount : {#amount : Nat; #max}) : async* ()
```

send tokens to another account
"to" virtual account has to be opened by user, and handler principal has to be set as remotePrincipal in it
We pass through any call Error instead of catching it


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
