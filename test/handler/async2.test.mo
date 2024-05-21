import Principal "mo:base/Principal";
import { print } "mo:base/Debug";
import TokenHandler "../../src/TokenHandler";
import ICRC1 "../../src/TokenHandler/ICRC1";
import Mock "mock";

let ledger = object {
  public let fee_ = Mock.Method<Nat>();
  public let balance_ = Mock.Method<Nat>();
  public let transfer_ = Mock.Method<ICRC1.TransferResult>();
  public let transfer_from_ = Mock.Method<ICRC1.TransferFromResult>();
  public shared func fee() : async Nat {
    let r = fee_.pop();
    await* r.run();
    r.response();
  };
  public shared func balance_of(_ : ICRC1.Account) : async Nat {
    let r = balance_.pop();
    await* r.run();
    r.response();
  };
  public shared func transfer(_ : ICRC1.TransferArgs) : async ICRC1.TransferResult {
    let r = transfer_.pop();
    await* r.run();
    r.response();
  };
  public shared func transfer_from(_ : ICRC1.TransferFromArgs) : async ICRC1.TransferFromResult {
    let r = transfer_from_.pop();
    await* r.run();
    r.response();
  };
  public func isEmpty() : Bool {
    fee_.isEmpty() and balance_.isEmpty() and transfer_.isEmpty();
  };
};
let anon_p = Principal.fromBlob("");
let user1 = Principal.fromBlob("1");

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
  print("new test: change fee plus notify");
  // fresh handler
  let handler = TokenHandler.TokenHandler(ledger, anon_p, 1000, 0);
  let (inc, _) = create_inc();
  // stage a response
  let (release, status) = ledger.fee_.stage(?5);
  // trigger call
  let fut1 = async { await* handler.fetchFee() };
  // wait for call to arrive
  while (status() == #staged) await async {};
  // trigger second call
  assert (await* handler.fetchFee()) == null;
  // release response
  release();
  assert (await fut1) == ?5;
  assert handler.journalLength() == inc(5); // #minimumUpdated, #depositFeeUpdated, #withdrawalFeeUpdated, #minimumWithdrawalUpdated, #feeUpdated

  // stage a response and release it immediately
  ledger.balance_.stage(?20).0 ();
  assert (await* handler.notify(user1)) == ?(20, 15); // (deposit, credit)
  assert handler.journalLength() == inc(2); // #credited, #newDeposit
  assert state(handler) == (20, 0, 1);
  ledger.transfer_.stage(null).0 (); // error response
  await* handler.trigger();
  assert handler.journalLength() == inc(3); // #consolidationError, #debited, #credited
  assert state(handler) == (20, 0, 1);
  ledger.transfer_.stage(?(#Ok 0)).0 ();
  await* handler.trigger();
  assert handler.journalLength() == inc(1); // #credited
  assert state(handler) == (0, 15, 0);
};

do {
  print("new test: withdrawal error");
  // make sure no staged responses are left from previous tests
  assert ledger.isEmpty();
  // fresh handler
  let handler = TokenHandler.TokenHandler(ledger, anon_p, 1000, 0);
  let (inc, _) = create_inc();
  // giver user1 credit and put funds into the consolidated balance
  ledger.balance_.stage(?20).0 ();
  ledger.transfer_.stage(?(#Ok 0)).0 ();
  assert (await* handler.notify(user1)) == ?(20, 20); // (deposit, credit)
  assert handler.journalLength() == inc(2); // #credited, #newDeposit
  await* handler.trigger();
  assert handler.journalLength() == inc(1); // #consolidated
  // stage a response
  let (release, state) = ledger.transfer_.stage(?(#Err(#BadFee { expected_fee = 10 })));
  assert handler.fee(#deposit) == 0;
  // transfer 20 credits from user to pool
  assert handler.debitUser(user1, 20);
  assert handler.journalLength() == inc(1); // debited
  // start withdrawal and move it to background task
  var has_started = false;
  let fut = async {
    has_started := true;
    await* handler.withdrawFromPool({ owner = user1; subaccount = null }, 10);
  };
  // we wait for background task to start
  // this can also be done with a single await async {} statement
  // the loop seems more robust but is normally not necessary
  while (not has_started) { await async {} };
  // now the withdraw call has executed until its first commit point
  // let's verify
  assert handler.state().flow.withdrawn == 10;
  // also the call to the mock ledger method has been made
  assert state() == #running;
  // now everything is halted until we release the response
  release();
  // we wait for loop to finish until the response is ready
  while (state() == #running) { await async {} };
  assert state() == #ready;
  // the ledger has an async interface (not async*)
  // hence one more wait is required before the caller resumes the continuation
  // this cannot be done in a different way
  // there is nothing specific that we can wait for in a while loop
  await async {};
  // now the continuation in the withdraw call has executed
  // let's verify
  assert handler.fee(#deposit) == 10; // #BadFee has been processed
  // because of the #TooLowQuantity error there is no further commit point
  // the continuation runs to the end of the withdraw function
  // let's verify
  assert handler.state().flow.withdrawn == 0;
  assert handler.journalLength() == inc(8); // burned, feeUpdated, depositMinimumUpdated, withdrawalMinimumUpdated, depositFeeUpdated, withdrawalFeeUpdated, withdrawalError, , issued
  // we do not have to await fut anymore, but we can:
  assert (await fut) == #err(#TooLowQuantity);
};

do {
  print("new test: successful withdrawal");
  // make sure no staged responses are left from previous tests
  assert ledger.isEmpty();
  // fresh handler
  let handler = TokenHandler.TokenHandler(ledger, anon_p, 1000, 0);
  let (inc, _) = create_inc();
  // give user1 20 credits
  handler.issue_(#user user1, 20);
  assert handler.journalLength() == inc(1); // #credited
  // stage two responses
  let (release, state) = ledger.transfer_.stage(?(#Err(#BadFee { expected_fee = 10 })));
  let (release2, state2) = ledger.transfer_.stage(?(#Ok 0));
  assert handler.fee(#deposit) == 0;
  // transfer 20 credits from user to pool
  assert handler.debitUser(user1, 20);
  assert handler.journalLength() == inc(1); // debited
  // start withdrawal and move it to background task
  let fut = async {
    await* handler.withdrawFromPool({ owner = user1; subaccount = null }, 11);
  };
  // we wait for the response to be processed
  release();
  while (state() != #ready) { await async {} };
  await async {};
  // now the continuation in the withdraw call has executed to the second commit point
  // let's verify
  assert handler.fee(#deposit) == 10; // #BadFee has been processed
  //assert handler.journalLength() == inc(5); // feeUpdated, #depositFeeUpdated, #withdrawalFeeUpdated, depositMinimumUpdated, withdrawalMinimumUpdated
  assert handler.journalLength() == inc(6); // burned, feeUpdated, depositMinimumUpdated, withdrawalMinimumUpdated, depositFeeUpdated, withdrawalFeeUpdated
  // now everything is halted until we release the second response
  // we wait for the second response to be processed
  release2();
  while (state2() != #ready) { await async {} };
  await async {};
  // now the second contination has executed and withdraw has run to the end
  // let's verify
  assert handler.journalLength() == inc(1); // #withdraw
  // we do not have to await fut anymore, but we can:
  assert (await fut) == #ok(0, 1);
};
