import AssocList "mo:base/AssocList";
import Principal "mo:base/Principal";
import List "mo:base/List";

module {
  public type StableData = (Nat, [(Principal, Nat)]);

  /// Manages the backlog of funds waiting for consolidation.
  /// Tracks the size of the queue, queued funds, and funds currently underway for consolidation.
  public class Backlog() {
    /// Holds the backlog entries (principal, amount).
    var backlog : AssocList.AssocList<Principal, Nat> = null;

    /// Number of principals in the backlog.
    var size_ : Nat = 0;

    /// Total funds queued for consolidation.
    var queuedFunds : Nat = 0;

    /// Total funds underway for consolidation.
    var underwayFunds : Nat = 0;

    /// Retrieves the current size of the backlog.
    public func size() : Nat = size_;

    /// Retrieves the sum of all balances in the backlog.
    public func funds() : Nat = queuedFunds + underwayFunds;

    /// Adds a principal and amount to the backlog.
    public func push(p : Principal, amount : Nat) {
      let (updated, prev) = AssocList.replace<Principal, Nat>(backlog, p, Principal.equal, ?amount);
      queuedFunds += amount;
      backlog := updated;
      switch (prev) {
        case (null) size_ += 1;
        case (?prevAmount) {
          queuedFunds -= prevAmount;
        };
      };
    };

    /// Removes a principal from the backlog.
    public func remove(p : Principal) {
      let (updated, prev) = AssocList.replace<Principal, Nat>(backlog, p, Principal.equal, null);
      backlog := updated;
      switch (prev) {
        case (null) {};
        case (?prevAmount) {
          size_ -= 1;
          queuedFunds -= prevAmount;
        };
      };
    };

    /// Removes the first entry of the backlog.
    /// Returns a principal from the first entry and a callback function
    /// that should be called after the consolidation process has completed.
    public func pop() : ?(p : Principal, consolidatedCallback : () -> ()) {
      switch (backlog) {
        case (null) null;
        case (?((p, amount), list)) {
          backlog := list;
          size_ -= 1;
          queuedFunds -= amount;
          underwayFunds += amount;
          ?(
            p,
            func() = underwayFunds -= amount,
          );
        };
      };
    };

    /// Serializes the backlog data.
    public func share() : StableData {
      // Underway funds have to be zero when upgrading canister.
      (queuedFunds, List.toArray(backlog));
    };

    /// Deserializes the backlog data.
    public func unshare(data : StableData) {
      backlog := null;
      queuedFunds := data.0;
      // Underway funds have to be zero when upgrading canister.
      size_ := data.1.size();
      var i = size_;
      while (i > 0) {
        backlog := ?(data.1 [i - 1], backlog);
        i -= 1;
      };
    };
  };
};
