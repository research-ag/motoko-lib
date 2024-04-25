import Principal "mo:base/Principal";
import { print } "mo:base/Debug";

import TokenHandler "../../src/TokenHandler";
import { MockLedger } "mock_ledger";

let ledger = await MockLedger();
let anon_p = Principal.fromBlob("");
let handler = TokenHandler.TokenHandler(Principal.fromActor(ledger), anon_p, 1000, 0);

let user1 = Principal.fromBlob("1");
let account = { owner = Principal.fromBlob("1"); subaccount = null };

func assert_state(x : (Nat, Nat, Nat)) {
  assert handler.depositedFunds() == x.0;
  assert handler.consolidatedFunds() == x.1;
  assert handler.depositsNumber() == x.2;
};

module Debug {
  public func state() {
    print(
      debug_show (
        handler.depositedFunds(),
        handler.consolidatedFunds(),
        handler.depositsNumber(),
      )
    );
  };
  public func journal(ctr : Nat) {
    print(
      debug_show (
        handler.queryJournal(?ctr)
      )
    );
  };
};

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
assert (await* handler.notify(user1)) == ?(0, 0);
assert_state(0, 0, 0);
assert handler.journalLength() == inc(0);
print("tree lookups = " # debug_show handler.lookups());

// notify with balance <= fee
await ledger.set_balance(5);
assert (await* handler.notify(user1)) == ?(0, 0);
assert_state(0, 0, 0);
assert handler.journalLength() == inc(0);
print("tree lookups = " # debug_show handler.lookups());

// notify with balance > fee
await ledger.set_balance(6);
assert (await* handler.notify(user1)) == ?(6, 1); // deposit = 6, credit = 1
assert_state(6, 0, 1);
assert handler.journalLength() == inc(2); // #newDeposit, #credited
print("tree lookups = " # debug_show handler.lookups());

// increase fee while item still in queue (trigger did not run yet)
await ledger.set_fee(6);
ignore await* handler.updateFee();
assert_state(0, 0, 0); // recalculation after fee update
assert handler.journalLength() == inc(2); // #feeUpdated, #debited
print("tree lookups = " # debug_show handler.lookups());

// increase deposit again
await ledger.set_balance(7);
assert (await* handler.notify(user1)) == ?(7, 1); // deposit = 7, credit = 1
assert_state(7, 0, 1);
assert handler.journalLength() == inc(2); // #newDeposit, #credited
print("tree lookups = " # debug_show handler.lookups());

// increase fee while notify is underway (and item still in queue)
// scenario 1: old_fee < previous = latest <= new_fee
// this means no new deposit has happened (latest = previous)
await ledger.lock_balance();
let f1 = async { await* handler.notify(user1) }; // would return ?(0,1) at old fee
await ledger.set_fee(10);
ignore await* handler.updateFee();
assert handler.journalLength() == inc(1); // #feeUpdated, not #debited because user1 is locked
assert_state(7, 0, 1); // state still unchanged
await ledger.release_balance(); // let notify return
assert (await f1) == ?(0, 0); // deposit <= new fee
assert_state(0, 0, 0); // state has changed
assert handler.journalLength() == inc(1); // #debited
print("tree lookups = " # debug_show handler.lookups());

// increase deposit again
await ledger.set_balance(15);
assert (await* handler.notify(user1)) == ?(15, 5); // deposit = 15, credit = 5
assert_state(15, 0, 1);
assert handler.journalLength() == inc(2); // #newDeposit, #credited
print("tree lookups = " # debug_show handler.lookups());

// increase fee while notify is underway (and item still in queue)
// scenario 2: old_fee < previous <= new_fee < latest
await ledger.set_balance(20);
await ledger.lock_balance();
let f2 = async { await* handler.notify(user1) }; // would return ?(5,10) at old fee
await ledger.set_fee(15);
ignore await* handler.updateFee();
assert handler.journalLength() == inc(1); // #feeUpdated, not #debited because user1 is locked
assert_state(15, 0, 1); // state still unchanged
await ledger.release_balance(); // let notify return
assert (await f2) == ?(20, 5); // credit = latest - new_fee
assert_state(20, 0, 1); // state should have changed
assert handler.journalLength() == inc(3); // #debited (recalculation), #newDeposit, #credited
print("tree lookups = " # debug_show handler.lookups());

// call multiple notify() simultaneously
// only the first should return state, the rest should not be executed
await ledger.lock_balance();
let arr = [async { await* handler.notify(user1) }, async { await* handler.notify(user1) }, async { await* handler.notify(user1) }];
assert (await arr[1]) == null; // should return null
assert (await arr[2]) == null; // should return null
await ledger.release_balance(); // let notify return
assert (await arr[0]) == ?(0, 5); // first notify() should return state
assert_state(20, 0, 1); // state unchanged because deposit has not changed
assert handler.journalLength() == inc(0);
print("tree lookups = " # debug_show handler.lookups());

// only 1 consolidation process can be triggered for same user at same time
// consolidation with deposit > fee should be successful
var transfer_count = await ledger.transfer_count();
let f3 = async { await* handler.trigger() };
let f4 = async { await* handler.trigger() };
await f3;
await f4;
assert ((await ledger.transfer_count())) == transfer_count + 1; // only 1 transfer call has been made
assert_state(0, 5, 0); // consolidation successful
assert handler.journalLength() == inc(1); // #consolidated
print("tree lookups = " # debug_show handler.lookups());

// increase fee while deposit is being consolidated
// scenario 1: old_fee < deposit < new_fee
// consolidation should fail and deposit should be reset
await ledger.set_balance(20);
assert (await* handler.notify(user1)) == ?(20, 10); // deposit = 20, credit = 10
assert handler.journalLength() == inc(2); // #credited, #newDeposit
assert_state(20, 5, 1);
await ledger.lock_transfer();
let f5 = async { await* handler.trigger() };
await ledger.set_fee(25);
await ledger.set_response([#Err(#BadFee { expected_fee = 25 })]);
await ledger.release_transfer(); // let transfer return
await f5;
assert_state(0, 5, 0); // consolidation failed
assert handler.journalLength() == inc(3); // #consolidationError, #debited, #feeUpdated
print("tree lookups = " # debug_show handler.lookups());

// increase fee while deposit is being consolidated
// scenario 2: old_fee < new_fee < deposit
// consolidation should fail and deposit should be adjusted with new fee
await ledger.set_balance(35);
assert (await* handler.notify(user1)) == ?(35, 15); // deposit = 35, credit = 15
assert handler.journalLength() == inc(2); // #credited, #newDeposit
assert_state(35, 5, 1);
await ledger.lock_transfer();
let f6 = async { await* handler.trigger() };
await ledger.set_fee(26);
await ledger.set_response([#Err(#BadFee { expected_fee = 26 })]);
await ledger.release_transfer(); // let transfer return
await f6;
assert_state(35, 5, 1); // consolidation failed with updated deposit scheduled
assert handler.journalLength() == inc(4); // #consolidationError, #debited, #feeUpdated, #credited
assert (await* handler.notify(user1)) == ?(0, 14); // credit corrected after consolidation
assert handler.journalLength() == inc(0);
print("tree lookups = " # debug_show handler.lookups());

// trigger consolidation again
await ledger.set_response([#Ok 42]);
await* handler.trigger();
assert_state(0, 14, 0); // consolidation successful
assert handler.journalLength() == inc(1); // #consolidated
print("tree lookups = " # debug_show handler.lookups());

// withdraw (fee < amount < consolidated_funds)
// should be successful
await ledger.set_fee(1);
ignore await* handler.updateFee();
assert handler.journalLength() == inc(1); // #feeUpdated
await ledger.set_response([#Ok 42]);
assert (await* handler.withdraw(account, 5)) == #ok(42, 4);
assert handler.journalLength() == inc(1); // #withdraw
ignore handler.debitStrict(user1, 5);
assert_state(0, 9, 0);
assert handler.journalLength() == inc(1); // #debited

// withdraw (amount <= fee_)
transfer_count := await ledger.transfer_count();
await ledger.set_response([#Ok 42]); // transfer call should not be executed anyway
assert (await* handler.withdraw(account, 1)) == #err(#TooLowQuantity);
assert (await ledger.transfer_count()) == transfer_count; // no transfer call
assert_state(0, 9, 0); // state unchanged
assert handler.journalLength() == inc(1); // #withdrawError

// withdraw (consolidated_funds < amount - fee)
await ledger.set_response([#Err(#InsufficientFunds({ balance = 9 }))]);
assert (await* handler.withdraw(account, 15)) == #err(#InsufficientFunds({ balance = 9 }));
assert_state(0, 9, 0); // state unchanged
assert handler.journalLength() == inc(1); // #withdrawError

// increase fee while withdraw is being consolidated
// scenario 1: old_fee < new_fee < amount
// withdraw should fail and then retry successfully, fee should be updated
await ledger.lock_transfer();
transfer_count := await ledger.transfer_count();
let fn7 = async { await* handler.withdraw(account, 4) };
await ledger.set_fee(2);
await ledger.set_response([#Err(#BadFee { expected_fee = 2 }), #Ok 42]);
await ledger.release_transfer(); // let transfer return
assert (await fn7) == #ok(42, 2);
assert (await ledger.transfer_count()) == transfer_count + 2;
assert handler.journalLength() == inc(2); // #feeUpdated, #withdraw
ignore handler.debitStrict(user1, 4);
assert_state(0, 5, 0); // state has changed
assert handler.journalLength() == inc(1); // #debited

// increase fee while withdraw is being consolidated
// scenario 2: old_fee < amount <= new_fee
// withdraw should fail and then retry with failure, fee should be updated
// the second call should be avoided with comparison amount and fee
await ledger.lock_transfer();
transfer_count := await ledger.transfer_count();
let fn8 = async { await* handler.withdraw(account, 4) };
await ledger.set_fee(4);
await ledger.set_response([#Err(#BadFee { expected_fee = 4 }), #Ok 42]); // the second call should not be executed
await ledger.release_transfer(); // let transfer return
assert (await fn8) == #err(#TooLowQuantity);
assert (await ledger.transfer_count()) == transfer_count + 1; // the second transfer call is avoided
assert_state(0, 5, 0); // state unchanged
assert handler.journalLength() == inc(2); // #feeUpdated, #withdrawalError
