import Principal "mo:base/Principal";
import IntMap "./IntMap";

module {
  public type StableData = [(Principal, Int)];

  public type LogEvent = { #credited : Nat; #debited : Nat };

  /// Tracks credited funds (usable balance) associated with each principal.
  public class CreditRegistry(log : (Principal, LogEvent) -> ()) {
    var map = IntMap.Map<Principal>(Principal.compare);

    /// Retrieves the total credited funds in the credit registry.
    public func creditTotal() : Int = map.sum();

    /// Gets the current credit amount associated with a specific principal.
    public func get(p : Principal) : Int = map.get(p);

    /// Deducts amount from P’s credit.
    /// With checking the availability of sufficient funds.
    public func debitStrict(p : Principal, amount : Nat) : Bool {
      let current = map.get(p);
      if (amount > current) return false;
      map.set(p, current - amount);
      log(p, #debited(amount));
      true;
    };

    /// Deducts amount from P’s credit.
    /// Without checking the availability of sufficient funds.
    public func debit(p : Principal, amount : Nat) {
      map.add(p, -amount);
      log(p, #debited(amount));
    };

    /// Increases the credit amount associated with a specific principal
    /// (the credit is created out of thin air).
    public func credit(p : Principal, amount : Nat) {
      map.add(p, amount);
      log(p, #credited(amount));
    };

    /// Serializes the credit registry data.
    public func share() : StableData = map.share();

    /// Deserializes the credit registry data.
    public func unshare(values : StableData) = map.unshare(values);
  };
};
