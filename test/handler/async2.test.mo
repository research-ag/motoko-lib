import Principal "mo:base/Principal";
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

// release first response
release1();
ignore (await fut1) == 5;
