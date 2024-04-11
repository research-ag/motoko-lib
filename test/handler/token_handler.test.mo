import Principal "mo:base/Principal";
import Blob "mo:base/Blob";
import Array "mo:base/Array";
import Nat8 "mo:base/Nat8";

import TokenHandler "../../src/TokenHandler";
import MockLedger "./MockLedger";

actor class Agent() = this {
  type Item = {
    account : { owner : Principal; subaccount : ?Blob };
    amount : Nat;
  };

  public func init() : async () {
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

    let fee = 5;

    // Ledger initialization
    let ledger = await MockLedger.MockLedger({
      transfer_fee = fee;
    });

    let ledger_principal = Principal.fromActor(ledger);

    // Handler initialization
    let handler = TokenHandler.TokenHandler(ledger_principal, own_principal, 1000, fee);

    // Credit funds
    ignore handler.credit(sub_principal[0], 100);
    var info0 = handler.info(sub_principal[0]);
    assert info0.credit == 100;

    // Debit funds
    ignore handler.debitStrict(sub_principal[0], 50);
    info0 := handler.info(sub_principal[0]);
    assert info0.credit == 50;

    // Make deposit less than fee
    info0 := handler.info(sub_principal[0]);
    let deposit_1 = 2;
    await ledger.makeDeposit(sub_blob[0], deposit_1);
    var nr0 = await* handler.notify(sub_principal[0]);
    await* handler.processBacklog();
    assert nr0 != null;
    ignore do ? {
      assert (nr0!).0 == deposit_1;
      assert (nr0!).1 == info0.credit;
    };

    // Make deposit greater than fee in result
    let deposit_2 = 5;
    await ledger.makeDeposit(sub_blob[0], deposit_2);
    nr0 := await* handler.notify(sub_principal[0]);
    await* handler.processBacklog();
    assert nr0 != null;
    ignore do ? {
      assert (nr0!).0 == deposit_2;
      assert (nr0!).1 == info0.credit + (deposit_1 + deposit_2 - fee : Int);
    };

    // Assert the token handler is not frozen
    assert not handler.isFrozen();
  };
};

let agent1 = await Agent();

agent1.init();
