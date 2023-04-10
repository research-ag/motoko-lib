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
    public type Asset = {
      #ft : (id : AssetId, quantity : Nat);
    };
    public type VirtualAccountState = { asset: Asset; backingSubaccountId: SubaccountId; remotePrincipal: Principal };
    public type TxInput = {
      map : [ContributionInput];
    };
    public type AccountReference = {
      #sub : SubaccountId;
      #vir : (Principal, VirtualAccountId);
    };
    type ContributionBody = {
      inflow : [(AccountReference, Asset)];
      outflow : [(AccountReference, Asset)];
      mints : [Asset];
      burns : [Asset];
      memo : ?Blob;
    };
    public type ContributionInput = ContributionBody and {
      owner : ?Principal;
    };
    public type AggregatorId = Nat;
    public type LocalId = Nat;
    public type GlobalId = (aggregator : AggregatorId, localId : LocalId);
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
    public type SubmitAndExecuteError = ProcessingError or { #NotApproved; };
    public type Ledger = actor {
      openVirtualAccount : (state : VirtualAccountState) -> async R.Result<VirtualAccountId, { #UnknownPrincipal; #UnknownSubaccount; #MismatchInAsset; #NoSpaceForAccount }>;
      setVirtualBalance : (vid : VirtualAccountId, newBalance : Nat) -> async R.Result<Int, { #UnknownPrincipal; #UnknownVirtualAccount; #DeletedVirtualAccount }>;
      incVirtualBalance : (vid : VirtualAccountId, delta : Nat) -> async R.Result<Nat, { #UnknownPrincipal; #UnknownVirtualAccount; #DeletedVirtualAccount }>;
      decVirtualBalance : (vid : VirtualAccountId, delta : Nat) -> async R.Result<Nat, { #InsufficientFunds; #UnknownPrincipal; #UnknownVirtualAccount; #DeletedVirtualAccount }>;
      virtualAccount : (vid : VirtualAccountId) -> async R.Result<VirtualAccountState, { #UnknownPrincipal; #UnknownVirtualAccount; #DeletedVirtualAccount }>;
      submitAndExecute : (tx : TxInput) -> async R.Result<GlobalId, SubmitAndExecuteError>;
    };
  };

  public func defaultHandlerStableData(): StableData = ([], 0, (0, 0), ([var], 0, 0));

  public type Info = {
    var credit : Nat;
    virtualAccountId : HPL.VirtualAccountId;
  };

  public type StableInfo = {
    credit : Nat;
    virtualAccountId : HPL.VirtualAccountId;
  };

  public type JournalRecord = (Time.Time, Principal, {
    #credited: Nat;
    #debited: Nat;
    #error: Any;
    #openAccountError: { #UnknownPrincipal; #UnknownSubaccount; #MismatchInAsset; #NoSpaceForAccount };
    #sweepIn: Nat;
    #sweepOut: Nat;
    #withdraw: { to: (Principal, HPL.AccountReference); amount: Nat };
    #deposit: { from: (Principal, HPL.VirtualAccountId); amount: Nat };
  });

  public type DepositError = {
    #CallHPLError;
    #DeletedVirtualAccount;
    #InsufficientFunds;
    #MismatchInAsset;
    #MismatchInRemotePrincipal; 
    #TooLargeFtQuantity;
    #TooLargeVirtualAccountId;
    #UnknownPrincipal;
    #UnknownVirtualAccount;
  };

  public type WithdrawError = {
    #CallHPLError;
    #DeletedVirtualAccount;
    #MismatchInAsset;
    #MismatchInRemotePrincipal; 
    #TooLargeFtQuantity;
    #TooLargeSubaccountId;
    #TooLargeVirtualAccountId;
    #UnknownPrincipal;
    #UnknownSubaccount;
    #UnknownVirtualAccount;
  };

  public type StableData = (
    [(Principal, StableInfo)],        // map
    Nat,                              // consolidatedFunds
    (Nat, Nat),                       // total debited/credited
    ([var ?JournalRecord], Nat, Int)  // journal
  );

  public class TokenHandler(
    hplLedgerPrincipal : Principal,
    assetId: HPL.AssetId, 
    backingSubaccountId: HPL.SubaccountId,
    ownPrincipal : Principal,
    journalSize: Nat,
  ) {
    let hpl = actor (Principal.toText(hplLedgerPrincipal)) : HPL.Ledger;

    /// if some unexpected error happened, this flag turns true and handler stops doing anything until recreated
    var isFrozen_ : Bool = false;
    func freezeTokenHandler(errorText: Text): () {
      isFrozen_ := true;
      journal.push((Time.now(), ownPrincipal, #error(errorText)));
    };

    var journal : CircularBuffer.CircularBuffer<JournalRecord> = CircularBuffer.CircularBuffer<JournalRecord>(journalSize);
    var consolidatedFunds_ : Nat = 0;
    var map : RBTree.RBTree<Principal, Info> = RBTree.RBTree<Principal, Info>(Principal.compare);

    var totalDebited : Nat = 0;
    var totalCredited : Nat = 0;

    /// Returns reference to registered virtual account for P.
    /// If not registered yet, registers it automatically
    public func getAccountReferenceFor(p : Principal) : async* (Principal, HPL.VirtualAccountId) {
      let virtualAccountId : HPL.VirtualAccountId = switch (map.get(p)) {
        case (?info) info.virtualAccountId;
        case (null) {
          let registerResult = try {
            await hpl.openVirtualAccount({ asset = #ft(assetId, 0); backingSubaccountId = backingSubaccountId; remotePrincipal = p });
          } catch (err) {
            #err(#CallHPLError);
          };
          switch (registerResult) {
            case (#ok vid) {
              map.put(p, {
                virtualAccountId = vid;
                var credit = 0;
              });
              vid;
            };
            case (#err error) {
              let message = "Opening virtual account problem";
              journal.push((Time.now(), p, #error(message, error)));
              throw Error.reject(message);
            };
          };
        };
      };
      (ownPrincipal, virtualAccountId);
    };

    /// query the usable balance
    public func balance(p : Principal) : ?Nat = Option.map<Info, Nat>(map.get(p), func (info: Info) : Nat = info.credit);

    /// query journal for debug purposes. Returns:
    /// 1) array of all items in order, starting from the oldest record in journal, but no earlier than "startFrom" if provided
    /// 2) the index of next upcoming journal log. Use this value as "startFrom" in your next journal query to fetch next entries
    public func queryJournal(startFrom: ?Nat): ([JournalRecord], Nat) = (
      Iter.toArray(
        journal.slice(
          Int.abs(Int.max(Option.get(startFrom, 0), journal.pushesAmount() - journalSize)),
          journal.pushesAmount()
        )
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
      let ?info = map.get(p) else return false;
      info.credit += amount;
      totalCredited += amount;
      journal.push((Time.now(), p, #credited(amount)));
      assertBalancesIntegrity();
      true;
    };

    /// The handler will turn the balance of virtual account, previously opened for P, to zero.
    /// If there was non-zero amount (deposit), the handler will add the deposit to the credit of P. 
    /// Returns the newly detected deposit and total usable balance if success, otherwise null
    public func sweepIn(p : Principal) : async* ?(Nat, Nat) {
      if (isFrozen()) return null;
      let ?info = map.get(p) else return null;
      let updateResult = try {
        await hpl.setVirtualBalance(info.virtualAccountId, 0);
      } catch (err) {
        #err(#CallHPLError);
      };
      switch (updateResult) {
        case (#ok delta) {
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
    public func sweepOut(p : Principal) : async* ?Nat {
      if (isFrozen()) return null;
      let ?info = map.get(p) else return null;
      let updateResult = try {
        await hpl.incVirtualBalance(info.virtualAccountId, info.credit);
      } catch (err) {
        #err(#CallHPLError);
      };
      switch (updateResult) {
        case (#ok newBalance) {
          journal.push((Time.now(), p, #sweepOut(info.credit)));
          totalDebited += info.credit;
          info.credit := 0;
          ?newBalance;
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
    public func deposit(from : (Principal, HPL.VirtualAccountId), amount: Nat): async* R.Result<(), DepositError> {
      let callResult = try {
        await hpl.submitAndExecute({ map = [
          {
            owner = null;
            inflow = [(#sub(backingSubaccountId), #ft(assetId, amount))];
            outflow = [(#vir(from), #ft(assetId, amount))];
            mints = []; burns = []; memo = null;
          }
        ]});
      } catch (err) {
        #err(#CallHPLError);
      };
      switch (callResult) {
        case (#ok _) {
          journal.push((Time.now(), ownPrincipal, #deposit({ from = from; amount = amount; })));
          #ok();
        };
        case (#err err) switch (err) {
          case (#CallHPLError) #err(#CallHPLError);
          case (#DeletedVirtualAccount) #err(#DeletedVirtualAccount);
          case (#InsufficientFunds) #err(#InsufficientFunds);
          case (#MismatchInAsset) #err(#MismatchInAsset);
          case (#MismatchInRemotePrincipal) #err(#MismatchInRemotePrincipal);
          case (#TooLargeFtQuantity) #err(#TooLargeFtQuantity);
          case (#TooLargeVirtualAccountId) #err(#TooLargeVirtualAccountId);
          case (#UnknownPrincipal) #err(#UnknownPrincipal);
          case (#UnknownVirtualAccount) #err(#UnknownVirtualAccount);
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
    public func withdraw(to : (Principal, HPL.AccountReference), amount: Nat): async* R.Result<(), WithdrawError> {
      let callResult = try {
        await hpl.submitAndExecute({ map = [
          {
            owner = null;
            outflow = [(#sub(backingSubaccountId), #ft(assetId, amount))];
            inflow = []; mints = []; burns = []; memo = null;
          },
          {
            owner = ?to.0;
            inflow = [(to.1, #ft(assetId, amount))];
            outflow = []; mints = []; burns = []; memo = null;
          }
        ]});
      } catch (err) {
        #err(#CallHPLError);
      };
      switch (callResult) {
        case (#ok _) {
          journal.push((Time.now(), ownPrincipal, #withdraw({ to = to; amount = amount; })));
          #ok();
        };
        case (#err err) switch (err) {
          case (#TooLargeFtQuantity) #err(#TooLargeFtQuantity);
          case (#TooLargeSubaccountId) #err(#TooLargeSubaccountId);
          case (#TooLargeVirtualAccountId) #err(#TooLargeVirtualAccountId);
          case (#UnknownPrincipal) #err(#UnknownPrincipal);
          case (#UnknownSubaccount) #err(#UnknownSubaccount);
          case (#UnknownVirtualAccount) #err(#UnknownVirtualAccount);
          case (#DeletedVirtualAccount) #err(#DeletedVirtualAccount);
          case (#MismatchInAsset) #err(#MismatchInAsset);
          case (#MismatchInRemotePrincipal) #err(#MismatchInRemotePrincipal);
          case (#CallHPLError) #err(#CallHPLError);
          case (_) {
            let message = "Unexpected error during withdraw";
            journal.push((Time.now(), ownPrincipal, #error(message, to, err)));
            freezeTokenHandler(message);
            throw Error.reject(message);
          };
        };
      };
    };

    /// serialize tracking data
    public func share() : StableData = (
      Iter.toArray(
        Iter.map<(Principal, Info), (Principal, StableInfo)>(
          map.entries(), 
          func (info: (Principal, Info)) : (Principal, StableInfo) = (info.0, { credit = info.1.credit; virtualAccountId = info.1.virtualAccountId })
        )
      ), 
      consolidatedFunds_, 
      (totalDebited, totalCredited), 
      journal.share()
    );

    /// deserialize tracking data
    public func unshare(values : StableData) {
      map := RBTree.RBTree<Principal, Info>(Principal.compare);
      for ((p, value) in values.0.vals()) {
        map.put(p, { virtualAccountId = value.virtualAccountId; var credit = value.credit; });
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
        let values: [Text] = [
          "Balances integrity failed", Nat.toText(usableSum), Nat.toText(totalDebited),
          Nat.toText(consolidatedFunds_), Nat.toText(totalCredited)
        ];
        freezeTokenHandler(Text.join("; ", Iter.fromArray(values)));
      }
    };
  };
};
