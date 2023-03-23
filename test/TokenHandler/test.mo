import Cycles "mo:base/ExperimentalCycles";
import TokenHandler "../../src/TokenHandler";
import Ledger "ICRC1";
import Principal "mo:base/Principal";
import Blob "mo:base/Blob";
import Array "mo:base/Array";
import Nat8 "mo:base/Nat8";

actor TestActor {
  type I = {
    account : { owner : Principal; subaccount : ?Blob };
    amount : Nat;
  };
  public shared func init() : async () {
    let own_principal = Principal.fromActor(TestActor);

    let n = 10;
    let a = Array.init<Nat8>(32, 0);
    let sub_blob = Array.tabulate<Blob>(
      n,
      func(i) {
        a[0] := 255 - Nat8.fromNat(i);
        Blob.fromArrayMut(a);
      },
    );
    let sub_principal = Array.tabulate<Principal>(n, func(i) = Principal.fromBlob(sub_blob[i]));

    let fee = 1;
    let anonymous = Principal.fromText("2vxsx-fae");

    Cycles.add(100_000_000_000);
    let ledger = await Ledger.Ledger({
      initial_mints = Array.tabulate<I>(
        n,
        func(i) = {
          account = {
            owner = own_principal;
            subaccount = ?sub_blob[i];
          };
          amount = 100 * i;
        },
      );
      minting_account = { owner = anonymous; subaccount = null };
      token_name = "ABC";
      token_symbol = "abc";
      decimals = 0;
      transfer_fee = fee;
    });

    let ledger_principal = Principal.fromActor(ledger);

    let handler = TokenHandler.TokenHandler(ledger_principal, own_principal, fee);

    handler.credit(sub_principal[0], 100);
    handler.credit(sub_principal[1], 100);
    handler.credit(sub_principal[2], 100);

    await* handler.notify(sub_principal[0]);
    await* handler.notify(sub_principal[1]);
    await* handler.notify(sub_principal[2]);
  };
};
