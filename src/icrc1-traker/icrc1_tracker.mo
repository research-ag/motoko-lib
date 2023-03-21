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
import Timer "mo:base/Timer";

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

  public class Icrc1Tracker(
    icrc1Ledger: Icrc1Interface.Icrc1LedgerInterface, 
    ownPrincipal: Principal,
  ) {

    public func notify(p: Principal): async* () {
      await* consolidateAccount(p);
    };

    // check the deposit account, update the tracked value in that account, return that value
    public func checkDeposit(p: Principal): async* Nat {
      // if the call below produces an error then this function will return with #canister_reject error
      // that is ok, the caller has to retry
      // there is no reason that the call below should permanently fail 
      let icrc1Balance = await* loadIcrc1Balance(p);

      // update the tracked value  
      // TODO: this should never _decrease_ the tracked value, find a way to throw an error if it does
      ignore trackingRepo.checkNewDeposits(p, icrc1Balance);

      // TODO: if there is an increase then log it as a detected deposit

      // schedule consolidation

      // return value 
      icrc1Balance
    };


    public func creditAvailable(p: Principal): Int = trackingRepo.creditBalanceOf(p);

    private func consolidateAccount(p: Principal): async* () {
      if (not trackingRepo.obtainLock(p)) return;
      let latestBalance = await* loadIcrc1Balance(p);
      // if the above call has produced an error then this function will return with #canister_reject error
      // TODO: need to catch and also release lock in the catch branch
      ignore trackingRepo.checkNewDeposits(p, latestBalance);
      if (latestBalance == 0) { 
        trackingRepo.releaseLock(p);
        return;
      };
      let transferResult = try {
          await icrc1Ledger.icrc1_transfer({
            from_subaccount = ?Principal.toBlob(p);
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
          ignore trackingRepo.addCredit(p, latestBalance);
          ignore trackingRepo.checkNewDeposits(p, 0);
        };
        case (#Err _) {
          ignore trackingRepo.checkNewDeposits(p, latestBalance);
          consolidationBacklog := AssocList.replace<Principal, ()>(consolidationBacklog, p, Principal.equal, ?()).0;
        };
      };
      trackingRepo.releaseLock(p);
    };

    private func processConsolidationBacklog(): async () = async switch (consolidationBacklog) {
        case (null) return;
        case (?((p, _), list)) {
          consolidationBacklog := list;
          await* consolidateAccount(p);
        };
      };

    private func loadIcrc1Balance(p: Principal): async* (Nat) {
      await icrc1Ledger.icrc1_balance_of({ owner = ownPrincipal; subaccount = ?Principal.toBlob(p); });
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

    // A timer for consolidating backlog subaccounts
    let backlogTimer = Timer.recurringTimer(#seconds 10, processConsolidationBacklog);

  };

}
