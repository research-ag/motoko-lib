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
  transfer_from = mock_ledger.icrc2_transfer_from;
  mock = mock_ledger; // mock ledger for controlling responses
};

let anon_p = Principal.fromBlob("");
let user1 = Principal.fromBlob("1");
let user2 = Principal.fromBlob("2");
let account = { owner = Principal.fromBlob("o"); subaccount = null };
let user1_account = { owner = user1; subaccount = null };
//let account = { owner = Principal.fromBlob("1"); subaccount = null };

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
  assert handler.ledgerFee() == 0;
  assert handler.journalLength() == 0;

  // update fee first time
  await ledger.mock.set_fee(5);
  ignore await* handler.fetchFee();
  assert handler.ledgerFee() == 5;
  assert handler.journalLength() == inc(5); // #feeUpdated, #depositFeeUpdated, #withdrawalFeeUpdated, #depositMinimumUpdated, #withdrawalMinimumUpdated

  // notify with 0 balance
  await ledger.mock.set_balance(0);
  assert (await* handler.notify(user1)) == ?(0, 0);
  assert state(handler) == (0, 0, 0);
  assert handler.journalLength() == inc(0);
  print("tree lookups = " # debug_show handler.lookups_());

  // notify with balance <= fee
  await ledger.mock.set_balance(5);
  assert (await* handler.notify(user1)) == ?(0, 0);
  assert state(handler) == (0, 0, 0);
  assert handler.journalLength() == inc(0);
  print("tree lookups = " # debug_show handler.lookups_());

  // notify with balance > fee
  await ledger.mock.set_balance(6);
  assert (await* handler.notify(user1)) == ?(6, 1); // deposit = 6, credit = 1
  assert state(handler) == (6, 0, 1);
  assert handler.journalLength() == inc(2); // #newDeposit, #credited
  print("tree lookups = " # debug_show handler.lookups_());

  // increase fee while item still in queue (trigger did not run yet)
  await ledger.mock.set_fee(6);
  ignore await* handler.fetchFee();
  assert state(handler) == (0, 0, 0); // recalculation after fee update
  assert handler.journalLength() == inc(6); // #feeUpdated, #debited, #depositMinimumUpdated, #withdrawalMinimumUpdated, #depositFeeUpdated, #withdrawalFeeUpdated
  print("tree lookups = " # debug_show handler.lookups_());

  // increase deposit again
  await ledger.mock.set_balance(7);
  assert (await* handler.notify(user1)) == ?(7, 1); // deposit = 7, credit = 1
  assert state(handler) == (7, 0, 1);
  assert handler.journalLength() == inc(2); // #newDeposit, #credited
  print("tree lookups = " # debug_show handler.lookups_());

  // increase fee while notify is underway (and item still in queue)
  // scenario 1: old_fee < previous = latest <= new_fee
  // this means no new deposit has happened (latest = previous)
  await ledger.mock.lock_balance("INCREASE_FEE_WHILE_NOTIFY_IS_UNDERWAY_SCENARIO_1");
  let f1 = async { await* handler.notify(user1) }; // would return ?(0, 1) at old fee
  await ledger.mock.set_fee(10); // fee 6 -> 10
  assert state(handler) == (7, 0, 1); // state from before
  ignore await* handler.fetchFee();
  assert handler.journalLength() == inc(6); // #feeUpdated, #depositFeeUpdated, #withdrawalFeeUpdated, #debited, #depositMinimumUpdated, #withdrawalMinimumUpdated
  assert state(handler) == (0, 0, 0); // state changed
  await ledger.mock.release_balance(); // let notify return
  assert (await f1) == ?(0, 0); // deposit <= new fee
  assert handler.journalLength() == inc(0);
  print("tree lookups = " # debug_show handler.lookups_());

  // increase deposit again
  await ledger.mock.set_balance(15);
  assert (await* handler.notify(user1)) == ?(15, 5); // deposit = 15, credit = 5
  assert state(handler) == (15, 0, 1);
  assert handler.journalLength() == inc(2); // #newDeposit, #credited
  print("tree lookups = " # debug_show handler.lookups_());

  // increase fee while notify is underway (and item still in queue)
  // scenario 2: old_fee < previous <= new_fee < latest
  await ledger.mock.set_balance(20);
  await ledger.mock.lock_balance("INCREASE_FEE_WHILE_NOTIFY_IS_UNDERWAY_SCENARIO_2");
  let f2 = async { await* handler.notify(user1) }; // would return ?(5, 10) at old fee
  await ledger.mock.set_fee(15); // fee 10 -> 15
  assert state(handler) == (15, 0, 1); // state from before
  ignore await* handler.fetchFee();
  assert handler.journalLength() == inc(6); // #feeUpdated, #depositFeeUpdated, #withdrawalFeeUpdated, #debited, #depositMinimumUpdated, #withdrawalMinimumUpdated
  assert state(handler) == (0, 0, 0); // state changed
  await ledger.mock.release_balance(); // let notify return
  assert (await f2) == ?(20, 5); // credit = latest - new_fee
  assert state(handler) == (20, 0, 1); // state should have changed
  assert handler.journalLength() == inc(2); // #newDeposit, #credited
  print("tree lookups = " # debug_show handler.lookups_());

  // decrease fee while notify is underway (and item still in queue)
  // new_fee < old_fee < previous == latest
  await ledger.mock.lock_balance("DECREASE_FEE_WHILE_NOTIFY_IS_UNDERWAY");
  let f3 = async { await* handler.notify(user1) }; // would return ?(0, 5) at old fee
  await ledger.mock.set_fee(10); // fee 15 -> 10
  assert state(handler) == (20, 0, 1); // state from before
  ignore await* handler.fetchFee();
  assert handler.journalLength() == inc(6); // #feeUpdated, #depositFeeUpdated, #withdrawalFeeUpdated, #credited, #depositMinimumUpdated, #withdrawalMinimumUpdated
  assert state(handler) == (20, 0, 1); // state unchanged
  await ledger.mock.release_balance(); // let notify return
  assert (await f3) == ?(0, 10); // credit increased
  assert state(handler) == (20, 0, 1); // state unchanged
  print("tree lookups = " # debug_show handler.lookups_());

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
  print("tree lookups = " # debug_show handler.lookups_());

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
  assert handler.ledgerFee() == 5;
  assert handler.journalLength() == inc(5); // #feeUpdated,  #depositFeeUpdated, #withdrawalFeeUpdated, #depositMinimumUpdated, #withdrawalMinimumUpdated

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
  assert handler.journalLength() == inc(7); // #consolidationError, #debited, #feeUpdated, #depositFeeUpdated, #withdrawalFeeUpdated, #depositMinimumUpdated, #withdrawalMinimumUpdated
  // TODO assert handler.journalLength() == inc(5); // #consolidationError, #debited, #feeUpdated, #depositMinimumUpdated, #withdrawalMinimumUpdated
  assert handler.userCredit(user1) == 0; // credit has been corrected after consolidation
  print("tree lookups = " # debug_show handler.lookups_());

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
  assert handler.journalLength() == inc(8); // #consolidationError, #debited, #feeUpdated, #depositFeeUpdated, #withdrawalFeeUpdated, #credited, #depositMinimumUpdated, #withdrawalMinimumUpdated
  // TODO assert handler.journalLength() == inc(6); // #consolidationError, #debited, #feeUpdated, #credited, #depositMinimumUpdated, #withdrawalMinimumUpdated
  assert handler.userCredit(user1) == 5; // credit has been corrected after consolidation
  print("tree lookups = " # debug_show handler.lookups_());

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
  assert handler.journalLength() == inc(5); // #feeUpdated, #depositFeeUpdated, #withdrawalFeeUpdated, #depositMinimumUpdated, #withdrawalMinimumUpdated
  await ledger.mock.set_response([#Err(#BadFee { expected_fee = 100 })]);
  await ledger.mock.release_transfer(); // let transfer return
  await f3;
  assert state(handler) == (0, 0, 0); // consolidation failed with deposit reset
  assert handler.journalLength() == inc(2); // #consolidationError, #debited
  assert handler.userCredit(user1) == 0; // credit has been corrected
  print("tree lookups = " # debug_show handler.lookups_());

  // increase fee while deposit is being consolidated (explicitly)
  // scenario 2: old_fee < new_fee < deposit
  // consolidation should fail and deposit should be adjusted with new fee
  await ledger.mock.set_fee(5);
  ignore await* handler.fetchFee();
  assert handler.journalLength() == inc(5); // #feeUpdated, #depositFeeUpdated, #withdrawalFeeUpdated, #depositMinimumUpdated, #withdrawalMinimumUpdated
  assert (await* handler.notify(user1)) == ?(20, 15); // deposit = 20, credit = 15
  assert handler.journalLength() == inc(2); // #credited, #newDeposit
  assert state(handler) == (20, 0, 1);
  await ledger.mock.lock_transfer("EXP_INCREASE_FEE_WHILE_DEPOSIT_IS_BEING_CONSOLIDATED_SCENARIO_2");
  let f4 = async { await* handler.trigger() };
  await ledger.mock.set_fee(6);
  ignore await* handler.fetchFee();
  assert handler.journalLength() == inc(5); // #feeUpdated, #depositFeeUpdated, #withdrawalFeeUpdated, #depositMinimumUpdated, #withdrawalMinimumUpdated
  await ledger.mock.set_response([#Err(#BadFee { expected_fee = 6 })]);
  await ledger.mock.release_transfer(); // let transfer return
  await f4;
  assert state(handler) == (20, 0, 1); // consolidation failed with updated deposit scheduled
  assert handler.journalLength() == inc(3); // #consolidationError, #debited, #credited
  assert handler.userCredit(user1) == 14; // credit has been corrected
  print("tree lookups = " # debug_show handler.lookups_());

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
  assert handler.userCredit(user1) == 14; // credit unchanged
  print("tree lookups = " # debug_show handler.lookups_());

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
  assert handler.ledgerFee() == 5;
  assert handler.journalLength() == inc(5); // #feeUpdated, #depositFeeUpdated, #withdrawalFeeUpdated, #depositMinimumUpdated, #withdrawalMinimumUpdated

  // increase deposit again
  await ledger.mock.set_balance(20);
  assert (await* handler.notify(user1)) == ?(20, 15); // deposit = 20, credit = 15
  assert state(handler) == (20, 0, 1);
  assert handler.journalLength() == inc(2); // #newDeposit, #credited
  print("tree lookups = " # debug_show handler.lookups_());

  // trigger consolidation again
  await ledger.mock.set_response([#Ok 42]);
  await* handler.trigger();
  await ledger.mock.set_balance(0);
  assert state(handler) == (0, 15, 0); // consolidation successful
  assert handler.journalLength() == inc(1); // #consolidated
  print("tree lookups = " # debug_show handler.lookups_());

  // withdraw (fee < amount < consolidated_funds)
  // should be successful
  await ledger.mock.set_fee(1);
  ignore await* handler.fetchFee();
  assert handler.journalLength() == inc(5); // #feeUpdated, #depositFeeUpdated, #withdrawalFeeUpdated, #depositMinimumUpdated, #withdrawalMinimumUpdated
  await ledger.mock.set_response([#Ok 42]);
  assert (await* handler.withdrawFromCredit(user1, account, 5)) == #ok(42, 4);
  assert handler.journalLength() == inc(2); // #burned, #withdraw
  assert state(handler) == (0, 10, 0);

  // withdraw (amount <= fee_)
  var transfer_count = await ledger.mock.transfer_count();
  await ledger.mock.set_response([#Ok 42]); // transfer call should not be executed anyway
  assert (await* handler.withdrawFromCredit(user1, account, 1)) == #err(#TooLowQuantity);
  assert (await ledger.mock.transfer_count()) == transfer_count; // no transfer call
  assert state(handler) == (0, 10, 0); // state unchanged
  assert handler.journalLength() == inc(3); // #burned, #withdrawError, #issued

  // withdraw (consolidated_funds < amount)
  await ledger.mock.set_response([#Err(#InsufficientFunds({ balance = 10 }))]);
  // TODO: InsufficientCredit should return current credit balance?
  assert (await* handler.withdrawFromCredit(user1, account, 100)) == #err(#InsufficientCredit);
  assert state(handler) == (0, 10, 0); // state unchanged
  assert handler.journalLength() == inc(1); // #withdrawError

  // increase fee while withdraw is being underway
  // scenario 1: old_fee < new_fee < amount
  // withdraw should fail and then retry successfully, fee should be updated
  await ledger.mock.lock_transfer("INCREASE_FEE_WITHDRAW_IS_BEING_UNDERWAY_SCENARIO_1");
  transfer_count := await ledger.mock.transfer_count();
  let f1 = async { await* handler.withdrawFromCredit(user1, account, 5) };
  await ledger.mock.set_fee(2);
  await ledger.mock.set_response([#Err(#BadFee { expected_fee = 2 }), #Ok 42]);
  await ledger.mock.release_transfer(); // let transfer return
  assert (await f1) == #ok(42, 3);
  assert (await ledger.mock.transfer_count()) == transfer_count + 2;
  assert handler.journalLength() == inc(7); // #burned, #feeUpdated, #depositMinimumUpdated, #withdrawalMinimumUpdated, depositFeeUpdated, withdrawalFeeUpdated, #withdraw
  assert state(handler) == (0, 5, 0); // state has changed
  assert handler.debitUser(user1, 5);
  assert handler.journalLength() == inc(1); // #debited

  // increase fee while withdraw is being underway
  // scenario 2: old_fee < amount <= new_fee
  // withdraw should fail and then retry with failure, fee should be updated
  // the second call should be avoided with comparison amount and fee
  await ledger.mock.lock_transfer("INCREASE_FEE_WITHDRAW_IS_BEING_UNDERWAY_SCENARIO_2");
  transfer_count := await ledger.mock.transfer_count();
  let f2 = async { await* handler.withdrawFromPool(account, 4) };
  await ledger.mock.set_fee(4);
  await ledger.mock.set_response([#Err(#BadFee { expected_fee = 4 }), #Ok 42]); // the second call should not be executed
  await ledger.mock.release_transfer(); // let transfer return
  assert (await f2) == #err(#TooLowQuantity);
  assert (await ledger.mock.transfer_count()) == transfer_count + 1; // the second transfer call is avoided
  assert state(handler) == (0, 5, 0); // state unchanged
  assert handler.journalLength() == inc(8); // #burned, #feeUpdated, #depositMinimumUpdated, #withdrawalMinimumUpdated, #depositFeeUpdated, #withdrawalFeeUpdated, #withdrawalError, #issued

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
  assert handler.ledgerFee() == 5;
  assert handler.fee(#deposit) == 5;
  assert handler.fee(#withdrawal) == 5;
  assert handler.journalLength() == inc(5); // #feeUpdated, #depositMinimumUpdated, #withdrawalMinimumUpdated, #depositFeeUpdated, #withdrawalFeeUpdated

  // another user deposit + consolidation
  await ledger.mock.set_balance(300);
  assert (await* handler.notify(user2)) == ?(300, 295); // deposit = 300, credit = 295
  assert handler.journalLength() == inc(2); // #newDeposit, #credited
  await ledger.mock.set_response([#Ok 42]);
  await* handler.trigger();
  await ledger.mock.set_balance(0);
  assert state(handler) == (0, 295, 0); // consolidation successful
  assert handler.journalLength() == inc(1); // #consolidated
  print("tree lookups = " # debug_show handler.lookups_());

  // increase deposit
  await ledger.mock.set_balance(20);
  assert (await* handler.notify(user1)) == ?(20, 15); // deposit = 20, credit = 15
  assert state(handler) == (20, 295, 1);
  assert handler.journalLength() == inc(2); // #newDeposit, #credited
  print("tree lookups = " # debug_show handler.lookups_());

  // trigger consolidation
  await ledger.mock.set_response([#Ok 42]);
  await* handler.trigger();
  await ledger.mock.set_balance(0);
  assert state(handler) == (0, 310, 0); // consolidation successful
  assert handler.journalLength() == inc(1); // #consolidated
  print("tree lookups = " # debug_show handler.lookups_());

  // withdraw from credit (fee < amount =< credit)
  // should be successful
  await ledger.mock.set_fee(1);
  ignore await* handler.fetchFee();
  assert handler.journalLength() == inc(5); // #feeUpdated, #depositMinimumUpdated, #withdrawalMinimumUpdated, #depositFeeUpdated, #withdrawalFeeUpdated
  await ledger.mock.set_response([#Ok 42]);
  assert (await* handler.withdrawFromCredit(user1, account, 5)) == #ok(42, 4);
  assert handler.journalLength() == inc(2); // #withdraw, #debited
  assert state(handler) == (0, 305, 0);
  assert handler.userCredit(user1) == 10;

  // withdraw from credit (amount <= fee_ =< credit)
  var transfer_count = await ledger.mock.transfer_count();
  await ledger.mock.set_response([#Ok 42]); // transfer call should not be executed anyway
  assert (await* handler.withdrawFromCredit(user1, account, 1)) == #err(#TooLowQuantity);
  assert (await ledger.mock.transfer_count()) == transfer_count; // no transfer call
  assert state(handler) == (0, 305, 0); // state unchanged
  assert handler.journalLength() == inc(3); // #burned, #withdrawError, #issued

  // withdraw from credit (credit < amount)
  // insufficient user credit
  transfer_count := await ledger.mock.transfer_count();
  await ledger.mock.set_response([#Ok 42]); // transfer call should not be executed anyway
  assert (await* handler.withdrawFromCredit(user1, account, 12)) == #err(#InsufficientCredit); // amount 12 > credit 10
  assert (await ledger.mock.transfer_count()) == transfer_count; // no transfer call
  assert state(handler) == (0, 305, 0); // state unchanged
  assert handler.journalLength() == inc(1); // #withdrawError

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
  assert handler.ledgerFee() == 5;
  assert handler.journalLength() == inc(5); // #feeUpdated, #depositFeeUpdated, #withdrawalFeeUpdated, #depositMinimumUpdated, #withdrawalMinimumUpdated

  // another user deposit + consolidation
  await ledger.mock.set_balance(300);
  assert (await* handler.notify(user2)) == ?(300, 295); // deposit = 300, credit = 295
  assert handler.journalLength() == inc(2); // #newDeposit, #credited
  await ledger.mock.set_response([#Ok 42]);
  await* handler.trigger();
  await ledger.mock.set_balance(0);
  assert state(handler) == (0, 295, 0); // consolidation successful
  assert handler.journalLength() == inc(1); // #consolidated
  print("tree lookups = " # debug_show handler.lookups_());

  // increase deposit
  await ledger.mock.set_balance(20);
  assert (await* handler.notify(user1)) == ?(20, 15); // deposit = 20, credit = 15
  assert state(handler) == (20, 295, 1);
  assert handler.journalLength() == inc(2); // #newDeposit, #credited
  print("tree lookups = " # debug_show handler.lookups_());

  // trigger consolidation
  await ledger.mock.set_response([#Ok 42]);
  await* handler.trigger();
  await ledger.mock.set_balance(0);
  assert state(handler) == (0, 310, 0); // consolidation successful
  assert handler.journalLength() == inc(1); // #consolidated
  print("tree lookups = " # debug_show handler.lookups_());

  // withdraw from credit (fee < amount =< credit)
  // should be successful
  await ledger.mock.set_fee(1);
  ignore await* handler.fetchFee();
  assert handler.journalLength() == inc(5); // #feeUpdated, #depositFeeUpdated, #withdrawalFeeUpdated, #depositMinimumUpdated, #withdrawalMinimumUpdated
  await ledger.mock.set_response([#Ok 42]);
  assert (await* handler.withdrawFromCredit(user1, account, 5)) == #ok(42, 4);
  assert handler.journalLength() == inc(2); // #withdraw, #debited
  assert state(handler) == (0, 305, 0);
  assert handler.userCredit(user1) == 10;

  // withdraw from credit (amount <= fee_ =< credit)
  var transfer_count = await ledger.mock.transfer_count();
  await ledger.mock.set_response([#Ok 42]); // transfer call should not be executed anyway
  assert (await* handler.withdrawFromCredit(user1, account, 1)) == #err(#TooLowQuantity);
  assert (await ledger.mock.transfer_count()) == transfer_count; // no transfer call
  assert state(handler) == (0, 305, 0); // state unchanged
  assert handler.journalLength() == inc(3); // #burned, #withdrawError, #issued

  // withdraw from credit (credit < amount)
  // insufficient user credit
  transfer_count := await ledger.mock.transfer_count();
  await ledger.mock.set_response([#Ok 42]); // transfer call should not be executed anyway
  assert (await* handler.withdrawFromCredit(user1, account, 12)) == #err(#InsufficientCredit); // amount 12 > credit 10
  assert (await ledger.mock.transfer_count()) == transfer_count; // no transfer call
  assert state(handler) == (0, 305, 0); // state unchanged
  assert handler.journalLength() == inc(1); // #withdrawError

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
  assert handler.ledgerFee() == 5;
  assert handler.journalLength() == inc(5); // #feeUpdated, #depositFeeUpdated, #withdrawalFeeUpdated, #depositMinimumUpdated, #withdrawalMinimumUpdated

  // Change fee while notify is underway with locked 0-deposit.
  // 0-deposits can be temporarily being stored in deposit registry because of being locked with #notify.
  // Deposit registry recalculation is triggered and credits related to 0-deposits should not be corrected there.

  // scenario 1: increase fee
  await ledger.mock.lock_balance("CHANGE_FEE_WHILE_NOTIFY_IS_UNDERWAY_WITH_LOCKED_0_DEPOSIT_SCENARIO_1");
  await ledger.mock.set_balance(5);
  let f1 = async { await* handler.notify(user1) };
  await ledger.mock.set_fee(6);
  ignore await* handler.fetchFee();
  assert handler.journalLength() == inc(5); // #feeUpdated, #depositFeeUpdated, #withdrawalFeeUpdated, #depositMinimumUpdated, #withdrawalMinimumUpdated
  await ledger.mock.release_balance(); // let notify return
  assert (await f1) == ?(0, 0);
  assert state(handler) == (0, 0, 0); // state unchanged because deposit has not changed
  assert handler.userCredit(user1) == 0; // credit should not be corrected
  assert handler.journalLength() == inc(0);
  print("tree lookups = " # debug_show handler.lookups_());

  // scenario 2: decrease fee
  await ledger.mock.lock_balance("CHANGE_FEE_WHILE_NOTIFY_IS_UNDERWAY_WITH_LOCKED_0_DEPOSIT_SCENARIO_2");
  await ledger.mock.set_balance(5);
  let f2 = async { await* handler.notify(user1) };
  await ledger.mock.set_fee(2);
  ignore await* handler.fetchFee();
  assert handler.journalLength() == inc(5); // #feeUpdated, #depositFeeUpdated, #withdrawalFeeUpdated, #depositMinimumUpdated, #withdrawalMinimumUpdated
  await ledger.mock.release_balance(); // let notify return
  assert (await f2) == ?(5, 3);
  assert state(handler) == (5, 0, 1); // state unchanged because deposit has not changed
  assert handler.userCredit(user1) == 3; // credit should not be corrected
  assert handler.journalLength() == inc(2); // #credited, #newDeposit
  print("tree lookups = " # debug_show handler.lookups_());

  // Recalculate credits related to deposits when fee changes

  // scenario 1: new_fee < prev_fee < deposit
  await ledger.mock.set_fee(1);
  ignore await* handler.fetchFee();
  assert handler.journalLength() == inc(6); // #feeUpdated, #credited, #depositMinimumUpdated, #withdrawalMinimumUpdated, #depositFeeUpdated, #withdrawalFeeUpdated
  assert handler.userCredit(user1) == 4; // credit corrected

  print("tree lookups = " # debug_show handler.lookups_());

  // scenario 2: prev_fee < new_fee < deposit
  await ledger.mock.set_fee(3);
  ignore await* handler.fetchFee();
  assert handler.journalLength() == inc(6); // #feeUpdated, #debited, #depositMinimumUpdated, #withdrawalMinimumUpdated, #depositFeeUpdated, #withdrawalFeeUpdated
  assert handler.userCredit(user1) == 2; // credit corrected
  print("tree lookups = " # debug_show handler.lookups_());

  // scenario 3: prev_fee < deposit <= new_fee
  await ledger.mock.set_fee(5);
  ignore await* handler.fetchFee();
  // TODO assert handler.journalLength() == inc(6); // #feeUpdated, #depositFeeUpdated, #withdrawalFeeUpdated, #debited, #depositMinimumUpdated, #withdrawalMinimumUpdated
  assert handler.journalLength() == inc(6); // #feeUpdated, #debited, #depositMinimumUpdated, #withdrawalMinimumUpdated, #depositFeeUpdated, #withdrawalFeeUpdated
  assert handler.userCredit(user1) == 0; // credit corrected
  print("tree lookups = " # debug_show handler.lookups_());

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
  assert handler.ledgerFee() == 5;
  assert handler.journalLength() == inc(5); // #feeUpdated, #depositMinimumUpdated, #withdrawalMinimumUpdated, #depositFeeUpdated, #withdrawalFeeUpdated
  print("tree lookups = " # debug_show handler.lookups_());

  // fetching fee should not overlap
  await ledger.mock.lock_fee("FETCHING_FEE_SHOULD_NOT_OVERLAP");
  await ledger.mock.set_fee(6);
  let f1 = async { await* handler.fetchFee() };
  let f2 = async { await* handler.fetchFee() };
  assert (await f2) == null;
  await ledger.mock.release_fee();
  assert (await f1) == ?6;
  assert handler.journalLength() == inc(5); // #feeUpdated, #depositMinimumUpdated, #withdrawalMinimumUpdated, #depositFeeUpdated, #withdrawalFeeUpdated
  print("tree lookups = " # debug_show handler.lookups_());

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
  assert handler.ledgerFee() == 5;
  assert handler.minimum(#deposit) == 6;
  assert handler.minimum(#withdrawal) == 6;
  assert handler.journalLength() == inc(5); // #feeUpdated, #depositMinimumUpdated, #withdrawalMinimumUpdated, #depositFeeUpdated, #withdrawalFeeUpdated
  print("tree lookups = " # debug_show handler.lookups_());

  // set deposit minimum
  // case: min > fee
  handler.setMinimum(#deposit, 12);
  assert handler.minimum(#deposit) == 12;
  assert handler.journalLength() == inc(1); // #depositMinimumUpdated

  // set deposit minimum
  // case: min == prev_min
  handler.setMinimum(#deposit, 12);
  assert handler.minimum(#deposit) == 12;
  assert handler.journalLength() == inc(0);
  print("tree lookups = " # debug_show handler.lookups_());

  // set deposit minimum
  // case: min < fee
  handler.setMinimum(#deposit, 4);
  assert handler.minimum(#deposit) == 6; // fee + 1
  assert handler.journalLength() == inc(1); // #depositMinimumUpdated
  print("tree lookups = " # debug_show handler.lookups_());

  // set deposit minimum
  // case: min == fee
  handler.setMinimum(#deposit, 5);
  assert handler.minimum(#deposit) == 6;
  assert handler.journalLength() == inc(0);
  print("tree lookups = " # debug_show handler.lookups_());

  // notify
  // case: fee < balance < min
  handler.setMinimum(#deposit, 9);
  assert handler.minimum(#deposit) == 9;
  assert handler.journalLength() == inc(1); // #depositMinimumUpdated
  await ledger.mock.set_balance(8);
  assert (await* handler.notify(user1)) == ?(0, 0);
  assert handler.journalLength() == inc(0);
  print("tree lookups = " # debug_show handler.lookups_());

  // notify
  // case: fee < min <= balance
  await ledger.mock.set_balance(9);
  assert (await* handler.notify(user1)) == ?(9, 4);
  assert handler.journalLength() == inc(2); // #credited, #newDeposit
  print("tree lookups = " # debug_show handler.lookups_());

  // notify
  // case: fee < balance < min, old deposit exists
  // old deposit should not be reset because it was made before minimum increase
  handler.setMinimum(#deposit, 15);
  assert handler.minimum(#deposit) == 15;
  assert handler.journalLength() == inc(1); // #depositMinimumUpdated
  await ledger.mock.set_balance(12);
  assert (await* handler.notify(user1)) == ?(0, 4); // deposit not updated
  assert handler.journalLength() == inc(0);
  print("tree lookups = " # debug_show handler.lookups_());

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
  assert handler.ledgerFee() == 5;
  assert handler.minimum(#deposit) == 6;
  assert handler.minimum(#withdrawal) == 6;
  assert handler.journalLength() == inc(5); // #feeUpdated, #depositFeeUpdated, #withdrawalFeeUpdated, #depositMinimumUpdated, #withdrawalMinimumUpdated

  // increase deposit again
  await ledger.mock.set_balance(20);
  assert (await* handler.notify(user1)) == ?(20, 15); // deposit = 20, credit = 15
  assert state(handler) == (20, 0, 1);
  assert handler.journalLength() == inc(2); // #newDeposit, #credited
  print("tree lookups = " # debug_show handler.lookups_());

  // trigger consolidation again
  await ledger.mock.set_response([#Ok 42]);
  await* handler.trigger();
  await ledger.mock.set_balance(0);
  assert state(handler) == (0, 15, 0); // consolidation successful
  assert handler.journalLength() == inc(1); // #consolidated
  print("tree lookups = " # debug_show handler.lookups_());

  // set withdrawal minimum
  // case: min > fee
  handler.setMinimum(#withdrawal, 12);
  assert handler.minimum(#withdrawal) == 12;
  assert handler.journalLength() == inc(1); // #withdrawalMinimumUpdated

  // set withdrawal minimum
  // case: min == prev_min
  handler.setMinimum(#withdrawal, 12);
  assert handler.minimum(#withdrawal) == 12;
  assert handler.journalLength() == inc(0);
  print("tree lookups = " # debug_show handler.lookups_());

  // set withdrawal minimum
  // case: min < fee
  handler.setMinimum(#withdrawal, 4);
  assert handler.minimum(#withdrawal) == 6; // fee + 1
  assert handler.journalLength() == inc(1); // #depositMinimumUpdated
  print("tree lookups = " # debug_show handler.lookups_());

  // set withdrawal minimum
  // case: min == fee
  handler.setMinimum(#withdrawal, 5);
  assert handler.minimum(#withdrawal) == 6;
  assert handler.journalLength() == inc(0);
  print("tree lookups = " # debug_show handler.lookups_());

  // increase withdrawal minimum
  handler.setMinimum(#withdrawal, 11);
  assert handler.minimum(#withdrawal) == 11;
  assert handler.journalLength() == inc(1); // #withdrawalMinimumUpdated

  // withdraw
  // case: fee < amount < min
  var transfer_count = await ledger.mock.transfer_count();
  await ledger.mock.set_response([#Ok 42]); // transfer call should not be executed anyway
  assert (await* handler.withdrawFromCredit(user1, account, 6)) == #err(#TooLowQuantity);
  assert (await ledger.mock.transfer_count()) == transfer_count; // no transfer call
  assert state(handler) == (0, 15, 0); // state unchanged
  assert handler.journalLength() == inc(3); // #burned, #withdrawError, #issued
  print("tree lookups = " # debug_show handler.lookups_());

  // withdraw
  // case: fee < min <= amount
  await ledger.mock.set_response([#Ok 42]);
  assert (await* handler.withdrawFromCredit(user1, account, 11)) == #ok(42, 6);
  assert handler.journalLength() == inc(2); // #burned, #withdraw
  assert state(handler) == (0, 4, 0);

  handler.assertIntegrity();
  assert not handler.isFrozen();
};

do {
  let handler = TokenHandler.TokenHandler(ledger, anon_p, 1000, 0);
  await ledger.mock.reset_state();
  let (inc, _) = create_inc();

//  TODO: fix tests

  // credit issuer
  handler.issue_(#pool, 20);
  assert handler.poolCredit() == 20;
  assert handler.journalLength() == inc(1); // #issued

  // debit issuer
  handler.issue_(#pool, -5);
  assert handler.poolCredit() == 15;
  assert handler.journalLength() == inc(1); // #issued

  // credit user
  // case: pool credit < amount
  assert (handler.creditUser(user1, 30)) == false;
  assert handler.journalLength() == inc(0);
  assert handler.poolCredit() == 15;
  assert handler.userCredit(user1) == 0;

  // credit user
  // case: pool credit <= amount
  assert (handler.creditUser(user1, 15)) == true;
  assert handler.journalLength() == inc(1); // #credited
  assert handler.poolCredit() == 0;
  assert handler.userCredit(user1) == 15;

  // debit user
  // case: credit < amount
  assert (handler.debitUser(user1, 16)) == false;
  assert handler.journalLength() == inc(0);
  assert handler.poolCredit() == 0;
  assert handler.userCredit(user1) == 15;

  // debit user
  // case: credit >= amount
  assert (handler.debitUser(user1, 15)) == true;
  assert handler.journalLength() == inc(1); // #debited
  assert handler.poolCredit() == 15;
  assert handler.userCredit(user1) == 0;

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
  assert handler.ledgerFee() == 5;
  assert handler.minimum(#deposit) == 6;
  assert handler.minimum(#withdrawal) == 6;
  assert handler.journalLength() == inc(5); // #feeUpdated, #depositFeeUpdated, #withdrawalFeeUpdated, #depositMinimumUpdated, #withdrawalMinimumUpdated

  // set deposit fee
  // case: fee > ledger_fee
  handler.setFee(#deposit, 6);
  assert handler.fee(#deposit) == 6;
  assert handler.journalLength() == inc(2); // #depositFeeUpdated, #depositMinimumUpdated

  // set deposit fee
  // case: fee == prev_fee
  handler.setFee(#deposit, 6);
  assert handler.fee(#deposit) == 6;
  assert handler.journalLength() == inc(0);

  // set deposit fee
  // case: fee < ledger_fee
  handler.setFee(#deposit, 4);
  assert handler.fee(#deposit) == 5;
  assert handler.journalLength() == inc(2); // #depositFeeUpdated, #depositMinimumUpdated

  // set deposit fee
  // case: fee == ledger_fee
  handler.setFee(#deposit, 4);
  assert handler.fee(#deposit) == 5;
  assert handler.journalLength() == inc(0);

  // notify (balance > min)
  await ledger.mock.set_balance(13);
  assert (await* handler.notify(user1)) == ?(13, 8);
  assert handler.journalLength() == inc(2); // #credited, #newDeposit

  // set deposit fee (new_min) > balance
  assert handler.userCredit(user1) == 8;
  handler.setFee(#deposit, 6);
  assert handler.fee(#deposit) == 6;
  assert handler.journalLength() == inc(3); // #depositFeeUpdated, #depositMinimumUpdated, #debited
  assert handler.userCredit(user1) == 7; // credit corrected

  // trigger consolidation
  await ledger.mock.set_response([#Ok 42]);
  await* handler.trigger();
  await ledger.mock.set_balance(0);
  assert state(handler) == (0, 7, 0); // consolidation successful
  assert handler.journalLength() == inc(1); // #consolidated

  // set withdrawal fee
  // case: fee > ledger_fee
  handler.setFee(#withdrawal, 6);
  assert handler.fee(#withdrawal) == 6;
  assert handler.journalLength() == inc(2); // #withdrawalFeeUpdated, #withdrawalMinimumUpdated

  // set withdrawal fee
  // case: fee == prev_fee
  handler.setFee(#withdrawal, 6);
  assert handler.fee(#withdrawal) == 6;
  assert handler.journalLength() == inc(0);

  // set withdrawal fee
  // case: fee < ledger_fee
  handler.setFee(#withdrawal, 4);
  assert handler.fee(#withdrawal) == 5;
  assert handler.journalLength() == inc(2); // #withdrawalFeeUpdated, #withdrawalMinimumUpdated

  // set withdrawal fee
  // case: fee == ledger_fee
  handler.setFee(#withdrawal, 4);
  assert handler.fee(#withdrawal) == 5;
  assert handler.journalLength() == inc(0);

  // decrease ledger fee (ledger_fee < withdrawal_fee)
  await ledger.mock.set_fee(2);
  ignore await* handler.fetchFee();
  assert handler.ledgerFee() == 2;
  assert handler.minimum(#withdrawal) == 5; // withdrawal_fee + 1
  assert handler.journalLength() == inc(3); // #feeUpdated, #withdrawalFeeUpdated, #withdrawalMinimumUpdated

  // withdrawal with defined withdrawal fee
  await ledger.mock.set_response([#Ok 42]);
  assert (await* handler.withdrawFromCredit(user1, account, 5)) == #ok(42, 1);
  assert handler.journalLength() == inc(2); // #withdraw, #debited
  assert state(handler) == (0, 2, 0);
  assert handler.userCredit(user1) == 2;

  handler.assertIntegrity();
  assert not handler.isFrozen();
};

do {
  let handler = TokenHandler.TokenHandler(ledger, anon_p, 1000, 0);
  await ledger.mock.reset_state();
  let (inc, _) = create_inc();

  // credit issuer
  handler.issue_(#pool, 20);
  assert handler.poolCredit() == 20;
  assert handler.journalLength() == inc(1); // #issued

  // debit issuer
  handler.issue_(#pool, -5);
  assert handler.poolCredit() == 15;
  assert handler.journalLength() == inc(1); // #issued

  // credit (strict)
  // case: issuer_credit < amount
  assert (handler.creditUser(user1, 30)) == false;
  assert handler.journalLength() == inc(0);
  assert handler.poolCredit() == 15;
  assert handler.userCredit(user1) == 0;

  // credit (strict)
  // case: issuer_credit <= amount
  assert (handler.creditUser(user1, 15)) == true;
  assert handler.journalLength() == inc(1); // #credited
  assert handler.poolCredit() == 0;
  assert handler.userCredit(user1) == 15;

  // debit (strict)
  // case: credit < amount
  assert (handler.debitUser(user1, 16)) == false;
  assert handler.journalLength() == inc(0);
  assert handler.poolCredit() == 0;
  assert handler.userCredit(user1) == 15;

  // debit (strict)
  // case: credit >= amount
  assert (handler.debitUser(user1, 15)) == true;
  assert handler.journalLength() == inc(1); // #debited
  assert handler.poolCredit() == 15;
  assert handler.userCredit(user1) == 0;

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
  assert handler.ledgerFee() == 5;
  assert handler.minimum(#deposit) == 6;
  assert handler.minimum(#withdrawal) == 6;
  assert handler.journalLength() == inc(5); // #feeUpdated, #depositFeeUpdated, #withdrawalFeeUpdated, #depositMinimumUpdated, #withdrawalMinimumUpdated

  // deposit from allowance < amount
  await ledger.mock.set_transfer_from_res([#Err(#InsufficientAllowance({ allowance = 8 }))]);
  assert (await* handler.depositFromAllowance(user1_account, 9)) == #err(#InsufficientAllowance({ allowance = 8 }));
  assert state(handler) == (0, 0, 0);
  assert handler.journalLength() == inc(1); // #consolidationError
  print("tree lookups = " # debug_show handler.lookups_());

  // deposit from allowance >= amount
  await ledger.mock.set_transfer_from_res([#Ok 42]);
  assert (await* handler.depositFromAllowance(user1_account, 8)) == #ok(3);
  assert handler.userCredit(user1) == 3;
  assert state(handler) == (0, 3, 0);
  assert handler.journalLength() == inc(3); // #consolidated, #newDeposit, #credited
  print("tree lookups = " # debug_show handler.lookups_());

  // deposit from allowance < minimum
  await ledger.mock.set_transfer_from_res([#Ok 42]); // should be not called
  var transfer_from_count = await ledger.mock.transfer_from_count();
  assert (await* handler.depositFromAllowance(user1_account, 5)) == #err(#TooLowQuantity);
  assert handler.userCredit(user1) == 3; // not changed
  assert state(handler) == (0, 3, 0); // not changed
  assert transfer_from_count == (await ledger.mock.transfer_from_count());
  assert handler.journalLength() == inc(0);
  print("tree lookups = " # debug_show handler.lookups_());

  // ledger fee is increased while deposit from allowance is underway
  // old_fee < new_fee < amount
  await ledger.mock.lock_transfer_from("LEDGER_FEE_IS_INCREASED_WHILE_DEPOSIT_FROM_ALLOWANCE_IS_UNDERWAY_1");
  transfer_from_count := await ledger.mock.transfer_from_count();
  let f1 = async { await* handler.depositFromAllowance(user1_account, 8) };
  await ledger.mock.set_fee(6);
  await ledger.mock.set_transfer_from_res([#Err(#BadFee { expected_fee = 6 }), #Ok 42]);
  await ledger.mock.release_transfer_from();
  assert (await f1) == #ok(2);
  assert handler.userCredit(user1) == 5;
  assert state(handler) == (0, 5, 0);
  assert transfer_from_count + 2 == (await ledger.mock.transfer_from_count());
  // #feeUpdated, #depositMinimumUpdated, #withdrawalMinimumUpdated
  // #depositFeeUpdated, #withdrawalFeeUpdated, #consolidated
  // #newDeposit, #credited
  assert handler.journalLength() == inc(8);
  print("tree lookups = " # debug_show handler.lookups_());

  // ledger fee is increased while deposit from allowance is underway
  // old_fee < amount < new_fee
  await ledger.mock.lock_transfer_from("LEDGER_FEE_IS_INCREASED_WHILE_DEPOSIT_FROM_ALLOWANCE_IS_UNDERWAY_2");
  transfer_from_count := await ledger.mock.transfer_from_count();
  let f2 = async { await* handler.depositFromAllowance(user1_account, 8) };
  await ledger.mock.set_fee(9);
  await ledger.mock.set_transfer_from_res([#Err(#BadFee { expected_fee = 9 })]);
  await ledger.mock.release_transfer_from();
  assert (await f2) == #err(#TooLowQuantity);
  assert handler.userCredit(user1) == 5; // unchanged
  assert state(handler) == (0, 5, 0); // unchanged
  assert transfer_from_count + 1 == (await ledger.mock.transfer_from_count());
  // #feeUpdated, #depositMinimumUpdated, #withdrawalMinimumUpdated
  // #depositFeeUpdated, #withdrawalFeeUpdated, #consolidationError
  assert handler.journalLength() == inc(6);
  print("tree lookups = " # debug_show handler.lookups_());

  // ledger fee is decreased while deposit from allowance is underway
  // new_fee < old_fee < amount
  await ledger.mock.lock_transfer_from("LEDGER_FEE_IS_DECREASED_WHILE_DEPOSIT_FROM_ALLOWANCE_IS_UNDERWAY");
  transfer_from_count := await ledger.mock.transfer_from_count();
  let f3 = async { await* handler.depositFromAllowance(user1_account, 10) };
  await ledger.mock.set_fee(8);
  await ledger.mock.set_transfer_from_res([#Err(#BadFee { expected_fee = 8 }), #Ok 42]);
  await ledger.mock.release_transfer_from();
  assert (await f3) == #ok(1); // amount - old_fee
  assert handler.userCredit(user1) == 6;
  assert state(handler) == (0, 6, 0);
  assert transfer_from_count + 2 == (await ledger.mock.transfer_from_count());
  // #feeUpdated, #depositMinimumUpdated, #withdrawalMinimumUpdated
  // #depositFeeUpdated, #withdrawalFeeUpdated, #consolidated
  // #newDeposit, #credited
  assert handler.journalLength() == inc(8);
  print("tree lookups = " # debug_show handler.lookups_());

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
  assert handler.ledgerFee() == 5;
  assert handler.journalLength() == inc(5); // #feeUpdated, #depositFeeUpdated, #withdrawalFeeUpdated, #depositMinimumUpdated, #withdrawalMinimumUpdated

  // notify with 0 balance
  await ledger.mock.set_balance(0);
  assert (await* handler.notify(user1)) == ?(0, 0);
  print("tree lookups = " # debug_show handler.lookups_());

  // pause notifications
  handler.pauseNotifications();

  // notify with 0 balance
  assert (await* handler.notify(user1)) == null;
  print("tree lookups = " # debug_show handler.lookups_());

  // unpause notifications
  handler.unpauseNotifications();

  // notify with 0 balance
  assert (await* handler.notify(user1)) == ?(0, 0);
  print("tree lookups = " # debug_show handler.lookups_());

  handler.assertIntegrity();
  assert not handler.isFrozen();
};
