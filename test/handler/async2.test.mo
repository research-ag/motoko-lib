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

let release1 = ledger.transfer_.stage(?(#Ok 0));
let fut1 = async { await* handler.trigger() };
// We now need to give mockLedger time to read from the register.
// Unfortunately, inside handler.trigger there is an await statement which delays everything.
await async {};
let release2 = ledger.transfer_.stage(?(#Ok 0));
let fut2 = async { await* handler.trigger() };
release1();
await fut1;
release2();
await fut2;
