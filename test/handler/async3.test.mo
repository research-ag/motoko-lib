import Principal "mo:base/Principal";
import { print } "mo:base/Debug";
import TokenHandler "../../src/TokenHandler";
import ICRC1 "../../src/TokenHandler/ICRC1";
import Mock "mock";

let ledger = object {
  public let fee_ = Mock.Method<Nat>();
  public let balance_ = Mock.Method<Nat>();
  public let transfer_ = Mock.Method<ICRC1.TransferResult>();
  public shared func fee() : async Nat {
    let r = fee_.read();
    await* r.run();
    r.response();
  };
  public shared func balance_of(_ : ICRC1.Account) : async Nat {
    let r = balance_.read();
    await* r.run();
    r.response();
  };
  public shared func transfer(_ : ICRC1.TransferArgs) : async ICRC1.TransferResult {
    let r = transfer_.read();
    await* r.run();
    r.response();
  };
};

let anon_p = Principal.fromBlob("");
let user1 = Principal.fromBlob("1");
// let account = { owner = Principal.fromBlob("1"); subaccount = null };

func create_inc() : (Nat -> Nat, () -> Nat) {
  var journalCtr = 0;
  func inc(n : Nat) : Nat { journalCtr += n; journalCtr };
  (inc, func() { journalCtr });
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
  ledger.fee_.stage(?5)();
  ignore await* handler.updateFee();
  assert handler.fee() == 5;
  assert handler.journalLength() == inc(1); // #feeUpdated

  // notify with 0 balance
  ledger.balance_.stage(?5)();
  assert (await* handler.notify(user1)) == ?(0, 0);
  assert_state(handler, (0, 0, 0));
  assert handler.journalLength() == inc(0);
  print("tree lookups = " # debug_show handler.lookups());

  // notify with balance <= fee
  ledger.balance_.stage(?5)();
  assert (await* handler.notify(user1)) == ?(0, 0);
  assert_state(handler, (0, 0, 0));
  assert handler.journalLength() == inc(0);
  print("tree lookups = " # debug_show handler.lookups());

  // notify with balance > fee
  ledger.balance_.stage(?6)();
  assert (await* handler.notify(user1)) == ?(6, 1); // deposit = 6, credit = 1
  assert_state(handler, (6, 0, 1));
  assert handler.journalLength() == inc(2); // #newDeposit, #credited
  print("tree lookups = " # debug_show handler.lookups());

  // increase fee while item still in queue (trigger did not run yet)
  ledger.fee_.stage(?6)();
  ignore await* handler.updateFee();
  assert_state(handler, (0, 0, 0)); // recalculation after fee update
  assert handler.journalLength() == inc(2); // #feeUpdated, #debited
  print("tree lookups = " # debug_show handler.lookups());

  // increase deposit again
  ledger.balance_.stage(?7)();
  assert (await* handler.notify(user1)) == ?(7, 1); // deposit = 7, credit = 1
  assert_state(handler, (7, 0, 1));
  assert handler.journalLength() == inc(2); // #newDeposit, #credited
  print("tree lookups = " # debug_show handler.lookups());

  // increase fee while notify is underway (and item still in queue)
  // scenario 1: old_fee < previous = latest <= new_fee
  // this means no new deposit has happened (latest = previous)
  let release1 = ledger.balance_.stage(?7);
  let f1 = async { await* handler.notify(user1) }; // would return ?(0,1) at old fee
  ledger.fee_.stage(?10)(); // fee 6 -> 10
  assert_state(handler, (7, 0, 1)); // state from before
  ignore await* handler.updateFee();
  assert handler.journalLength() == inc(2); // #feeUpdated, #debited
  assert_state(handler, (0, 0, 0)); // state changed
  release1(); // let notify return
  assert (await f1) == ?(0, 0); // deposit <= new fee
  assert handler.journalLength() == inc(0);
  print("tree lookups = " # debug_show handler.lookups());

  // increase deposit again
  ledger.balance_.stage(?15)();
  assert (await* handler.notify(user1)) == ?(15, 5); // deposit = 15, credit = 5
  assert_state(handler, (15, 0, 1));
  assert handler.journalLength() == inc(2); // #newDeposit, #credited
  print("tree lookups = " # debug_show handler.lookups());

  // increase fee while notify is underway (and item still in queue)
  // scenario 2: old_fee < previous <= new_fee < latest
  let release2 = ledger.balance_.stage(?20);
  let f2 = async { await* handler.notify(user1) }; // would return ?(5, 10) at old fee
  ledger.fee_.stage(?15)(); // fee 10 -> 15
  assert_state(handler, (15, 0, 1)); // state from before
  ignore await* handler.updateFee();
  assert handler.journalLength() == inc(2); // #feeUpdated, #debited
  assert_state(handler, (0, 0, 0)); // state changed
  release2(); // let notify return
  assert (await f2) == ?(20, 5); // credit = latest - new_fee
  assert_state(handler, (20, 0, 1)); // state should have changed
  assert handler.journalLength() == inc(2); // #newDeposit, #credited
  print("tree lookups = " # debug_show handler.lookups());

  // decrease fee while notify is underway (and item still in queue)
  // new_fee < old_fee < previous == latest
  let release3 = ledger.balance_.stage(?20);
  let f3 = async { await* handler.notify(user1) }; // would return ?(0, 5) at old fee
  ledger.fee_.stage(?10)(); // fee 15 -> 10
  assert_state(handler, (20, 0, 1)); // state from before
  ignore await* handler.updateFee();
  assert handler.journalLength() == inc(2); // #feeUpdated, #credited
  assert_state(handler, (20, 0, 1)); // state unchanged
  release3(); // let notify return
  assert (await f3) == ?(0, 10); // credit increased
  assert_state(handler, (20, 0, 1)); // state unchanged
  print("tree lookups = " # debug_show handler.lookups());

  // call multiple notify() simultaneously
  // only the first should return state, the rest should not be executed
  let release4 = ledger.balance_.stage(?20);
  let fut1 = async { await* handler.notify(user1) };
  let fut2 = async { await* handler.notify(user1) };
  let fut3 = async { await* handler.notify(user1) };
  assert (await fut2) == null; // should return null
  assert (await fut3) == null; // should return null
  release4(); // let notify return
  assert (await fut1) == ?(0, 10); // first notify() should return state
  assert_state(handler, (20, 0, 1)); // state unchanged because deposit has not changed
  assert handler.journalLength() == inc(0);
  print("tree lookups = " # debug_show handler.lookups());
};

do {
  let handler = TokenHandler.TokenHandler(ledger, anon_p, 1000, 0);
  let (inc, _) = create_inc();

  // update fee
  ledger.fee_.stage(?5)();
  ignore await* handler.updateFee();
  assert handler.fee() == 5;
  assert handler.journalLength() == inc(1); // #feeUpdated

  // increase deposit again
  ledger.balance_.stage(?7)();
  assert (await* handler.notify(user1)) == ?(7, 2); // deposit = 7, credit = 2
  assert_state(handler, (7, 0, 1));
  assert handler.journalLength() == inc(2); // #credited, #newDeposit
  print("tree lookups = " # debug_show handler.lookups());

  // // only 1 consolidation process can be triggered for same user at same time
  // // consolidation with deposit > fee should be successful
  // // TODO
  // // var transfer_count = await ledger.transfer_count();
  // let f3 = async {
  //   ledger.transfer_.stage(? #Ok 42)();
  //   await* handler.trigger();
  //   ledger.balance_.stage(?0)();
  // };
  // let f4 = async {
  //   ledger.transfer_.stage(? #Ok 42)();
  //   await* handler.trigger();
  //   ledger.balance_.stage(?0)();
  // };
  // await f3;
  // await f4;
  // // assert ((await ledger.transfer_count())) == transfer_count + 1; // only 1 transfer call has been made
  // assert_state(handler, (0, 2, 0)); // consolidation successful
  // assert handler.journalLength() == inc(1); // #consolidated
  // assert handler.info(user1).credit == 2; // credit unchanged
  // print("tree lookups = " # debug_show handler.lookups());
};
