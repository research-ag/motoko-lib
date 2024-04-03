import Principal "mo:base/Principal";
import Blob "mo:base/Blob";
import Array "mo:base/Array";
import Nat8 "mo:base/Nat8";
import Debug "mo:base/Debug";

import TokenHandler "../../src/TokenHandler";
import Ledger "./Ledger";

actor class Agent() = this {
  type Item = {
    account : { owner : Principal; subaccount : ?Blob };
    amount : Nat;
  };

  func delay() {
    var i = 0;
    while (i < 1_000_000) {
      i += 1;
    };
  };

  func mint(args : { ledger : Ledger.Ledger; minting_sub : Blob; own_principal : Principal; sub_blob : Blob; amount : Nat }) : async* () {
    let { ledger; minting_sub; own_principal; sub_blob; amount } = args;

    ignore await ledger.icrc1_transfer({
      from_subaccount = ?minting_sub;
      to = {
        owner = own_principal;
        subaccount = ?sub_blob;
      };
      amount;
      fee = null;
      memo = null;
      created_at_time = null;
    });
  };

  public func init() : async () {
    let own_principal = Principal.fromActor(this);

    Debug.print("own_principal " # debug_show own_principal);

    let n = 10;

    let sub_principal = Array.tabulate<Principal>(
      n,
      func(i) = Principal.fromBlob(Blob.fromArray([255 - Nat8.fromNat(i)])),
    );

    let sub_blob = Array.tabulate<Blob>(
      n,
      func(i) = TokenHandler.toSubaccount(sub_principal[i]),
    );

    let minting_sub = sub_blob[9];

    let fee = 1;

    // Ledger initialization
    let ledger = await Ledger.Ledger({
      initial_mints = Array.tabulate<Item>(
        n,
        func(i) = {
          account = {
            owner = own_principal;
            subaccount = ?sub_blob[i];
          };
          amount = 100;
        },
      );
      minting_account = { owner = own_principal; subaccount = ?minting_sub };
      token_name = "ABC";
      token_symbol = "ABC";
      decimals = 0;
      transfer_fee = fee;
    });

    let ledger_principal = Principal.fromActor(ledger);

    // Handler initialization
    let handler = TokenHandler.TokenHandler(ledger_principal, own_principal, fee);

    ignore handler.credit(sub_principal[0], 100);

    await* mint({
      ledger;
      minting_sub;
      own_principal;
      sub_blob = sub_blob[0];
      amount = 200;
    });

    // Debug.print("backlogFunds before " # debug_show (handler.backlogFunds()));
    // Debug.print("consolidatedFunds before " # debug_show (handler.consolidatedFunds()));

    ignore await* handler.notify(sub_principal[0]);
    delay();

    // Debug.print("info " # debug_show (handler.info(sub_principal[0])));
    Debug.print("backlogFunds after " # debug_show (handler.backlogFunds()));
    // Debug.print("consolidatedFunds after " # debug_show (handler.consolidatedFunds()));

    // let totalSupply = await ledger.icrc1_total_supply();

    // Debug.print("totalSupply " # debug_show (totalSupply));

    assert true;
  };
};

let agent1 = await Agent();

agent1.init();
