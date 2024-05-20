import Debug "mo:base/Debug";

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
  type TransferFromError = {
    #BadFee : { expected_fee : Nat };
    #BadBurn : { min_burn_amount : Nat };
    #InsufficientFunds : { balance : Nat };
    #InsufficientAllowance : { allowance : Nat };
    #CreatedInFuture : { ledger_time : Nat64 };
    #Duplicate : { duplicate_of : Nat };
    #TemporarilyUnavailable;
    #GenericError : { error_code : Nat; message : Text };
  };
  type TransferFromArgs = {
    spender_subaccount : ?Blob;
    from : Account;
    to : Account;
    amount : Nat;
    fee : ?Nat;
    memo : ?Blob;
    created_at_time : ?Nat64;
  };
  type TransferFromResult = {
    #Ok : Nat;
    #Err : TransferFromError;
  };

  public actor class MockLedger() {
    var fee : Nat = 0;
    var fee_lock : Bool = false;
    var fee_lock_key : Text = "";
    var balance : Nat = 0;
    var balance_lock : Bool = false;
    var balance_lock_key : Text = "";
    var response : [TransferResponse] = [#Ok 42];
    var transfer_lock : Bool = false;
    var transfer_lock_key : Text = "";
    var transfer_count_ : Nat = 0;
    var transfer_res_i_ : Nat = 0;

    var transfer_from_res : [TransferFromResult] = [#Ok 42];
    var transfer_from_lock : Bool = false;
    var transfer_from_lock_key : Text = "";
    var transfer_from_count_ : Nat = 0;
    var transfer_from_res_i_ : Nat = 0;

    public func reset_state() : async () {
      fee := 0;
      balance := 0;
      balance_lock := false;
      balance_lock_key := "";
      response := [#Ok 42];
      transfer_lock := false;
      transfer_lock_key := "";
      transfer_count_ := 0;
      transfer_res_i_ := 0;
    };

    // icrc1_fee

    public func icrc1_fee() : async Nat {
      var inc : Nat = 0;
      while (fee_lock and inc < 100) {
        await async {};
        inc += 1;
      };
      if (inc == 100) {
        Debug.print("lock key: " # fee_lock_key);
        assert false;
      };
      fee;
    };
    public func set_fee(x : Nat) : async () { fee := x };
    public func lock_fee(key : Text) : async () {
      fee_lock := true;
      fee_lock_key := key;
    };
    public func release_fee() : async () {
      fee_lock := false;
      fee_lock_key := "";
    };

    // icrc1_balance_of

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
      if (inc == 100) {
        Debug.print("lock key: " # balance_lock_key);
        assert false;
      };
      balance;
    };
    public func set_balance(x : Nat) : async () { balance := x };
    public func lock_balance(key : Text) : async () {
      balance_lock := true;
      balance_lock_key := key;
    };
    public func release_balance() : async () {
      balance_lock := false;
      balance_lock_key := "";
    };

    // icrc1_transfer

    public func icrc1_transfer(_ : TransferArgs) : async TransferResponse {
      var inc : Nat = 0;
      while (transfer_lock and inc < 100) {
        await async {};
        inc += 1;
      };
      if (inc == 100) {
        Debug.print("lock key: " # transfer_lock_key);
        assert false;
      };
      transfer_count_ += 1;
      let res = response[transfer_res_i_];
      transfer_res_i_ := (transfer_res_i_ + 1) % response.size();
      res;
    };
    public func lock_transfer(key : Text) : async () {
      transfer_lock := true;
      transfer_lock_key := key;
    };
    public func release_transfer() : async () {
      transfer_lock := false;
      transfer_lock_key := "";
    };
    public func set_response(r : [TransferResponse]) : async () {
      response := r;
      transfer_res_i_ := 0;
    };
    public func transfer_count() : async Nat { transfer_count_ };

    // icrc2_transfer_from

    public func icrc2_transfer_from(_ : TransferFromArgs) : async (TransferFromResult) {
      var inc : Nat = 0;
      while (transfer_from_lock and inc < 100) {
        await async {};
        inc += 1;
      };
      if (inc == 100) {
        Debug.print("lock key: " # transfer_from_lock_key);
        assert false;
      };
      transfer_from_count_ += 1;
      let res = transfer_from_res[transfer_from_res_i_];
      transfer_from_res_i_ := (transfer_from_res_i_ + 1) % transfer_from_res.size();
      res;
    };
    public func lock_transfer_from(key : Text) : async () {
      transfer_from_lock := true;
      transfer_from_lock_key := key;
    };
    public func release_transfer_from() : async () {
      transfer_from_lock := false;
      transfer_from_lock_key := "";
    };
    public func set_transfer_from_res(r : [TransferFromResult]) : async () {
      transfer_from_res := r;
      transfer_from_res_i_ := 0;
    };
    public func transfer_from_count() : async Nat { transfer_from_count_ };
  };

};
