# ICRC1Interface

## Type `Subaccount`
``` motoko
type Subaccount = Blob
```


## Type `Account`
``` motoko
type Account = { owner : Principal; subaccount : ?Subaccount }
```


## Type `TransferArgs`
``` motoko
type TransferArgs = { from_subaccount : ?Subaccount; to : Account; amount : Nat; fee : ?Nat; memo : ?Blob; created_at_time : ?Nat64 }
```


## Type `TransferError`
``` motoko
type TransferError = {#BadFee : { expected_fee : Nat }; #BadBurn : { min_burn_amount : Nat }; #InsufficientFunds : { balance : Nat }; #TooOld; #CreatedInFuture : { ledger_time : Nat64 }; #Duplicate : { duplicate_of : Nat }; #TemporarilyUnavailable; #GenericError : { error_code : Nat; message : Text }}
```


## Type `Icrc1LedgerInterface`
``` motoko
type Icrc1LedgerInterface = actor { icrc1_balance_of : shared (Account) -> async (Nat); icrc1_transfer : shared (TransferArgs) -> async ({#Ok : Nat; #Err : TransferError}) }
```

