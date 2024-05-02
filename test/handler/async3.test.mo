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
// let account = { owner = Principal.fromBlob("1"); subaccount = null };

func create_inc() : (Nat -> Nat, () -> Nat) {
  var ctr = 0;
  func inc(n : Nat) : Nat { ctr += n; ctr };
  (inc, func() { ctr });
};

func assert_state(handler : TokenHandler.TokenHandler, x : (Nat, Nat, Nat)) {
  assert handler.depositedFunds() == x.0;
  assert handler.consolidatedFunds() == x.1;
  assert handler.depositsNumber() == x.2;
};

module Debug {
  public func state(handler : TokenHandler.TokenHandler) {
    print(
      debug_show (
        handler.depositedFunds(),
        handler.consolidatedFunds(),
        handler.depositsNumber(),
      )
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
  let (inc, _) = create_inc();

  // init state
  assert handler.fee() == 0;
  assert handler.journalLength() == 0;

  // update fee first time
  await ledger.mock.set_fee(5);
  ignore await* handler.updateFee();
  assert handler.fee() == 5;
  assert handler.journalLength() == inc(1); // #feeUpdated

  // notify with 0 balance
  await ledger.mock.set_balance(0);
  assert (await* handler.notify(user1)) == ?(0, 0);
  assert_state(handler, (0, 0, 0));
  assert handler.journalLength() == inc(0);
  print("tree lookups = " # debug_show handler.lookups());

  // notify with balance <= fee
  await ledger.mock.set_balance(5);
  assert (await* handler.notify(user1)) == ?(0, 0);
  assert_state(handler, (0, 0, 0));
  assert handler.journalLength() == inc(0);
  print("tree lookups = " # debug_show handler.lookups());

  // notify with balance > fee
  await ledger.mock.set_balance(6);
  assert (await* handler.notify(user1)) == ?(6, 1); // deposit = 6, credit = 1
  assert_state(handler, (6, 0, 1));
  assert handler.journalLength() == inc(2); // #newDeposit, #credited
  print("tree lookups = " # debug_show handler.lookups());

  // increase fee while item still in queue (trigger did not run yet)
  await ledger.mock.set_fee(6);
  ignore await* handler.updateFee();
  assert_state(handler, (0, 0, 0)); // recalculation after fee update
  assert handler.journalLength() == inc(2); // #feeUpdated, #debited
  print("tree lookups = " # debug_show handler.lookups());

  // increase deposit again
  await ledger.mock.set_balance(7);
  assert (await* handler.notify(user1)) == ?(7, 1); // deposit = 7, credit = 1
  assert_state(handler, (7, 0, 1));
  assert handler.journalLength() == inc(2); // #newDeposit, #credited
  print("tree lookups = " # debug_show handler.lookups());

  // increase fee while notify is underway (and item still in queue)
  // scenario 1: old_fee < previous = latest <= new_fee
  // this means no new deposit has happened (latest = previous)
  await ledger.mock.lock_balance("INCREASE_FEE_WHILE_NOTIFY_IS_UNDERWAY_SCENARIO_1");
  let f1 = async { await* handler.notify(user1) }; // would return ?(0, 1) at old fee
  await ledger.mock.set_fee(10); // fee 6 -> 10
  assert_state(handler, (7, 0, 1)); // state from before
  ignore await* handler.updateFee();
  assert handler.journalLength() == inc(2); // #feeUpdated, #debited
  assert_state(handler, (0, 0, 0)); // state changed
  await ledger.mock.release_balance(); // let notify return
  assert (await f1) == ?(0, 0); // deposit <= new fee
  assert handler.journalLength() == inc(0);
  print("tree lookups = " # debug_show handler.lookups());

  // increase deposit again
  await ledger.mock.set_balance(15);
  assert (await* handler.notify(user1)) == ?(15, 5); // deposit = 15, credit = 5
  assert_state(handler, (15, 0, 1));
  assert handler.journalLength() == inc(2); // #newDeposit, #credited
  print("tree lookups = " # debug_show handler.lookups());

  // increase fee while notify is underway (and item still in queue)
  // scenario 2: old_fee < previous <= new_fee < latest
  await ledger.mock.set_balance(20);
  await ledger.mock.lock_balance("INCREASE_FEE_WHILE_NOTIFY_IS_UNDERWAY_SCENARIO_2");
  let f2 = async { await* handler.notify(user1) }; // would return ?(5, 10) at old fee
  await ledger.mock.set_fee(15); // fee 10 -> 15
  assert_state(handler, (15, 0, 1)); // state from before
  ignore await* handler.updateFee();
  assert handler.journalLength() == inc(2); // #feeUpdated, #debited
  assert_state(handler, (0, 0, 0)); // state changed
  await ledger.mock.release_balance(); // let notify return
  assert (await f2) == ?(20, 5); // credit = latest - new_fee
  assert_state(handler, (20, 0, 1)); // state should have changed
  assert handler.journalLength() == inc(2); // #newDeposit, #credited
  print("tree lookups = " # debug_show handler.lookups());

  // decrease fee while notify is underway (and item still in queue)
  // new_fee < old_fee < previous == latest
  await ledger.mock.lock_balance("DECREASE_FEE_WHILE_NOTIFY_IS_UNDERWAY");
  let f3 = async { await* handler.notify(user1) }; // would return ?(0, 5) at old fee
  await ledger.mock.set_fee(10); // fee 15 -> 10
  assert_state(handler, (20, 0, 1)); // state from before
  ignore await* handler.updateFee();
  assert handler.journalLength() == inc(2); // #feeUpdated, #credited
  assert_state(handler, (20, 0, 1)); // state unchanged
  await ledger.mock.release_balance(); // let notify return
  assert (await f3) == ?(0, 10); // credit increased
  assert_state(handler, (20, 0, 1)); // state unchanged
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
  assert_state(handler, (20, 0, 1)); // state unchanged because deposit has not changed
  assert handler.journalLength() == inc(0);
  print("tree lookups = " # debug_show handler.lookups());
};
