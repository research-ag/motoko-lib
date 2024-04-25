import Principal "mo:base/Principal";
import { print } "mo:base/Debug";

import TokenHandler "../../src/TokenHandler";
import { MockLedger } "mock_ledger";

let ledger = await MockLedger();
let anon_p = Principal.fromBlob("");
let handler = TokenHandler.TokenHandler(Principal.fromActor(ledger), anon_p, 1000, 0);

let user1 = Principal.fromBlob("1");

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
  public func journal() {
    print(
      debug_show (
        handler.queryJournal(?0)
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
assert_state(7, 0, 1); // state from before
ignore await* handler.updateFee();
assert handler.journalLength() == inc(2); // #feeUpdated, #debited
assert_state(0, 0, 0); // state changed
await ledger.release_balance(); // let notify return
assert (await f1) == ?(0, 0); // deposit <= new fee
assert_state(0, 0, 0); // state has not changed
assert handler.journalLength() == inc(0);
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
assert_state(15, 0, 1); // state from before
ignore await* handler.updateFee();
assert handler.journalLength() == inc(2); // #feeUpdated, #debited
assert_state(0, 0, 0); // state changed
await ledger.release_balance(); // let notify return
assert (await f2) == ?(20, 5); // credit = latest - new_fee
assert_state(20, 0, 1); // state should have changed
assert handler.journalLength() == inc(2); // #newDeposit, #credited
print("tree lookups = " # debug_show handler.lookups());

// call multiple notify() simultaneously
await ledger.lock_balance();
let arr = [async { await* handler.notify(user1) }, async { await* handler.notify(user1) }, async { await* handler.notify(user1) }];
await ledger.release_balance(); // let notify return
assert (await arr[0]) == ?(0, 5); // first notify() should return state
assert (await arr[1]) == null; // should return null
assert (await arr[2]) == null; // should return null
assert_state(20, 0, 1); // state unchanged because deposit has not changed
assert handler.journalLength() == inc(0);
print("tree lookups = " # debug_show handler.lookups());

// only 1 consolidation process can be triggered for same user at same time
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
await ledger.set_response(#Err(#BadFee { expected_fee = 25 }));
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
await ledger.set_response(#Err(#BadFee { expected_fee = 26 }));
await ledger.release_transfer(); // let transfer return
await f6;
assert_state(35, 5, 1); // consolidation failed with updated deposit scheduled
assert handler.journalLength() == inc(4); // #consolidationError, #debited, #feeUpdated, #credited
assert (await* handler.notify(user1)) == ?(0, 14); // credit corrected after consolidation
assert handler.journalLength() == inc(0);
print("tree lookups = " # debug_show handler.lookups());
