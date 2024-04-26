import Debug "mo:base/Debug";
import Principal "mo:base/Principal";
import Error "mo:base/Error";
import Option "mo:base/Option";
import TokenHandler "../../src/TokenHandler";
import ICRC1 "../../src/TokenHandler/ICRC1";

class Response<T>(response_ : ?T) {
  var lock = true;

  public func run() : async* () {
    var inc = 100;
    while (lock and inc > 0) {
      await async {};
      inc -= 1;
    };
    if (Option.isNull(response_)) {
      throw Error.reject("");
    };
  };

  public func response() : T {
    let ?x = response_ else Debug.trap("wrong use. always call run before response.");
    x;
  };

  public func release() {
    assert lock;
    lock := false;
  };
};

type ReleaseFunc = () -> ();

let mockLedger = object {
  public var fee_register : ?Response<Nat> = null;
  public var balance_register : ?Response<Nat> = null;
  public var transfer_register : ?Response<ICRC1.TransferResult> = null;

  public func next_response(arg : { #fee : ?Nat; #transfer : ?Nat; #balance : ?Nat }) : ReleaseFunc {
    switch (arg) {
      case (#fee r) {
        let response = Response<Nat>(r);
        fee_register := ?response;
        response.release;
      };
      case (#transfer r) {
        let response = Response<ICRC1.TransferResult>(do ? { #Ok(r!) });
        transfer_register := ?response;
        response.release;
      };
      case (#balance r) {
        let response = Response<Nat>(r);
        balance_register := ?response;
        response.release;
      };
    };
  };

  public shared func transfer(_ : ICRC1.TransferArgs) : async ICRC1.TransferResult {
    let ?r = transfer_register else Debug.trap("transfer_register not set");
    transfer_register := null;
    await* r.run();
    r.response();
  };

  public shared func balance_of(_ : ICRC1.Account) : async Nat {
    let ?r = balance_register else Debug.trap("balance_register not set");
    balance_register := null;
    await* r.run();
    r.response();
  };

  public shared func fee() : async Nat {
    let ?r = fee_register else Debug.trap("fee_register not set");
    fee_register := null;
    await* r.run();
    r.response();
  };
};

let anon_p = Principal.fromBlob("");
let ledgerApi : ICRC1.LedgerAPI = {
  fee = mockLedger.fee;
  balance_of = mockLedger.balance_of;
  transfer = mockLedger.transfer;
};
let handler = TokenHandler.TokenHandler(ledgerApi, anon_p, anon_p, 1000, 0);

let release1 = mockLedger.next_response(#transfer(?0));
let fut1 = async { await* handler.trigger() };
// We now need to give mockLedger time to read from the register.
// Unfortunately, inside handler.trigger there is an await statement which delays everything. 
await async {}; 
let release2 = mockLedger.next_response(#transfer(?0));
let fut2 = async { await* handler.trigger() };
release1();
await fut1;
release2();
