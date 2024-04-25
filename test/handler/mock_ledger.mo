module {

  type Account = { owner : Principal; subaccount : ?Subaccount };
  type Subaccount = Blob;
  type TransferArgs = {
    from_subaccount : ?Subaccount;
    to : Account;
    amount : Nat;
    fee : ?Nat;
    memo : ?Blob;
    created_at_time : ?Nat64;
  };
  type TransferError = {
    #BadFee : { expected_fee : Nat };
    #BadBurn : { min_burn_amount : Nat };
    #InsufficientFunds : { balance : Nat };
    #TooOld;
    #CreatedInFuture : { ledger_time : Nat64 };
    #Duplicate : { duplicate_of : Nat };
    #TemporarilyUnavailable;
    #GenericError : { error_code : Nat; message : Text };
  };
  type TransferResponse = {
    #Ok : Nat;
    #Err : TransferError;
  };

  public actor class MockLedger() {
    var fee : Nat = 0;
    var balance : Nat = 0;
    var balance_lock : Bool = false;
    var response : TransferResponse = #Ok 42;
    var transfer_lock : Bool = false;
    var transfer_count_ : Nat = 0;

    public query func icrc1_fee() : async Nat { fee };
    public func set_fee(x : Nat) : async () { fee := x };

    public func icrc1_balance_of(_ : Account) : async Nat {
      var inc : Nat = 0;
      // inc - workaround for the case when
      // background process is still running
      // and blocking the execution of the script
      // after an assertion failure
      while (balance_lock and inc < 100) {
        await async {};
        inc += 1;
      };
      balance;
    };
    public func set_balance(x : Nat) : async () { balance := x };
    public func lock_balance() : async () { balance_lock := true };
    public func release_balance() : async () { balance_lock := false };

    public func icrc1_transfer(_ : TransferArgs) : async TransferResponse {
      var inc : Nat = 0;
      while (transfer_lock and inc < 100) {
        await async {};
        inc += 1;
      };
      transfer_count_ += 1;
      response;
    };
    public func lock_transfer() : async () { transfer_lock := true };
    public func release_transfer() : async () { transfer_lock := false };
    public func set_response(r : TransferResponse) : async () { response := r };
    public func transfer_count() : async Nat { transfer_count_ };
  };

};
