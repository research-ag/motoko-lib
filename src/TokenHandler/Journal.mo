import Time "mo:base/Time";
import Iter "mo:base/Iter";
import Option "mo:base/Option";
import Int "mo:base/Int";

import CircularBuffer "../CircularBuffer";
import ICRC1 "./ICRC1";

module {
  public type StableData = ([var ?JournalRecord], Nat, Nat);

  public type AccountManagerEvent = {
    #newDeposit : Nat;
    #consolidated : { deducted : Nat; credited : Nat };
    #feeUpdated : { old : Nat; new : Nat };
    #consolidationError : ICRC1.TransferError or { #CallIcrc1LedgerError };
    #withdraw : { to : ICRC1.Account; amount : Nat };
  };
  public type CreditRegistryEvent = {
    #debited : Nat;
    #credited : Nat;
  };
  public type Event = AccountManagerEvent or CreditRegistryEvent or {
    #error : Text;
  };
  public type JournalRecord = (Time.Time, Principal, Event);

  /// Manages journal records and provides methods to interact with them.
  /// Plays a critical role in logging and maintaining transaction records within the token handler.
  public class Journal(journalCapacity : Nat) {

    let journal : CircularBuffer.CircularBuffer<JournalRecord> = CircularBuffer.CircularBuffer<JournalRecord>(journalCapacity);

    /// Adds a new journal record to the journal.
    public func push(p : Principal, e : Event) {
      journal.push(Time.now(), p, e);
    };

    /// Queries the journal records starting from a specific index - for debug purposes.
    ///
    /// Returns:
    /// 1) Array of all items in order, starting from the oldest record in journal, but no earlier than "startFrom" if provided
    /// 2) The index of next upcoming journal log. Use this value as "startFrom" in your next journal query to fetch next entries
    public func queryJournal(startFrom : ?Nat) : ([JournalRecord], Nat) = (
      (
        Option.get(startFrom, 0)
        |> Int.abs(Int.max(_, journal.pushesAmount() - journalCapacity))
        |> journal.slice(_, journal.pushesAmount())
        |> Iter.toArray(_)
      ),
      journal.pushesAmount(),
    );

    /// Serializes the journal data.
    public func share() : StableData {
      journal.share();
    };

    /// Deserializes the journal data.
    public func unshare(data : StableData) : () {
      journal.unshare(data);
    };
  };
};
