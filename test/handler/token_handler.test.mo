import Principal "mo:base/Principal";
import Blob "mo:base/Blob";
import Array "mo:base/Array";
import Nat8 "mo:base/Nat8";
import Int "mo:base/Int";

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

    // Udpate fee
    assert handler.fee() == handler_initial_fee;
    let newFee = await* handler.updateFee();
    assert newFee == ledger_fee;
    assert handler.fee() == ledger_fee;

    // Credit funds
    handler.credit(test_principal, 100);
    assert handler.balance(test_principal) == 100;

    // Debit funds
    ignore handler.debitStrict(test_principal, 70);
    assert handler.balance(test_principal) == 30;

    // Debit too much
    assert handler.debitStrict(test_principal, 31) == false;
    assert handler.balance(test_principal) == 30;

    // Make deposit less than fee
    let initialCredit = handler.balance(test_principal);
    let deposit_1 = 2;
    await ledger.makeDeposit(test_blob, deposit_1);
    var nr = await* handler.notify(test_principal);
    assert nr != null;
    ignore do ? {
      assert (nr!).0 == 2;
      assert (nr!).1 == initialCredit;
    };
    var info = handler.info(test_principal);
    assert info.deposit == 0;
    assert handler.depositedFunds() == 0;
    await* handler.trigger();

    // Make deposit greater than fee in result
    let deposit_2 = 5;
    await ledger.makeDeposit(test_blob, deposit_2);
    nr := await* handler.notify(test_principal);
    assert nr != null;
    ignore do ? {
      assert (nr!).0 == deposit_1 + deposit_2;
      assert (nr!).1 == initialCredit + (deposit_1 + deposit_2 - +handler.fee());
    };
    info := handler.info(test_principal);
    assert info.deposit == deposit_1 + deposit_2;
    assert handler.depositedFunds() == deposit_1 + deposit_2;
    assert handler.totalConsolidated() == 0;
    await* handler.trigger();
    assert handler.totalConsolidated() == (deposit_1 + deposit_2 - +handler.fee());

    // Make deposit for another user
    let prev_test_principal = sub_principal[0];
    test_principal := sub_principal[1];
    test_blob := sub_blob[1];
    let deposit_3 = 100;
    await ledger.makeDeposit(test_blob, deposit_3);
    nr := await* handler.notify(test_principal);
    assert nr != null;
    ignore do ? {
      assert (nr!).0 == deposit_3;
      assert (nr!).1 == (deposit_3 - handler.fee() : Int);
    };
    info := handler.info(test_principal);
    assert info.deposit == deposit_3;
    await* handler.trigger();
    assert handler.creditTotal() == handler.balance(test_principal) + handler.balance(prev_test_principal);
    assert handler.totalConsolidated() == (deposit_1 + deposit_2 - +handler.fee()) + (deposit_3 - +handler.fee());

    // Withdraw
    let random_sub_blob = sub_blob[9];
    let consolidated = handler.consolidatedFunds();
    let w_amount_gross : Nat = consolidated - 50;
    var wr = await* handler.withdraw(
      {
        owner = own_principal;
        subaccount = ?random_sub_blob;
      },
      w_amount_gross,
    );
    var w_amount : Nat = w_amount_gross - handler.fee();
    switch (wr) {
      case (#err(_)) { assert false };
      case (#ok(tx_index, x)) {
        assert wr == #ok((tx_index, Int.abs(w_amount)));
      };
    };
    let new_consolidated = handler.consolidatedFunds();
    assert handler.totalWithdrawn() == w_amount_gross;
    assert new_consolidated == consolidated - +w_amount_gross;
    assert new_consolidated == handler.totalConsolidated() - +handler.totalWithdrawn();

    // Assert the token handler is not frozen
    assert not handler.isFrozen();
  };
};

let test_actor = await TestActor();

test_actor.runTest();
