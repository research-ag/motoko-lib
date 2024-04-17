import Result "mo:base/Result";
import Principal "mo:base/Principal";
import Time "mo:base/Time";
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

  public func defaultStableData() : StableData = (([], 0, 0, 0, 0, 0), ([]), ([var], 0, 0));

  /// Converts `Principal` to `ICRC1.Subaccount`.
  public func toSubaccount(p : Principal) : ICRC1.Subaccount = Mapping.toSubaccount(p);

  /// Converts `ICRC1.Subaccount` to `Principal`.
  public func toPrincipal(subaccount : ICRC1.Subaccount) : ?Principal = Mapping.toPrincipal(subaccount);

  public class TokenHandler(
    icrc1LedgerPrincipal_ : Principal,
    ownPrincipal : Principal,
    journalCapacity : Nat,
    initialFee : Nat,
  ) {

    /// If some unexpected error happened, this flag turns true and handler stops doing anything until recreated.
    var isFrozen_ : Bool = false;

    /// Checks if the TokenHandler is frozen.
    public func isFrozen() : Bool = isFrozen_;

    /// Freezes the handler in case of unexpected errors and logs the error message to the journal.
    func freezeTokenHandler(errorText : Text) : () {
      isFrozen_ := true;
      journal.push((Time.now(), ownPrincipal, #error(errorText)));
    };

    /// Collection of logs capturing events like deposits, withdrawals, fee updates, errors, etc.
    /// The journal provides a chronological history of actions taken by the handler.
    var journal : Journal.Journal = Journal.Journal(journalCapacity);

    /// Tracks credited funds (usable balance) associated with each principal.
    let creditRegistry : CreditRegistry.CreditRegistry = CreditRegistry.CreditRegistry(
      journal,
      isFrozen,
    );

    /// Manages accounts and funds for users.
    /// Handles deposit, withdrawal, and consolidation operations.
    let accountManager : AccountManager.AccountManager = AccountManager.AccountManager(
      icrc1LedgerPrincipal_,
      ownPrincipal,
      journal,
      initialFee,
      isFrozen,
      freezeTokenHandler,
      creditRegistry,
    );

    /// Returns the fee.
    public func fee() : Nat = accountManager.fee();

    /// Fetches and updates the fee from the ICRC1 ledger.
    public func updateFee() : async* Nat {
      await* accountManager.updateFee();
    };

    /// Returns balances info for a principal - for debug purposes.
    public func info(p : Principal) : AccountInfo = {
      deposit = accountManager.getDeposit(p);
      credit = creditRegistry.get(p);
    };

    /// Queries the journal records starting from a specific index - for debug purposes.
    ///
    /// Returns:
    /// 1) Array of all items in order, starting from the oldest record in journal, but no earlier than "startFrom" if provided
    /// 2) The index of next upcoming journal log. Use this value as "startFrom" in your next journal query to fetch next entries
    public func queryJournal(startFrom : ?Nat) : ([Journal.JournalRecord], Nat) = journal.queryJournal(startFrom);

    /// Returns the ICRC1 ledger principal.
    public func icrc1LedgerPrincipal() : Principal = icrc1LedgerPrincipal_;

    /// Retrieves the sum of all current deposits.
    public func depositedFunds() : Nat = accountManager.depositedFunds();

    /// Retrieves the sum of all successful consolidations
    public func totalConsolidated() : Nat = accountManager.totalConsolidated();

    /// Retrieves the sum of all deductions from the main account.
    public func totalWithdrawn() : Nat = accountManager.totalWithdrawn();

    /// Retrieves the calculated balance of the main account.
    public func consolidatedFunds() : Nat = accountManager.consolidatedFunds();

    /// Returns the size of the deposit registry.
    public func depositsNumber() : Nat = accountManager.depositsNumber();

    /// Retrieves the total credited funds in the credit registry.
    public func creditTotal() : Int = creditRegistry.creditTotal();

    /// Gets the current credit amount associated with a specific principal.
    public func balance(p : Principal) : Int = creditRegistry.get(p);

    /// Deducts amount from P’s usable balance.
    /// With checking the availability of sufficient funds.
    public func debitStrict(p : Principal, amount : Nat) : Bool = creditRegistry.debitStrict(p, amount);

    /// Deducts amount from P’s usable balance.
    /// Without checking the availability of sufficient funds.
    public func debit(p : Principal, amount : Nat) : Bool = creditRegistry.debit(p, amount);

    /// Increases the credit amount associated with a specific principal
    /// (the credit is created out of thin air).
    public func credit(p : Principal, amount : Nat) : Bool = creditRegistry.credit(p, amount);

    /// Notifies of a deposit and schedules consolidation process.
    /// Returns the newly detected deposit and credit funds if successful, otherwise null.
    public func notify(p : Principal) : async* ?(Nat, Int) {
      let ?depositDelta = await* accountManager.notify(p) else return null;
      ?(depositDelta, creditRegistry.get(p));
    };

    /// Triggers the proccessing first encountered deposit.
    public func trigger() : async* () {
      await* accountManager.trigger();
    };

    /// Initiates a withdrawal by transferring tokens to another account.
    /// Returns ICRC1 transaction index and amount of transferred tokens (fee excluded).
    public func withdraw(to : ICRC1.Account, amount : Nat) : async* Result.Result<(transactionIndex : Nat, withdrawnAmount : Nat), ICRC1.TransferError or { #CallIcrc1LedgerError; #TooLowQuantity }> {
      await* accountManager.withdraw(to, amount);
    };

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
