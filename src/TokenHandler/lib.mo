import Principal "mo:base/Principal";
import Int "mo:base/Int";
import Text "mo:base/Text";
import Nat "mo:base/Nat";

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

    public func pauseNotifications() = accountManager.pauseNotifications();

    public func unpauseNotifications() = accountManager.unpauseNotifications();

    // Pass through the lookup counter from depositRegistry
    // TODO: Remove later
    public func lookups() : Nat = accountManager.lookups();

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
    let creditRegistry = CreditRegistry.CreditRegistry(ownPrincipal, journal.push);

    /// Manages accounts and funds for users.
    /// Handles deposit, withdrawal, and consolidation operations.
    let accountManager = AccountManager.AccountManager(
      ledgerApi,
      ownPrincipal,
      journal.push,
      initialFee,
      freezeTokenHandler,
      creditRegistry.credit,
      creditRegistry.debit,
    );

    /// Returns the ledger fee.
    public func ledgerFee() : Nat = accountManager.ledgerFee();

    public func definedFee(t : AccountManager.FeeType) : Nat = accountManager.definedFee(t);

    public func fee(t : AccountManager.FeeType) : Nat = accountManager.fee(t);

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

    /// Returns a user's current credit
    public func getCredit(p : Principal) : Int {
      creditRegistry.get(p);
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
        total = creditRegistry.creditTotal();
      };
      users = {
        queued = accountManager.depositsNumber();
      };
    };

    /// Query the "length" of the journal (total number of entries ever pushed)
    public func journalLength() : Nat = journal.length();

    /// Gets the current credit amount associated with a specific principal.
    public func balance(p : Principal) : Int = creditRegistry.get(p);

    /// Gets the current credit amount of the issuer account.
    public func issuer() : Int = creditRegistry.issuer();

    /// Deducts amount from the issuer account credit.
    public func debitIssuer(amount : Nat) = creditRegistry.debitIssuer(amount);

    /// Increases the current issuer account credit.
    public func creditIssuer(amount : Nat) = creditRegistry.creditIssuer(amount);

    /// Deducts amount from P’s usable balance.
    /// With checking the availability of sufficient funds.
    public func debitStrict(p : Principal, amount : Nat) : Bool = creditRegistry.debitStrict(p, amount);

    /// Adds amount to P’s credit.
    /// With checking the availability of sufficient funds in the issuer account.
    public func creditStrict(p : Principal, amount : Nat) : Bool = creditRegistry.creditStrict(p, amount);

    /// Deducts amount from P’s usable balance.
    /// Without checking the availability of sufficient funds.
    public func debit(p : Principal, amount : Nat) = creditRegistry.debit(p, amount);

    /// Increases the credit amount associated with a specific principal
    /// (the credit is created out of thin air).
    public func credit(p : Principal, amount : Nat) = creditRegistry.credit(p, amount);

    /// Notifies of a deposit and schedules consolidation process.
    /// Returns the newly detected deposit and credit funds if successful, otherwise null.
    public func notify(p : Principal) : async* ?(Nat, Int) {
      if isFrozen_ return null;
      let ?depositDelta = await* accountManager.notify(p) else return null;
      ?(depositDelta, creditRegistry.get(p));
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
    public func withdraw(to : ICRC1.Account, amount : Nat) : async* AccountManager.WithdrawResponse {
      await* accountManager.withdraw(to, amount);
    };

    /// Initiates a withdrawal by transferring tokens to another account.
    /// Returns ICRC1 transaction index and amount of transferred tokens (fee excluded).
    /// At the same time, it reduces the user's credit. Accordingly, amount < credit should be satisfied.
    public func withdrawFromCredit(p : Principal, to : ICRC1.Account, amount : Nat) : async* AccountManager.WithdrawResponse {
      if (amount > creditRegistry.get(p)) {
        let err = #InsufficientCredit;
        journal.push(ownPrincipal, #withdrawalError(err));
        return #err(err);
      };
      let result = await* accountManager.withdraw(to, amount);
      switch (result) {
        // sync credit after successful withdrawal
        case (#ok(_, _)) { creditRegistry.debit(p, amount) };
        case (_) {};
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
