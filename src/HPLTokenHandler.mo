import RBTree "mo:base/RBTree";
import Principal "mo:base/Principal";
import Iter "mo:base/Iter";
import Option "mo:base/Option";
import Int "mo:base/Int";
import AssocList "mo:base/AssocList";
import Blob "mo:base/Blob";
import Nat8 "mo:base/Nat8";
import Array "mo:base/Array";
import List "mo:base/List";
import Time = "mo:base/Time";
import Nat = "mo:base/Nat";
import Text = "mo:base/Text";
import R "mo:base/Result";

import CircularBuffer "CircularBuffer";
import Error "mo:base/Error";

module HPLTokenHandler {

  // https://github.com/research-ag/hpl/#readme
  public module HPL {
    public type AssetId = Nat;
    public type SubaccountId = Nat;
    public type VirtualAccountId = Nat;
    public type Asset = (id : AssetId, quantity : Nat);
    public type Expiration = {
      #None;
      #Timestamp : Nat64;
    };
    public type VirtualAccountState = {
      asset : Asset;
      backingSubaccountId : SubaccountId;
      remotePrincipal : Principal;
      expiration : Expiration;
    };
    public type BalanceUpdate = {
      #Set : Nat;
      #Increment : Nat;
      #Decrement : Nat;
    };
    public type VirtualAccountUpdateObject = {
      backingSubaccountId : ?SubaccountId;
      balance : ?BalanceUpdate;
      expiration : ?Expiration;
    };
    public type TxWithMemos = {
      memo : [Blob];
    };
    public type TxInputV1 = TxWithMemos and {
      map : [ContributionInput];
    };
    public type TxInput = { #v1 : TxInputV1 };
    public type AccountReference = {
      #sub : SubaccountId;
      #vir : (Principal, VirtualAccountId);
    };
    type ContributionBody = {
      inflow : [(AccountReference, Asset)];
      outflow : [(AccountReference, Asset)];
      mints : [Asset];
      burns : [Asset];
    };
    public type ContributionInput = ContributionBody and {
      owner : ?Principal;
    };
    public type GlobalId = (streamId : Nat, queueNumber : Nat);

    public type ProcessingError = {
      #TooLargeAssetId;
      #TooLargeFtQuantity;
      #TooLargeSubaccountId;
      #TooLargeVirtualAccountId;
      #TooLargeMemo;
      #TooManyFlows;
      #TooManyContributions;
      #NonZeroAssetSum;
      #UnknownPrincipal;
      #UnknownSubaccount;
      #UnknownVirtualAccount;
      #DeletedVirtualAccount;
      #UnknownFtAsset;
      #MismatchInAsset;
      #MismatchInRemotePrincipal;
      #InsufficientFunds;
      #NotAController;
    };
    public type SubmitAndExecuteError = ProcessingError or { #NotApproved };
    public type Ledger = actor {
      openVirtualAccount : (state : VirtualAccountState) -> async R.Result<VirtualAccountId, ?{ #UnknownPrincipal; #UnknownSubaccount; #MismatchInAsset; #NoSpaceForAccount; #InvalidExpirationTime }>;
      updateVirtualAccount : (vid : VirtualAccountId, updates : VirtualAccountUpdateObject) -> async R.Result<{ balance : Nat; delta : Int }, ?{ #UnknownPrincipal; #UnknownVirtualAccount; #DeletedVirtualAccount; #UnknownSubaccount; #MismatchInAsset; #InsufficientFunds; #InvalidExpirationTime }>;
      virtualAccount : (vid : VirtualAccountId) -> async R.Result<VirtualAccountState, ?{ #UnknownPrincipal; #UnknownVirtualAccount; #DeletedVirtualAccount }>;
      submitAndExecute : (tx : TxInput) -> async R.Result<(GlobalId, { #ftTransfer : { amount : Nat; fee : Nat } }), ?SubmitAndExecuteError>;
    };
  };

  public func defaultHandlerStableData() : StableData = ([], 0, (0, 0), ([var], 0, 0));

  public type Info = {
    var credit : Nat;
    var virtualAccountId : ?HPL.VirtualAccountId;
  };

  public type StableInfo = {
    credit : Nat;
    virtualAccountId : ?HPL.VirtualAccountId;
  };

  public type JournalRecord = (
    Time.Time,
    Principal,
    {
      #credited : Nat;
      #debited : Nat;
      #error : Any;
      #openAccountError : {
        #UnknownPrincipal;
        #UnknownSubaccount;
        #MismatchInAsset;
        #NoSpaceForAccount;
      };
      #sweepIn : Nat;
      #sweepOut : Nat;
      #withdraw : { to : (Principal, HPL.VirtualAccountId); amount : Nat };
      #deposit : { from : (Principal, HPL.VirtualAccountId); amount : Nat };
    },
  );

  public type StableData = (
    [(Principal, StableInfo)], // map
    Nat, // consolidatedFunds
    (Nat, Nat), // total debited/credited
    ([var ?JournalRecord], Nat, Nat) // journal
  );

  public class TokenHandler(
    hplLedgerPrincipal : Principal,
    assetId : HPL.AssetId,
    backingSubaccountId : HPL.SubaccountId,
    ownPrincipal : Principal,
    journalSize : Nat,
  ) {
    let hpl = actor (Principal.toText(hplLedgerPrincipal)) : HPL.Ledger;

    /// if some unexpected error happened, this flag turns true and handler stops doing anything until recreated
    var isFrozen_ : Bool = false;
    func freezeTokenHandler(errorText : Text) : () {
      isFrozen_ := true;
      journal.push((Time.now(), ownPrincipal, #error(errorText)));
    };

    var journal : CircularBuffer.CircularBuffer<JournalRecord> = CircularBuffer.CircularBuffer<JournalRecord>(journalSize);
    var consolidatedFunds_ : Nat = 0;
    var map : RBTree.RBTree<Principal, Info> = RBTree.RBTree<Principal, Info>(Principal.compare);

    var totalDebited : Nat = 0;
    var totalCredited : Nat = 0;

    func mapGetOrCreate(p : Principal) : Info = switch (map.get(p)) {
      case (?info) info;
      case (null) {
        let info = {
          var virtualAccountId : ?HPL.VirtualAccountId = null;
          var credit = 0;
        };
        map.put(p, info);
        info;
      };
    };

    /// Returns reference to registered virtual account for P.
    /// If not registered yet, registers it automatically
    /// We pass through any call Error instead of catching it
    public func getAccountReferenceFor(p : Principal) : async* (Principal, HPL.VirtualAccountId) {
      let info = mapGetOrCreate(p);
      let virtualAccountId : HPL.VirtualAccountId = switch (info.virtualAccountId) {
        case (?vid) vid;
        case (null) {
          let registerResult = await hpl.openVirtualAccount({
            asset = (assetId, 0);
            backingSubaccountId = backingSubaccountId;
            remotePrincipal = p;
            expiration = #None;
          });
          switch (registerResult) {
            case (#ok vid) {
              info.virtualAccountId := ?vid;
              vid;
            };
            case (#err error) {
              switch (error) {
                case (? #NoSpaceForAccount) throw Error.reject("No space for account");
                case (_) {
                  let message = "Opening virtual account problem";
                  journal.push((Time.now(), p, #error(message, error)));
                  freezeTokenHandler(message);
                  throw Error.reject(message);
                };
              };
            };
          };
        };
      };
      (ownPrincipal, virtualAccountId);
    };

    /// query the usable balance
    public func balance(p : Principal) : ?Nat = Option.map<Info, Nat>(map.get(p), func(info : Info) : Nat = info.credit);

    /// query journal for debug purposes. Returns:
    /// 1) array of all items in order, starting from the oldest record in journal, but no earlier than "startFrom" if provided
    /// 2) the index of next upcoming journal log. Use this value as "startFrom" in your next journal query to fetch next entries
    public func queryJournal(startFrom : ?Nat) : ([JournalRecord], Nat) = (
      (
        Option.get(startFrom, 0)
        |> Int.abs(Int.max(_, journal.pushesAmount() - journalSize))
        |> journal.slice(_, journal.pushesAmount())
        |> Iter.toArray(_)
      ),
      journal.pushesAmount(),
    );

    /// retrieve the current freeze state
    public func isFrozen() : Bool = isFrozen_;

    /// retrieve the sum of all successful consolidations
    public func consolidatedFunds() : Nat = consolidatedFunds_;

    /// deduct amount from P’s usable balance. Return false if the balance is insufficient.
    public func debit(p : Principal, amount : Nat) : Bool {
      if (isFrozen()) {
        return false;
      };
      let ?info = map.get(p) else return false;
      if (info.credit < amount) return false;
      info.credit -= amount;
      journal.push((Time.now(), p, #debited(amount)));
      totalDebited += amount;
      assertBalancesIntegrity();
      true;
    };

    ///  add amount to P’s usable balance (the credit is created out of thin air)
    public func credit(p : Principal, amount : Nat) : Bool {
      if (isFrozen()) {
        return false;
      };
      let info = mapGetOrCreate(p);
      info.credit += amount;
      totalCredited += amount;
      journal.push((Time.now(), p, #credited(amount)));
      assertBalancesIntegrity();
      true;
    };

    /// The handler will turn the balance of virtual account, previously opened for P, to zero.
    /// If there was non-zero amount (deposit), the handler will add the deposit to the credit of P.
    /// Returns the newly detected deposit and total usable balance if success, otherwise null
    /// We pass through any call Error instead of catching it
    public func sweepIn(p : Principal) : async* ?(Nat, Nat) {
      if (isFrozen()) return null;
      let ?info = map.get(p) else return null;
      let ?vid = info.virtualAccountId else return null;
      let updateResult = await hpl.updateVirtualAccount(
        vid,
        {
          balance = ? #Set 0;
          backingSubaccountId = null;
          expiration = null;
        },
      );
      switch (updateResult) {
        case (#ok { delta }) {
          if (delta == 0) {
            return ?(0, info.credit);
          };
          let deposit = Int.abs(delta); // expected delta here is always negative
          info.credit += deposit;
          journal.push((Time.now(), p, #sweepIn(deposit)));
          consolidatedFunds_ += deposit;
          ?(deposit, info.credit);
        };
        case (#err err) {
          let message = "Unexpected error during setting virtual account balance";
          journal.push((Time.now(), ownPrincipal, #error(message, err)));
          freezeTokenHandler(message);
          throw Error.reject(message);
        };
      };
    };

    /// The handler will increment the balance of virtual account, previously opened for P, with user credit.
    /// Returns total usable balance if success (available balance in the virtual account), otherwise null
    /// We pass through any call Error instead of catching it
    public func sweepOut(p : Principal) : async* ?Nat {
      if (isFrozen()) return null;
      let ?info = map.get(p) else return null;
      if (info.credit == 0) {
        return null;
      };
      let ?vid = info.virtualAccountId else return null;
      let updateResult = await hpl.updateVirtualAccount(
        vid,
        {
          balance = ? #Increment(info.credit);
          backingSubaccountId = null;
          expiration = null;
        },
      );
      switch (updateResult) {
        case (#ok { balance }) {
          journal.push((Time.now(), p, #sweepOut(info.credit)));
          totalDebited += info.credit;
          info.credit := 0;
          ?balance;
        };
        case (#err err) {
          let message = "Unexpected error during incrementing virtual account balance";
          journal.push((Time.now(), ownPrincipal, #error(message, err)));
          freezeTokenHandler(message);
          throw Error.reject(message);
        };
      };
    };

    /// receive tokens from user's virtual account, where remotePrincipal == ownPrincipal
    /// We pass through any call Error instead of catching it
    public func deposit(from : (Principal, HPL.VirtualAccountId), amount : Nat) : async* () {
      let info = mapGetOrCreate(from.0);
      let callResult = await hpl.submitAndExecute(
        #v1({
          map = [{
            owner = null;
            inflow = [(#sub(backingSubaccountId), (assetId, amount))];
            outflow = [(#vir(from), (assetId, amount))];
            mints = [];
            burns = [];
          }];
          memo = [];
        })
      );
      switch (callResult) {
        case (#ok _) {
          info.credit += amount;
          journal.push((Time.now(), ownPrincipal, #deposit({ from = from; amount = amount })));
        };
        case (#err err) switch (err) {
          case (? #InsufficientFunds) throw Error.reject("Insufficient funds");
          case (? #MismatchInAsset) throw Error.reject("Mismatch in asset id");
          case (? #MismatchInRemotePrincipal) throw Error.reject("Mismatch in remote principal");
          case (? #TooLargeFtQuantity) throw Error.reject("Too large quantity");
          case (
            ? #DeletedVirtualAccount or ? #TooLargeVirtualAccountId or ? #UnknownPrincipal or ? #UnknownVirtualAccount
          ) throw Error.reject("Virtual account not registered");
          case (_) {
            let message = "Unexpected error during deposit";
            journal.push((Time.now(), ownPrincipal, #error(message, from, err)));
            freezeTokenHandler(message);
            throw Error.reject(message);
          };
        };
      };
    };

    /// send tokens to another account
    /// "to" virtual account has to be opened by user, and handler principal has to be set as remotePrincipal in it
    /// We pass through any call Error instead of catching it
    public func withdraw(to : (Principal, HPL.VirtualAccountId), withdrawAmount : { #amount : Nat; #max }) : async* () {
      let ?info = map.get(to.0) else throw Error.reject("Not registered");
      let amount : Nat = switch (withdrawAmount) {
        case (#amount requested) {
          if (info.credit < requested) {
            throw Error.reject("Insufficient funds");
          };
          requested;
        };
        case (#max) info.credit;
      };
      if (amount == 0) {
        return ();
      };
      info.credit -= amount;
      let callResult = await hpl.submitAndExecute(
        #v1({
          map = [
            {
              owner = null;
              outflow = [(#sub(backingSubaccountId), (assetId, amount))];
              inflow = [(#vir(to), (assetId, amount))];
              mints = [];
              burns = [];
            },
          ];
          memo = [];
        })
      );
      switch (callResult) {
        case (#ok _) {
          journal.push((Time.now(), ownPrincipal, #withdraw({ to = to; amount = amount })));
        };
        case (#err err) {
          info.credit += amount;
          switch (err) {
            case (? #MismatchInAsset) throw Error.reject("Mismatch in asset id");
            case (? #MismatchInRemotePrincipal) throw Error.reject("Mismatch in remote principal");
            case (? #TooLargeFtQuantity) throw Error.reject("Too large quantity");
            case (
              ? #DeletedVirtualAccount or ? #TooLargeVirtualAccountId or ? #UnknownPrincipal or ? #UnknownVirtualAccount
            ) throw Error.reject("Virtual account not registered");
            case (_) {
              let message = "Unexpected error during withdraw";
              journal.push((Time.now(), ownPrincipal, #error(message, to, err)));
              freezeTokenHandler(message);
              throw Error.reject(message);
            };
          };
        };
      };
    };

    /// serialize tracking data
    public func share() : StableData = (
      Iter.toArray(
        Iter.map<(Principal, Info), (Principal, StableInfo)>(
          map.entries(),
          func(info : (Principal, Info)) : (Principal, StableInfo) = (info.0, { credit = info.1.credit; virtualAccountId = info.1.virtualAccountId }),
        )
      ),
      consolidatedFunds_,
      (totalDebited, totalCredited),
      journal.share(),
    );

    /// deserialize tracking data
    public func unshare(values : StableData) {
      map := RBTree.RBTree<Principal, Info>(Principal.compare);
      for ((p, value) in values.0.vals()) {
        map.put(p, { var virtualAccountId = value.virtualAccountId; var credit = value.credit });
      };
      consolidatedFunds_ := values.1;
      totalDebited := values.2.0;
      totalCredited := values.2.1;
      journal.unshare(values.3);
    };

    func assertBalancesIntegrity() : () {
      var usableSum = 0;
      for (entry in map.entries()) {
        usableSum += entry.1.credit;
      };
      if (usableSum + totalDebited != consolidatedFunds_ + totalCredited) {
        let values : [Text] = [
          "Balances integrity failed",
          Nat.toText(usableSum),
          Nat.toText(totalDebited),
          Nat.toText(consolidatedFunds_),
          Nat.toText(totalCredited),
        ];
        freezeTokenHandler(Text.join("; ", Iter.fromArray(values)));
      };
    };
  };
};
