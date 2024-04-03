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

  public type ICRC1Ledger = actor {
    icrc1_fee : query () -> async (Nat);
    icrc1_balance_of : query (Account) -> async (Nat);
    icrc1_transfer : (TransferArgs) -> async ({
      #Ok : Nat;
      #Err : TransferError;
    });
  };
};
