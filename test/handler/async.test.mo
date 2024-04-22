import Principal "mo:base/Principal";
import { print } "mo:base/Debug";
import TokenHandler "../../src/TokenHandler";

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

actor class MockLedger() { 
  var fee : Nat = 0;
  var balance : Nat = 0;
  var balance_lock : Bool = false;
  var response : TransferResponse = #Ok 42;

  public query func icrc1_fee() : async Nat { fee };
  public func set_fee(x : Nat) : async () { fee := x };

  public func icrc1_balance_of(_ : Account) : async Nat { 
    while (balance_lock) {
      await async {}
    };
    balance
  };

  public func set_balance(x : Nat) : async () { balance := x };
  public func release_balance() : async () { balance_lock := false };
  public func lock_balance() : async () { balance_lock := true };

  public func icrc1_transfer(_ : TransferArgs) : async TransferResponse { response };
  public func set_response(r : TransferResponse) : async () { response := r };
};

await async {};

let ledger = await MockLedger();
let anon_p = Principal.fromBlob("");
let handler = TokenHandler.TokenHandler(Principal.fromActor(ledger), anon_p, 1000, 0);

let user1 = Principal.fromBlob("1");

func assert_state(x : (Nat, Nat, Nat)) {
  assert handler.depositedFunds() == x.0;
  assert handler.consolidatedFunds() == x.1;
  assert handler.depositsNumber() == x.2;
};

func state() {
  print(debug_show (handler.depositedFunds(),
  handler.consolidatedFunds(),
  handler.depositsNumber()));
};

do {
  var journalCtr = 0;
  func inc(n : Nat) : Nat { journalCtr += n; journalCtr };

  // init state 
  assert handler.fee() == 0;
  assert handler.journalLength() == 0;
  // update fee first time
  await ledger.set_fee(5);
  ignore await* handler.updateFee();
  assert handler.fee() == 5;
  assert handler.journalLength() == inc(1); // #feeUpdated
  // notify with 0 balance
  assert (await* handler.notify(user1)) == ?(0,0);
  assert_state(0,0,0);
  assert handler.journalLength() == inc(0);
  print("tree lookups = " # debug_show handler.lookups());
  // notify with balance <= fee
  await ledger.set_balance(5);
  assert (await* handler.notify(user1)) == ?(0,0);
  assert_state(0,0,0);
  assert handler.journalLength() == inc(0);
  print("tree lookups = " # debug_show handler.lookups());
  // notify with balance > fee
  await ledger.set_balance(6);
  assert (await* handler.notify(user1)) == ?(6,1); // deposit = 6, credit = 1
  assert_state(6,0,1);
  assert handler.journalLength() == inc(2); // #newDeposit, #credited
  print("tree lookups = " # debug_show handler.lookups());
  // increase fee while item still in queue (trigger did not run yet)
  await ledger.set_fee(6);
  ignore await* handler.updateFee();
  assert_state(0,0,0);
  assert handler.journalLength() == inc(2); // #feeUpdated, #debited
  print("tree lookups = " # debug_show handler.lookups());
  // increase deposit again
  await ledger.set_balance(7);
  assert (await* handler.notify(user1)) == ?(7,1); // deposit = 7, credit = 1
  assert_state(7,0,1);
  assert handler.journalLength() == inc(2); // #newDeposit, #credited
  // increase fee while notify is underway (and item still in queue)
  // scenario 1: old_fee < previous = latest <= new_fee
  // this means no new deposit has happened (latest = previous) 
  await ledger.lock_balance();
  let f = async { await* handler.notify(user1) }; // would return ?(0,1) at old fee
  await ledger.set_fee(10);
  ignore await* handler.updateFee();
  assert handler.journalLength() == inc(1); // #feeUpdated, not #debited because user1 is locked
  assert_state(7,0,1); // state still unchanged
  await ledger.release_balance(); // let notify return
  assert (await f) == ?(0,0); // deposit <= fee
  assert_state(0,0,0); // state has changed
  assert handler.journalLength() == inc(1); // #debited
  // increase fee while notify is underway (and item still in queue)
  // scenario 2: old_fee < previous <= new_fee < latest
  await ledger.set_balance(20);
  await ledger.lock_balance();
  let f = async { await* handler.notify(user1) }; // would return ?(0,1) at old fee
  await ledger.set_fee(10);
  ignore await* handler.updateFee();
  assert handler.journalLength() == inc(1); // #feeUpdated, not #debited because user1 is locked
  assert_state(7,0,1); // state still unchanged
  await ledger.release_balance(); // let notify return
  assert (await f) == ?(13,10); // credit = latest - new_fee
  assert_state(20,0,1); // state should have changed
  assert handler.journalLength() == inc(2); // #newDeposit, #credited
};
