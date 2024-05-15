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

  public type TransferResult = {
    #Ok : Nat;
    #Err : TransferError;
  };

  public type AllowanceArgs = {
    account : Account;
    spender : Account;
  };

  public type AllowanceResult = {
    allowance : Nat;
    expires_at : ?Nat64;
  };

  public type ICRC1Ledger = actor {
    icrc1_fee : () -> async (Nat);
    // We do not declare icrc1_balance_of as query.
    // TODO: Is this ok to leave it like that?
    icrc1_balance_of : (Account) -> async (Nat);
    icrc1_transfer : (TransferArgs) -> async (TransferResult);
    icrc2_allowance : (AllowanceArgs) -> async (AllowanceResult);
    whoAmI : () -> async ();
  };

  public type LedgerAPI = {
    fee : shared () -> async Nat;
    balance_of : shared Account -> async Nat;
    transfer : shared TransferArgs -> async TransferResult;
    allowance : shared (AllowanceArgs) -> async (AllowanceResult);
    //    whoAmI : () -> async ();
  };
};
