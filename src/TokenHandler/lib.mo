import Principal "mo:base/Principal";
import Int "mo:base/Int";
import Text "mo:base/Text";
import Nat "mo:base/Nat";
import Result "mo:base/Result";

import Mapping "Mapping";
import ICRC1 "ICRC1";
import Journal "Journal";
import AccountManager "AccountManager";
import CreditRegistry "CreditRegistry";

module {
  public type StableData = (
    AccountManager.StableData, // account manager
    CreditRegistry.StableData, // credit registry
    Journal.StableData // journal
  );

  public type AccountInfo = {
    deposit : Nat;
    credit : Int;
  };

  public func defaultStableData() : StableData = (((#leaf, 0, 0, 1), 0, 0, 0, 0, 0, 0, 0, 0, 0), ([], 0), ([var], 0, 0));

  /// Converts `Principal` to `ICRC1.Subaccount`.
  public func toSubaccount(p : Principal) : ICRC1.Subaccount = Mapping.toSubaccount(p);

  /// Converts `ICRC1.Subaccount` to `Principal`.
  public func toPrincipal(subaccount : ICRC1.Subaccount) : ?Principal = Mapping.toPrincipal(subaccount);

  public type LedgerAPI = ICRC1.LedgerAPI;

  public class TokenHandler(
    ledgerApi : LedgerAPI,
    ownPrincipal : Principal,
    journalCapacity : Nat,
    initialFee : Nat,
  ) {

    /// Pause new notifications.
    public func pauseNotifications() = accountManager.pauseNotifications();

    /// Unpause new notifications.
    public func unpauseNotifications() = accountManager.unpauseNotifications();

    // Pass through the lookup counter from depositRegistry
    // TODO: Remove later
    public func lookups_() : Nat = accountManager.lookups();

    /// If some unexpected error happened, this flag turns true and handler stops doing anything until recreated.
    var isFrozen_ : Bool = false;

    /// Checks if the TokenHandler is frozen.
    public func isFrozen() : Bool = isFrozen_;

    /// Freezes the handler in case of unexpected errors and logs the error message to the journal.
    func freezeTokenHandler(errorText : Text) : () {
      isFrozen_ := true;
      journal.push(ownPrincipal, #error(errorText));
    };

    /// Collection of logs capturing events like deposits, withdrawals, fee updates, errors, etc.
    /// The journal provides a chronological history of actions taken by the handler.
    var journal = Journal.Journal(journalCapacity);

    /// Tracks credited funds (usable balance) associated with each principal.
    let creditRegistry = CreditRegistry.CreditRegistry(journal.push);

    /// Manages accounts and funds for users.
    /// Handles deposit, withdrawal, and consolidation operations.
    let accountManager = AccountManager.AccountManager(
      ledgerApi,
      ownPrincipal,
      journal.push,
      initialFee,
      freezeTokenHandler,
      func (p : Principal, x : Int) { creditRegistry.issue(#user p, x) },
    );

    /// Returns the ledger fee.
    public func ledgerFee() : Nat = accountManager.ledgerFee();

    /// Retrieves the admin-defined fee of the specific type.
    public func definedFee(t : AccountManager.FeeType) : Nat = accountManager.definedFee(t);

    /// Calculates the final fee of the specific type.
    public func fee(t : AccountManager.FeeType) : Nat = accountManager.fee(t);

    /// Defines the admin-defined fee of the specific type.
    public func setFee(t : AccountManager.FeeType, value : Nat) = accountManager.setFee(t, value);

    /// Retrieves the admin-defined minimum of the specific type.
    public func definedMinimum(minimumType : AccountManager.MinimumType) : Nat = accountManager.definedMinimum(minimumType);

    /// Calculates the final minimum of the specific type.
    public func minimum(minimumType : AccountManager.MinimumType) : Nat = accountManager.minimum(minimumType);

    /// Defines the admin-defined minimum of the specific type.
    public func setMinimum(minimumType : AccountManager.MinimumType, min : Nat) = accountManager.setMinimum(minimumType, min);

    /// Fetches and updates the fee from the ICRC1 ledger.
    /// Returns the new fee, or `null` if fetching is already in progress.
    public func fetchFee() : async* ?Nat {
      await* accountManager.fetchFee();
    };

    /// Returns a user's last know (= tracked) deposit
    /// Null means the principal is locked, hence no value is available.
    public func trackedDeposit(p : Principal) : ?Nat = accountManager.getDeposit(p);

    /// Queries the journal records starting from a specific index - for debug purposes.
    ///
    /// Returns:
    /// 1) Array of all items in order, starting from the oldest record in journal, but no earlier than "startFrom" if provided
    /// 2) The index of next upcoming journal log. Use this value as "startFrom" in your next journal query to fetch next entries
    public func queryJournal(startFrom : ?Nat) : ([Journal.JournalRecord], Nat) = journal.queryJournal(startFrom);

    public func state() : {
      journalLength : Nat;
      balance : {
        deposited : Nat;
        underway : Nat;
        queued : Nat;
        consolidated : Nat;
      };
      flow : {
        consolidated : Nat;
        withdrawn : Nat;
      };
      credit : {
        total : Int;
        pool : Int;
      };
      users : {
        queued : Nat;
      };
    } = {
      journalLength = journal.length();
      balance = {
        deposited = accountManager.depositedFunds();
        underway = accountManager.underwayFunds();
        queued = accountManager.queuedFunds();
        consolidated = accountManager.consolidatedFunds();
      };
      flow = {
        consolidated = accountManager.totalConsolidated();
        withdrawn = accountManager.totalWithdrawn();
      };
      credit = {
        total = creditRegistry.totalBalance();
        pool = creditRegistry.poolBalance();
      };
      users = {
        queued = accountManager.depositsNumber();
      };
    };

    /// Query the "length" of the journal (total number of entries ever pushed)
    public func journalLength() : Nat = journal.length();

    /// Gets the current credit amount associated with a specific principal.
    public func userCredit(p : Principal) : Int = creditRegistry.userBalance(p);

    /// Gets the current credit amount in the pool.
    public func poolCredit() : Int = creditRegistry.poolBalance();

    /// Adds amount to P’s credit.
    /// With checking the availability of sufficient funds.
    public func creditUser(p : Principal, amount : Nat) : Bool = creditRegistry.creditUser(p, amount);

    /// Deducts amount from P’s credit.
    /// With checking the availability of sufficient funds in the pool.
    public func debitUser(p : Principal, amount : Nat) : Bool = creditRegistry.debitUser(p, amount);

    // For debug and testing purposes only.
    // Issue credit directly to a principal or burn from a principal.
    // A negative amount means burn.
    // Without checking the availability of sufficient funds.
    public func issue_(account : CreditRegistry.Account, amount : Int) = creditRegistry.issue(account, amount);

    /// Notifies of a deposit and schedules consolidation process.
    /// Returns the newly detected deposit and credit funds if successful, otherwise null.
    public func notify(p : Principal) : async* ?(Nat, Int) {
      if isFrozen_ return null;
      let ?depositDelta = await* accountManager.notify(p) else return null;
      ?(depositDelta, creditRegistry.userBalance(p));
    };

    public func depositFromAllowance(account : ICRC1.Account, amount : Nat) : async* AccountManager.DepositFromAllowanceResponse {
      await* accountManager.depositFromAllowance(account, amount);
    };

    /// Triggers the proccessing first encountered deposit.
    public func trigger() : async* () {
      if isFrozen_ return;
      await* accountManager.trigger();
    };

    /// Initiates a withdrawal by transferring tokens to another account.
    /// Returns ICRC1 transaction index and amount of transferred tokens (fee excluded).
    public func withdrawFromPool(to : ICRC1.Account, amount : Nat) : async* AccountManager.WithdrawResponse {
      // try to burn from pool
      let success = creditRegistry.burn(#pool, amount);
      if (not success) return #err(#InsufficientCredit);
      let result = await* accountManager.withdraw(to, amount);
      if (Result.isErr(result)) {
        // re-issue credit if unsuccessful
        creditRegistry.issue(#pool, amount);
      };
      result;
    };

    /// Initiates a withdrawal by transferring tokens to another account.
    /// Returns ICRC1 transaction index and amount of transferred tokens (fee excluded).
    /// At the same time, it reduces the user's credit. Accordingly, amount <= credit should be satisfied.
    public func withdrawFromCredit(p : Principal, to : ICRC1.Account, amount : Nat) : async* AccountManager.WithdrawResponse {
      // try to burn from user
      creditRegistry.burn(#user p, amount)
      |> (if (not _) {
        let err = #InsufficientCredit;
        journal.push(ownPrincipal, #withdrawalError(err));
        return #err(err);
      });
      let result = await* accountManager.withdraw(to, amount);
      if (Result.isErr(result)) {
        // re-issue credit if unsuccessful
        creditRegistry.issue(#user p, amount);
      };
      result;
    };

    /// For testing purposes
    public func assertIntegrity() { accountManager.assertIntegrity() };

    /// Serializes the token handler data.
    public func share() : StableData = (
      accountManager.share(),
      creditRegistry.share(),
      journal.share(),
    );

    /// Deserializes the token handler data.
    public func unshare(values : StableData) {
      accountManager.unshare(values.0);
      creditRegistry.unshare(values.1);
      journal.unshare(values.2);
    };
  };

};
