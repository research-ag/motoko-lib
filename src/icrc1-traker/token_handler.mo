import R "mo:base/Result";
import Cycles "mo:base/ExperimentalCycles";
import RBTree "mo:base/RBTree";
import Principal "mo:base/Principal";
import Iter "mo:base/Iter";
import Option "mo:base/Option";
import Debug "mo:base/Debug";
import Int "mo:base/Int";
import AssocList "mo:base/AssocList";
import Blob "mo:base/Blob";

import Icrc1Interface "icrc1_interface";
import TrackingInfoRepository "tracking_info_repository";

module {
  public type Icrc1LedgerInterface = Icrc1Interface.Icrc1LedgerInterface;

  public type StableTrackingInfo = TrackingInfoRepository.StableTrackingInfo;

  public type Icrc1TransferError = {
    #CallIcrc1LedgerError;
    #IcrcInsufficientFunds;
    #IcrcTemporarilyUnavailable;
    #IcrcGenericError;
  };

  public class TokenHandler(
    icrc1Ledger: Icrc1Interface.Icrc1LedgerInterface, 
    ownPrincipal: Principal,
  ) {

    public func notify(p: Principal): async* () {
      await* consolidateAccount(p);
    };

    public func debit(p: Principal, amount: Nat): Bool {
      trackingRepo.debit(p, amount);
    };

    public func credit(p: Principal, amount: Nat): () {
      trackingRepo.credit(p, amount);
    };

    public func balance(p: Principal): Int {
      trackingRepo.usableBalanceOf(p);
    };

    public func info(p: Principal): StableTrackingInfo {
      trackingRepo.info(p);
    };

    private func consolidateAccount(p: Principal): async* () {
      if (not trackingRepo.obtainLock(p)) return;
      var latestBalance = 0;
      try {
        latestBalance := await icrc1Ledger.icrc1_balance_of({ owner = ownPrincipal; subaccount = ?Principal.toBlob(p); }); // FIXME should be 32 bytes instead of 29;
      } catch (err) {
        trackingRepo.releaseLock(p);
        throw err;
      };
      trackingRepo.updateDepositBalance(p, latestBalance);
      if (latestBalance != 0) { 
        let transferResult = try {
          await icrc1Ledger.icrc1_transfer({
            from_subaccount = ?Principal.toBlob(p); // FIXME should be 32 bytes instead of 29
            to = { owner = ownPrincipal; subaccount = null; };
            amount = latestBalance;
            fee = null;
            memo = null;
            created_at_time = null;
          });
        } catch (err) {
          #Err(#CallIcrc1LedgerError);
        };
      switch (transferResult) {
        case (#Ok _) {
          trackingRepo.credit(p, latestBalance);
          trackingRepo.updateDepositBalance(p, 0);
        };
        case (#Err _) {
          trackingRepo.updateDepositBalance(p, latestBalance);
          consolidationBacklog := AssocList.replace<Principal, ()>(consolidationBacklog, p, Principal.equal, ?()).0;
        };
      };
      };
      trackingRepo.releaseLock(p);
    };

    public func processConsolidationBacklog(): async () = async switch (consolidationBacklog) {
      case (null) return;
      case (?((p, _), list)) {
        consolidationBacklog := list;
        await* consolidateAccount(p);
      };
    };
    
    private func castIcrc1TransferError(err: Icrc1Interface.TransferError or { #CallIcrc1LedgerError; }): Icrc1TransferError {
      switch (err) {
        case (#CallIcrc1LedgerError) #CallIcrc1LedgerError;
        case (#InsufficientFunds _) #IcrcInsufficientFunds;
        case (#TemporarilyUnavailable _) #IcrcTemporarilyUnavailable;
        case (#GenericError _) #IcrcGenericError;
        case (_) Debug.trap("Unexpected ICRC1 error");
      };
    };

    // a backlog of principals, with failed account consolidation
    public var consolidationBacklog: AssocList.AssocList<Principal, ()> = null;

    // The map from principal to tracking info:
    public let trackingRepo : TrackingInfoRepository.TrackingInfoRepository = TrackingInfoRepository.TrackingInfoRepository();

  };

}
