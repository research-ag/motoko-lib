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
    let r = fee_.pop(); await* r.run(); r.response();
  };
  public shared func balance_of(_ : ICRC1.Account) : async Nat {
    let r = balance_.pop(); await* r.run(); r.response();
  };
  public shared func transfer(_ : ICRC1.TransferArgs) : async ICRC1.TransferResult {
    let r = transfer_.pop(); await* r.run(); r.response();
  };
};

let anon_p = Principal.fromBlob("");
let handler = TokenHandler.TokenHandler(ledger, anon_p, 1000, 0);
var journalCtr = 0;
func inc(n : Nat) : Nat { journalCtr += n; journalCtr };

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

// stage a response
let release1 = ledger.fee_.stage(?5).0;
// stage a second response
let release2 = ledger.fee_.stage(?10).0;
// trigger call
let fut1 = async { await* handler.updateFee() };
// trigger second call
let fut2 = async { await* handler.updateFee() };

// release second response first
release2();
assert (await fut2) == 10;
assert handler.journalLength() == inc(1); // #feeUpdate

// release first response second
release1();
assert (await fut1) == 5;
assert handler.journalLength() == inc(1); // #feeUpdate

let user1 = Principal.fromBlob("1");
func assert_state(x : (Nat, Nat, Nat)) {
  assert handler.depositedFunds() == x.0;
  assert handler.consolidatedFunds() == x.1;
  assert handler.depositsNumber() == x.2;
};

do {
  // stage a response and release it immediately
  ledger.balance_.stage(?20).0();
  assert (await* handler.notify(user1)) == ?(20, 15); // (deposit, credit)
  assert handler.journalLength() == inc(2); // #credited, #newDeposit
  assert_state(20, 0, 1);
  ledger.transfer_.stage(null).0(); // error response
  await* handler.trigger();
  assert handler.journalLength() == inc(1); // #consolidationError
  assert_state(20, 0, 1);
  ledger.transfer_.stage(?(#Ok 0)).0();
  await* handler.trigger();
  assert_state(0, 15, 0);
};

do {
  print("new test: withdrawal error");
  assert ledger.transfer_.isEmpty();
  // fresh handler
  let handler = TokenHandler.TokenHandler(ledger, anon_p, 1000, 0);
  var journalCtr = 0;
  func inc(n : Nat) : Nat { journalCtr += n; journalCtr };
  // give user1 20 credits
  handler.credit(user1, 20);
  assert handler.journalLength() == inc(1); // #credited
  // stage a response
  let (release, state) = ledger.transfer_.stage(?(#Err(#BadFee { expected_fee = 10 })));
  assert handler.fee() == 0;
  // start withdrawal and move it to background task
  var has_started = false;
  let fut = async { 
    has_started := true;
    await* handler.withdraw({ owner = user1; subaccount = null}, 10); 
  };
  // we wait for background task to start
  // this can also be done with a single await async {} statement
  // the loop seems more robust but is normally not necessary
  while (not has_started) { await async {} }; 
  // now the withdraw call has executed until its first commit point
  // let's verify
  assert handler.totalWithdrawn() == 10;
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
  assert handler.fee() == 10; // #BadFee has been processed
  // because of the #TooLowQuantity error there is no further commit point
  // the continuation runs to the end of the withdraw function 
  // let's verify
  assert handler.totalWithdrawn() == 0;
  assert handler.journalLength() == inc(2); // feeUpdated, withdrawalError
  // we do not have to await fut anymore, but we can:
  assert (await fut) == #err(#TooLowQuantity);
};

do {
  print("new test: successful withdrawal");
  assert ledger.transfer_.isEmpty();
  // fresh handler
  let handler = TokenHandler.TokenHandler(ledger, anon_p, 1000, 0);
  var journalCtr = 0;
  func inc(n : Nat) : Nat { journalCtr += n; journalCtr };
  // give user1 20 credits
  handler.credit(user1, 20);
  assert handler.journalLength() == inc(1); // #credited
  // stage two responses
  let (release, state) = ledger.transfer_.stage(?(#Err(#BadFee { expected_fee = 10 })));
  let (release2, state2) = ledger.transfer_.stage(?(#Ok 0));
  assert handler.fee() == 0;
  // start withdrawal and move it to background task
  let fut = async { 
    await* handler.withdraw({ owner = user1; subaccount = null}, 11); 
  };
  // we wait for the response to be processed
  release();
  while (state() != #ready) { await async {} }; 
  await async {};
  // now the continuation in the withdraw call has executed to the second commit point
  // let's verify
  assert handler.fee() == 10; // #BadFee has been processed
  assert handler.journalLength() == inc(1); // feeUpdated
  // now everything is halted until we release the second response
  // we wait for the second response to be processed
  release2();
  while (state2() != #ready) { await async {} }; 
  await async {};
  // now the second contination has executed and withdraw has run to the end
  // let's verify
  assert handler.journalLength() == inc(1); // #withdraw 
  // we do not have to await fut anymore, but we can:
  assert (await fut) == #ok (0,1);
};