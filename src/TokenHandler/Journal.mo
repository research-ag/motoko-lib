import Time "mo:base/Time";
import Iter "mo:base/Iter";
import Option "mo:base/Option";
import Int "mo:base/Int";

import CircularBuffer "../CircularBuffer";
import CreditRegistry "CreditRegistry";
import AccountManager "AccountManager";

module {
  public type StableData = ([var ?JournalRecord], Nat, Nat);

  public type Event = AccountManager.LogEvent or CreditRegistry.LogEvent or {
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

    /// Query the "length" of the journal (total number of entries ever pushed)
    public func length() : Nat { journal.pushesAmount() };

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
