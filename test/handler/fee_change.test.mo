import Principal "mo:base/Principal";
import Blob "mo:base/Blob";
import Array "mo:base/Array";
import Nat8 "mo:base/Nat8";
import Debug "mo:base/Debug";

import TokenHandler "../../src/TokenHandler";
import MockLedger "./MockLedger";

actor class TestActor() = this {

  public func runTest() : async () {
    let own_principal = Principal.fromActor(this);

    let n = 10;

    let sub_principal = Array.tabulate<Principal>(
      n,
      func(i) = Principal.fromBlob(Blob.fromArray([255 - Nat8.fromNat(i)])),
    );

    let sub_blob = Array.tabulate<Blob>(
      n,
      func(i) = TokenHandler.toSubaccount(sub_principal[i]),
    );

    let ledger_fee = 6;
    let handler_initial_fee = 5;

    // Ledger initialization
    let ledger = await MockLedger.MockLedger({
      transfer_fee = ledger_fee;
    });

    let ledger_principal = Principal.fromActor(ledger);

    // Handler initialization
    let handler = TokenHandler.TokenHandler(ledger_principal, own_principal, 1000, handler_initial_fee);

    var test_principal = sub_principal[0];
    var test_blob = sub_blob[0];

    // Make deposit <= ledger_fee
    let initialCredit = handler.balance(test_principal);
    Debug.print(debug_show initialCredit);
    let deposit_1 = 6;
    await ledger.makeDeposit(test_blob, deposit_1);
    var nr = await* handler.notify(test_principal);
    Debug.print(debug_show nr);
    assert nr != null;
    ignore do ? {
      assert (nr!).0 == 6;
      assert (nr!).1 == 1;
    };
    await* handler.trigger();
    Debug.print(debug_show handler.info(test_principal));
    Debug.print(debug_show handler.fee());
    Debug.print(debug_show handler.depositedFunds());
    var info = handler.info(test_principal);
    assert info.deposit == 0;
    assert handler.depositedFunds() == 0;
  };
};

let test_actor = await TestActor();

test_actor.runTest();
