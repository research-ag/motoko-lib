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
    let r = fee_.read(); await* r.run(); r.response();
  };
  public shared func balance_of(_ : ICRC1.Account) : async Nat {
    let r = balance_.read(); await* r.run(); r.response();
  };
  public shared func transfer(_ : ICRC1.TransferArgs) : async ICRC1.TransferResult {
    let r = transfer_.read(); await* r.run(); r.response();
  };
};

let anon_p = Principal.fromBlob("");
let handler = TokenHandler.TokenHandler(ledger, anon_p, 1000, 0);

var journalCtr = 0;
func inc(n : Nat) : Bool { 
  journalCtr += n;
  journalCtr == handler.state().journalLength 
};

module Debug {
  public func state() {
    print(
      debug_show handler.state());
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
let release1 = ledger.fee_.stage(?5);
// trigger call
let fut1 = async { await* handler.updateFee() };
// wait for staged response to be picked up
// (necessary before a second response can be staged)
await ledger.transfer_.clear();

// stage a second response
let release2 = ledger.fee_.stage(?10);
// trigger call
let fut2 = async { await* handler.updateFee() };

// release second response
release2();
assert (await fut2) == 10;
assert inc(1); // #feeUpdate

// release first response
release1();
assert (await fut1) == 5;
assert inc(1); // #feeUpdate

let user1 = Principal.fromBlob("1");
func assert_state(x : (Nat, Nat, Nat)) {
  let s = handler.state();
  assert s.balance.deposited == x.0;
  assert s.balance.consolidated == x.1;
  assert s.users.queued == x.2;
};

do {
  // stage a response and release it immediately
  ledger.balance_.stage(?20)();
  assert (await* handler.notify(user1)) == ?(20, 15); // (deposit, credit)
  assert inc(2); // #credited, #newDeposit
  assert_state(20, 0, 1);
  ledger.transfer_.stage(null)(); // error response
  await* handler.trigger();
  assert inc(3); // #consolidationError, #debited, #credited
  assert_state(20, 0, 1);
  ledger.transfer_.stage(?(#Ok 0))();
  await* handler.trigger();
  assert_state(0, 15, 0);
};
