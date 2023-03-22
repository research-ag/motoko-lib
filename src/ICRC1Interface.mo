// https://github.com/dfinity/ICRC-1/blob/main/standards/ICRC-1/README.md

module {
  public type Subaccount = Blob;
  public type Account = { owner : Principal; subaccount : ?Subaccount };
  public type TransferArgs = {
    from_subaccount : ?Subaccount;
    to : Account;
    amount : Nat;
    fee : ?Nat;
    memo : ?Blob;
    created_at_time : ?Nat64;
  };
  public type TransferError = {
    #BadFee : { expected_fee : Nat };
    #BadBurn : { min_burn_amount : Nat };
    #InsufficientFunds : { balance : Nat };
    #TooOld;
    #CreatedInFuture : { ledger_time : Nat64 };
    #Duplicate : { duplicate_of : Nat };
    #TemporarilyUnavailable;
    #GenericError : { error_code : Nat; message : Text };
  };
  public type Icrc1LedgerInterface = actor {
    icrc1_balance_of : (Account) -> async (Nat);
    icrc1_transfer : (TransferArgs) -> async ({
      #Ok : Nat;
      #Err : TransferError;
    });
  };
};