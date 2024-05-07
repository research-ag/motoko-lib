import Principal "mo:base/Principal";
import { print } "mo:base/Debug";
import TokenHandler "../../src/TokenHandler";
import MockLedger "mock_ledger";

type TestLedgerAPI = TokenHandler.LedgerAPI and { mock : MockLedger.MockLedger };

let mock_ledger : MockLedger.MockLedger = await MockLedger.MockLedger();

let ledger : TestLedgerAPI = {
  fee = mock_ledger.icrc1_fee;
  balance_of = mock_ledger.icrc1_balance_of;
  transfer = mock_ledger.icrc1_transfer;
  mock = mock_ledger; // mock ledger for controlling responses
};

let anon_p = Principal.fromBlob("");
let user1 = Principal.fromBlob("1");
let account = { owner = Principal.fromBlob("1"); subaccount = null };

func create_inc() : (Nat -> Nat, () -> Nat) {
  var ctr = 0;
  func inc(n : Nat) : Nat { ctr += n; ctr };
  (inc, func() { ctr });
};

func state(handler : TokenHandler.TokenHandler) : (Nat, Nat, Nat) {
  let s = handler.state();
  (
    s.balance.deposited,
    s.balance.consolidated,
    s.users.queued,
  );
};

module Debug {
  public func state(handler : TokenHandler.TokenHandler) {
    print(
      debug_show handler.state()
    );
  };
  public func journal(handler : TokenHandler.TokenHandler, ctr : Nat) {
    print(
      debug_show (
        handler.queryJournal(?ctr)
      )
    );
  };
};

do {
  let handler = TokenHandler.TokenHandler(ledger, anon_p, 1000, 0);
  await ledger.mock.reset_state();
  let (inc, _) = create_inc();

  // init state
  assert handler.fee() == 0;
  assert handler.journalLength() == 0;

  // update fee first time
  await ledger.mock.set_fee(5);
  ignore await* handler.fetchFee();
  assert handler.fee() == 5;
  assert handler.journalLength() == inc(1); // #feeUpdated

  // notify with 0 balance
  await ledger.mock.set_balance(0);
  assert (await* handler.notify(user1)) == ?(0, 0);
  assert state(handler) == (0, 0, 0);
  assert handler.journalLength() == inc(0);
  print("tree lookups = " # debug_show handler.lookups());

  // notify with balance <= fee
  await ledger.mock.set_balance(5);
  assert (await* handler.notify(user1)) == ?(0, 0);
  assert state(handler) == (0, 0, 0);
  assert handler.journalLength() == inc(0);
  print("tree lookups = " # debug_show handler.lookups());

  // notify with balance > fee
  await ledger.mock.set_balance(6);
  assert (await* handler.notify(user1)) == ?(6, 1); // deposit = 6, credit = 1
  assert state(handler) == (6, 0, 1);
  assert handler.journalLength() == inc(2); // #newDeposit, #credited
  print("tree lookups = " # debug_show handler.lookups());

  // increase fee while item still in queue (trigger did not run yet)
  await ledger.mock.set_fee(6);
  ignore await* handler.fetchFee();
  assert state(handler) == (0, 0, 0); // recalculation after fee update
  assert handler.journalLength() == inc(2); // #feeUpdated, #debited
  print("tree lookups = " # debug_show handler.lookups());

  // increase deposit again
  await ledger.mock.set_balance(7);
  assert (await* handler.notify(user1)) == ?(7, 1); // deposit = 7, credit = 1
  assert state(handler) == (7, 0, 1);
  assert handler.journalLength() == inc(2); // #newDeposit, #credited
  print("tree lookups = " # debug_show handler.lookups());

  // increase fee while notify is underway (and item still in queue)
  // scenario 1: old_fee < previous = latest <= new_fee
  // this means no new deposit has happened (latest = previous)
  await ledger.mock.lock_balance("INCREASE_FEE_WHILE_NOTIFY_IS_UNDERWAY_SCENARIO_1");
  let f1 = async { await* handler.notify(user1) }; // would return ?(0, 1) at old fee
  await ledger.mock.set_fee(10); // fee 6 -> 10
  assert state(handler) == (7, 0, 1); // state from before
  ignore await* handler.fetchFee();
  assert handler.journalLength() == inc(2); // #feeUpdated, #debited
  assert state(handler) == (0, 0, 0); // state changed
  await ledger.mock.release_balance(); // let notify return
  assert (await f1) == ?(0, 0); // deposit <= new fee
  assert handler.journalLength() == inc(0);
  print("tree lookups = " # debug_show handler.lookups());

  // increase deposit again
  await ledger.mock.set_balance(15);
  assert (await* handler.notify(user1)) == ?(15, 5); // deposit = 15, credit = 5
  assert state(handler) == (15, 0, 1);
  assert handler.journalLength() == inc(2); // #newDeposit, #credited
  print("tree lookups = " # debug_show handler.lookups());

  // increase fee while notify is underway (and item still in queue)
  // scenario 2: old_fee < previous <= new_fee < latest
  await ledger.mock.set_balance(20);
  await ledger.mock.lock_balance("INCREASE_FEE_WHILE_NOTIFY_IS_UNDERWAY_SCENARIO_2");
  let f2 = async { await* handler.notify(user1) }; // would return ?(5, 10) at old fee
  await ledger.mock.set_fee(15); // fee 10 -> 15
  assert state(handler) == (15, 0, 1); // state from before
  ignore await* handler.fetchFee();
  assert handler.journalLength() == inc(2); // #feeUpdated, #debited
  assert state(handler) == (0, 0, 0); // state changed
  await ledger.mock.release_balance(); // let notify return
  assert (await f2) == ?(20, 5); // credit = latest - new_fee
  assert state(handler) == (20, 0, 1); // state should have changed
  assert handler.journalLength() == inc(2); // #newDeposit, #credited
  print("tree lookups = " # debug_show handler.lookups());

  // decrease fee while notify is underway (and item still in queue)
  // new_fee < old_fee < previous == latest
  await ledger.mock.lock_balance("DECREASE_FEE_WHILE_NOTIFY_IS_UNDERWAY");
  let f3 = async { await* handler.notify(user1) }; // would return ?(0, 5) at old fee
  await ledger.mock.set_fee(10); // fee 15 -> 10
  assert state(handler) == (20, 0, 1); // state from before
  ignore await* handler.fetchFee();
  assert handler.journalLength() == inc(2); // #feeUpdated, #credited
  assert state(handler) == (20, 0, 1); // state unchanged
  await ledger.mock.release_balance(); // let notify return
  assert (await f3) == ?(0, 10); // credit increased
  assert state(handler) == (20, 0, 1); // state unchanged
  print("tree lookups = " # debug_show handler.lookups());

  // call multiple notify() simultaneously
  // only the first should return state, the rest should not be executed
  await ledger.mock.lock_balance("CALL_MULTIPLE_NOTIFY_SIMULTANEOUSLY");
  let fut1 = async { await* handler.notify(user1) };
  let fut2 = async { await* handler.notify(user1) };
  let fut3 = async { await* handler.notify(user1) };
  assert (await fut2) == null; // should return null
  assert (await fut3) == null; // should return null
  await ledger.mock.release_balance(); // let notify return
  assert (await fut1) == ?(0, 10); // first notify() should return state
  assert state(handler) == (20, 0, 1); // state unchanged because deposit has not changed
  assert handler.journalLength() == inc(0);
  print("tree lookups = " # debug_show handler.lookups());

  handler.assertIntegrity();
  assert not handler.isFrozen();
};

do {
  let handler = TokenHandler.TokenHandler(ledger, anon_p, 1000, 0);
  await ledger.mock.reset_state();
  let (inc, _) = create_inc();

  // update fee first time
  await ledger.mock.set_fee(5);
  ignore await* handler.fetchFee();
  assert handler.fee() == 5;
  assert handler.journalLength() == inc(1); // #feeUpdated

  // increase fee while deposit is being consolidated (implicitly)
  // scenario 1: old_fee < deposit <= new_fee
  // consolidation should fail and deposit should be reset
  await ledger.mock.set_balance(10);
  assert (await* handler.notify(user1)) == ?(10, 5); // deposit = 10, credit = 5
  assert handler.journalLength() == inc(2); // #credited, #newDeposit
  assert state(handler) == (10, 0, 1);
  await ledger.mock.lock_transfer("IMP_INCREASE_FEE_WHILE_DEPOSIT_IS_BEING_CONSOLIDATED_SCENARIO_1");
  let f1 = async { await* handler.trigger() };
  await ledger.mock.set_fee(10);
  await ledger.mock.set_response([#Err(#BadFee { expected_fee = 10 })]);
  await ledger.mock.release_transfer(); // let transfer return
  await f1;
  assert state(handler) == (0, 0, 0); // consolidation failed with deposit reset
  assert handler.journalLength() == inc(3); // #consolidationError, #debited, #feeUpdated
  assert handler.getCredit(user1) == 0; // credit has been corrected after consolidation
  print("tree lookups = " # debug_show handler.lookups());

  // increase fee while deposit is being consolidated (implicitly)
  // scenario 2: old_fee < new_fee < deposit
  // consolidation should fail and deposit should be adjusted with new fee
  await ledger.mock.set_balance(20);
  assert (await* handler.notify(user1)) == ?(20, 10); // deposit = 20, credit = 10
  assert handler.journalLength() == inc(2); // #credited, #newDeposit
  assert state(handler) == (20, 0, 1);
  await ledger.mock.lock_transfer("IMP_INCREASE_FEE_WHILE_DEPOSIT_IS_BEING_CONSOLIDATED_SCENARIO_2");
  let f2 = async { await* handler.trigger() };
  await ledger.mock.set_fee(15);
  await ledger.mock.set_response([#Err(#BadFee { expected_fee = 15 })]);
  await ledger.mock.release_transfer(); // let transfer return
  await f2;
  assert state(handler) == (20, 0, 1); // consolidation failed with updated deposit scheduled
  assert handler.journalLength() == inc(4); // #consolidationError, #debited, #feeUpdated, #credited
  assert handler.getCredit(user1) == 5; // credit has been corrected after consolidation
  print("tree lookups = " # debug_show handler.lookups());

  // increase fee while deposit is being consolidated (explicitly)
  // scenario 1: old_fee < deposit <= new_fee
  // consolidation should fail and deposit should be reset
  assert (await* handler.notify(user1)) == ?(0, 5); // deposit diff = 0, credit = 5
  assert handler.journalLength() == inc(0);
  assert state(handler) == (20, 0, 1);
  await ledger.mock.lock_transfer("EXP_INCREASE_FEE_WHILE_DEPOSIT_IS_BEING_CONSOLIDATED_SCENARIO_1");
  let f3 = async { await* handler.trigger() };
  await ledger.mock.set_fee(100);
  ignore await* handler.fetchFee();
  assert handler.journalLength() == inc(1); // #feeUpdated
  await ledger.mock.set_response([#Err(#BadFee { expected_fee = 100 })]);
  await ledger.mock.release_transfer(); // let transfer return
  await f3;
  assert state(handler) == (0, 0, 0); // consolidation failed with deposit reset
  assert handler.journalLength() == inc(2); // #consolidationError, #debited
  assert handler.getCredit(user1) == 0; // credit has been corrected
  print("tree lookups = " # debug_show handler.lookups());

  // increase fee while deposit is being consolidated (explicitly)
  // scenario 2: old_fee < new_fee < deposit
  // consolidation should fail and deposit should be adjusted with new fee
  await ledger.mock.set_fee(5);
  ignore await* handler.fetchFee();
  assert handler.journalLength() == inc(1); // #feeUpdated
  assert (await* handler.notify(user1)) == ?(20, 15); // deposit = 20, credit = 15
  assert handler.journalLength() == inc(2); // #credited, #newDeposit
  assert state(handler) == (20, 0, 1);
  await ledger.mock.lock_transfer("EXP_INCREASE_FEE_WHILE_DEPOSIT_IS_BEING_CONSOLIDATED_SCENARIO_2");
  let f4 = async { await* handler.trigger() };
  await ledger.mock.set_fee(6);
  ignore await* handler.fetchFee();
  assert handler.journalLength() == inc(1); // #feeUpdated
  await ledger.mock.set_response([#Err(#BadFee { expected_fee = 6 })]);
  await ledger.mock.release_transfer(); // let transfer return
  await f4;
  assert state(handler) == (20, 0, 1); // consolidation failed with updated deposit scheduled
  assert handler.journalLength() == inc(3); // #consolidationError, #debited, #credited
  assert handler.getCredit(user1) == 14; // credit has been corrected
  print("tree lookups = " # debug_show handler.lookups());

  // only 1 consolidation process can be triggered for same user at same time
  // consolidation with deposit > fee should be successful
  await ledger.mock.set_response([#Ok 42]);
  var transfer_count = await ledger.mock.transfer_count();
  let f5 = async { await* handler.trigger() };
  let f6 = async { await* handler.trigger() };
  await f5;
  await f6;
  await ledger.mock.set_balance(0);
  assert ((await ledger.mock.transfer_count())) == transfer_count + 1; // only 1 transfer call has been made
  assert state(handler) == (0, 14, 0); // consolidation successful
  assert handler.journalLength() == inc(1); // #consolidated
  assert handler.getCredit(user1) == 14; // credit unchanged
  print("tree lookups = " # debug_show handler.lookups());

  handler.assertIntegrity();
  assert not handler.isFrozen();
};

do {
  let handler = TokenHandler.TokenHandler(ledger, anon_p, 1000, 0);
  await ledger.mock.reset_state();
  let (inc, _) = create_inc();

  // update fee first time
  await ledger.mock.set_fee(5);
  ignore await* handler.fetchFee();
  assert handler.fee() == 5;
  assert handler.journalLength() == inc(1); // #feeUpdated

  // increase deposit again
  await ledger.mock.set_balance(20);
  assert (await* handler.notify(user1)) == ?(20, 15); // deposit = 20, credit = 15
  assert state(handler) == (20, 0, 1);
  assert handler.journalLength() == inc(2); // #newDeposit, #credited
  print("tree lookups = " # debug_show handler.lookups());

  // trigger consolidation again
  await ledger.mock.set_response([#Ok 42]);
  await* handler.trigger();
  await ledger.mock.set_balance(0);
  assert state(handler) == (0, 15, 0); // consolidation successful
  assert handler.journalLength() == inc(1); // #consolidated
  print("tree lookups = " # debug_show handler.lookups());

  // withdraw (fee < amount < consolidated_funds)
  // should be successful
  await ledger.mock.set_fee(1);
  ignore await* handler.fetchFee();
  assert handler.journalLength() == inc(1); // #feeUpdated
  await ledger.mock.set_response([#Ok 42]);
  assert (await* handler.withdraw(account, 5)) == #ok(42, 4);
  assert handler.journalLength() == inc(1); // #withdraw
  ignore handler.debitStrict(user1, 5);
  assert state(handler) == (0, 10, 0);
  assert handler.journalLength() == inc(1); // #debited

  // withdraw (amount <= fee_)
  var transfer_count = await ledger.mock.transfer_count();
  await ledger.mock.set_response([#Ok 42]); // transfer call should not be executed anyway
  assert (await* handler.withdraw(account, 1)) == #err(#TooLowQuantity);
  assert (await ledger.mock.transfer_count()) == transfer_count; // no transfer call
  assert state(handler) == (0, 10, 0); // state unchanged
  assert handler.journalLength() == inc(1); // #withdrawError

  // withdraw (consolidated_funds < amount - fee)
  await ledger.mock.set_response([#Err(#InsufficientFunds({ balance = 10 }))]);
  assert (await* handler.withdraw(account, 100)) == #err(#InsufficientFunds({ balance = 10 }));
  assert state(handler) == (0, 10, 0); // state unchanged
  assert handler.journalLength() == inc(1); // #withdrawError

  // increase fee while withdraw is being underway
  // scenario 1: old_fee < new_fee < amount
  // withdraw should fail and then retry successfully, fee should be updated
  await ledger.mock.lock_transfer("INCREASE_FEE_WITHDRAW_IS_BEING_UNDERWAY_SCENARIO_1");
  transfer_count := await ledger.mock.transfer_count();
  let f1 = async { await* handler.withdraw(account, 5) };
  await ledger.mock.set_fee(2);
  await ledger.mock.set_response([#Err(#BadFee { expected_fee = 2 }), #Ok 42]);
  await ledger.mock.release_transfer(); // let transfer return
  assert (await f1) == #ok(42, 3);
  assert (await ledger.mock.transfer_count()) == transfer_count + 2;
  assert handler.journalLength() == inc(2); // #feeUpdated, #withdraw
  assert state(handler) == (0, 5, 0); // state has changed
  ignore handler.debitStrict(user1, 5);
  assert handler.journalLength() == inc(1); // #debited

  // increase fee while withdraw is being underway
  // scenario 2: old_fee < amount <= new_fee
  // withdraw should fail and then retry with failure, fee should be updated
  // the second call should be avoided with comparison amount and fee
  await ledger.mock.lock_transfer("INCREASE_FEE_WITHDRAW_IS_BEING_UNDERWAY_SCENARIO_2");
  transfer_count := await ledger.mock.transfer_count();
  let f2 = async { await* handler.withdraw(account, 4) };
  await ledger.mock.set_fee(4);
  await ledger.mock.set_response([#Err(#BadFee { expected_fee = 4 }), #Ok 42]); // the second call should not be executed
  await ledger.mock.release_transfer(); // let transfer return
  assert (await f2) == #err(#TooLowQuantity);
  assert (await ledger.mock.transfer_count()) == transfer_count + 1; // the second transfer call is avoided
  assert state(handler) == (0, 5, 0); // state unchanged
  assert handler.journalLength() == inc(2); // #feeUpdated, #withdrawalError

  handler.assertIntegrity();
  assert not handler.isFrozen();
};

do {
  let handler = TokenHandler.TokenHandler(ledger, anon_p, 1000, 0);
  await ledger.mock.reset_state();
  let (inc, _) = create_inc();

  // update fee first time
  await ledger.mock.set_fee(5);
  ignore await* handler.fetchFee();
  assert handler.fee() == 5;
  assert handler.journalLength() == inc(1); // #feeUpdated

  // Change fee while notify is underway with locked 0-deposit.
  // 0-deposits can be temporarily being stored in deposit registry because of being locked with #notify.
  // Deposit registry recalculation is triggered and credits related to 0-deposits should not be corrected there.

  // scenario 1: increase fee
  await ledger.mock.lock_balance("CHANGE_FEE_WHILE_NOTIFY_IS_UNDERWAY_WITH_LOCKED_0_DEPOSIT_SCENARIO_1");
  await ledger.mock.set_balance(5);
  let f1 = async { await* handler.notify(user1) };
  await ledger.mock.set_fee(6);
  ignore await* handler.fetchFee();
  assert handler.journalLength() == inc(1); // #feeUpdated
  await ledger.mock.release_balance(); // let notify return
  assert (await f1) == ?(0, 0);
  assert state(handler) == (0, 0, 0); // state unchanged because deposit has not changed
  assert handler.getCredit(user1) == 0; // credit should not be corrected
  assert handler.journalLength() == inc(0);
  print("tree lookups = " # debug_show handler.lookups());

  // scenario 2: decrease fee
  await ledger.mock.lock_balance("CHANGE_FEE_WHILE_NOTIFY_IS_UNDERWAY_WITH_LOCKED_0_DEPOSIT_SCENARIO_2");
  await ledger.mock.set_balance(5);
  let f2 = async { await* handler.notify(user1) };
  await ledger.mock.set_fee(2);
  ignore await* handler.fetchFee();
  assert handler.journalLength() == inc(1); // #feeUpdated
  await ledger.mock.release_balance(); // let notify return
  assert (await f2) == ?(5, 3);
  assert state(handler) == (5, 0, 1); // state unchanged because deposit has not changed
  assert handler.getCredit(user1) == 3; // credit should not be corrected
  assert handler.journalLength() == inc(2); // #credited, #newDeposit
  print("tree lookups = " # debug_show handler.lookups());

  // Recalculate credits related to deposits when fee changes

  // scenario 1: new_fee < prev_fee < deposit
  await ledger.mock.set_fee(1);
  ignore await* handler.fetchFee();
  assert handler.journalLength() == inc(2); // #feeUpdated, #credited
  assert handler.getCredit(user1) == 4; // credit corrected

  print("tree lookups = " # debug_show handler.lookups());

  // scenario 2: prev_fee < new_fee < deposit
  await ledger.mock.set_fee(3);
  ignore await* handler.fetchFee();
  assert handler.journalLength() == inc(2); // #feeUpdated, #debited
  assert handler.getCredit(user1) == 2; // credit corrected
  print("tree lookups = " # debug_show handler.lookups());

  // scenario 3: prev_fee < deposit <= new_fee
  await ledger.mock.set_fee(5);
  ignore await* handler.fetchFee();
  assert handler.journalLength() == inc(2); // #feeUpdated, #debited
  assert handler.getCredit(user1) == 0; // credit corrected
  print("tree lookups = " # debug_show handler.lookups());

  handler.assertIntegrity();
  assert not handler.isFrozen();
};

do {
  let handler = TokenHandler.TokenHandler(ledger, anon_p, 1000, 0);
  await ledger.mock.reset_state();
  let (inc, _) = create_inc();

  // update fee first time
  await ledger.mock.set_fee(5);
  ignore await* handler.fetchFee();
  assert handler.fee() == 5;
  assert handler.journalLength() == inc(1); // #feeUpdated

  // fetching fee should not overlap
  await ledger.mock.lock_fee("FETCHING_FEE_SHOULD_NOT_OVERLAP");
  await ledger.mock.set_fee(6);
  let f1 = async { await* handler.fetchFee() };
  let f2 = async { await* handler.fetchFee() };
  assert (await f2) == null;
  await ledger.mock.release_fee();
  assert (await f1) == ?6;
  assert handler.journalLength() == inc(1); // #feeUpdated
};
