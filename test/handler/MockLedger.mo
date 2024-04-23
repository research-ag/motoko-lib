import RBTree "mo:base/RBTree";
import Blob "mo:base/Blob";
import Option "mo:base/Option";
import Principal "mo:base/Principal";
import Nat8 "mo:base/Nat8";

import TokenHandler "../../src/TokenHandler";

actor class MockLedger(
  init : {
    transfer_fee : Nat;
  }
) {

  public type Account = { owner : Principal; subaccount : ?Subaccount };
  public type Subaccount = Blob;
  public type TransferArgs = {
    from_subaccount : ?Subaccount;
    to : Account;
    amount : Nat;
    fee : ?Nat;
    memo : ?Blob;
    created_at_time : ?Nat64;
  };
  public type TransferError = {
    #BadFee : { expected_fee : Nat };
    #BadBurn : { min_burn_amount : Nat };
    #InsufficientFunds : { balance : Nat };
    #TooOld;
    #CreatedInFuture : { ledger_time : Nat64 };
    #Duplicate : { duplicate_of : Nat };
    #TemporarilyUnavailable;
    #GenericError : { error_code : Nat; message : Text };
  };

  var balances : RBTree.RBTree<Subaccount, Nat> = RBTree.RBTree<Subaccount, Nat>(Blob.compare);

  public query func icrc1_fee() : async Nat {
    init.transfer_fee;
  };

  public func icrc1_balance_of(account : Account) : async Nat {
    getBalance(account.subaccount);
  };

  let examplePrincipal = Principal.fromBlob(Blob.fromArray([255 - Nat8.fromNat(100)]));
  let mainSubaccount = TokenHandler.toSubaccount(examplePrincipal);

  func getBalance(sub : ?Subaccount) : Nat {
    Option.getMapped<Subaccount, Nat>(
      sub,
      func(sub : Subaccount) : Nat = Option.get(balances.get(sub), 0),
      Option.get(balances.get(mainSubaccount), 0),
    );
  };

  func putBalance(sub : ?Subaccount, balance : Nat) : () {
    let key = Option.get(sub, mainSubaccount);
    balances.put(key, balance);
  };

  public shared ({}) func icrc1_transfer(transfer : TransferArgs) : async {
    #Ok : Nat;
    #Err : TransferError;
  } {
    let effectiveFee = init.transfer_fee;

    if (Option.get(transfer.fee, effectiveFee) != effectiveFee) {
      return #Err(#BadFee { expected_fee = init.transfer_fee });
    };

    let debitBalance : Nat = getBalance(transfer.from_subaccount);

    if (debitBalance < transfer.amount + effectiveFee) {
      return #Err(#InsufficientFunds { balance = debitBalance });
    };

    putBalance(transfer.from_subaccount, debitBalance - transfer.amount);

    if (transfer.to.subaccount == null) {
      let creditBalance : Nat = getBalance(transfer.to.subaccount);
      putBalance(transfer.to.subaccount, creditBalance + transfer.amount);
    };

    return #Ok(0);
  };

  public func makeDeposit(sub : Subaccount, deposit : Nat) : async () {
    let balance = getBalance(?sub);
    putBalance(?sub, balance + deposit);
  };
};
