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
  print("new test");
  assert ledger.transfer_.isEmpty();
  // fresh handler
  let handler = TokenHandler.TokenHandler(ledger, anon_p, 1000, 0);
  // give user1 20 credits
  handler.credit(user1, 20);
  // stage two responses
  let (release, state) = ledger.transfer_.stage(?(#Err(#BadFee { expected_fee = 10 })));
  assert handler.fee() == 0;
  // start withdrawal and move it to background task
  let fut = async { 
    await* handler.withdraw({ owner = user1; subaccount = null}, 10); 
  };
  assert handler.totalWithdrawn() == 0; // background task hasn't started yet
  assert state() == #staged;
  await async {};
  assert handler.totalWithdrawn() == 10; // background task has started
  assert state() == #running; // why has this changed already?
  release();
  await async {}; // loop needs to finish
  assert state() == #ready;
  await async {}; // caller needs to resume the continuation (because target has an async interface, not needed with async* interface)
  assert handler.fee() == 10;
  assert handler.totalWithdrawn() == 0;
  // Note: handler fee is already updated
  // we do not have to await fut
  assert (await fut) == #err(#TooLowQuantity);
};

do {
  print("new test");
  assert ledger.transfer_.isEmpty();
  // fresh handler
  let handler = TokenHandler.TokenHandler(ledger, anon_p, 1000, 0);
  // give user1 20 credits
  handler.credit(user1, 20);
  // stage two responses
  let (release1, state1) = ledger.transfer_.stage(?(#Err(#BadFee { expected_fee = 10 })));
  let (release2, state2) = ledger.transfer_.stage(?(#Ok 0));
  assert handler.fee() == 0;
  // start withdrawal and move it to background task
  let fut = async { 
    await* handler.withdraw({ owner = user1; subaccount = null}, 11); 
  };
  release1();
  assert state1() == #staged;
  await async {};
  assert state1() == #ready;
  await async {};
  assert handler.fee() == 10;
  assert state2() == #running;
  release2();
  assert (await fut) == #ok(0,1);
  assert state2() == #ready;
  assert handler.fee() == 10;
};
