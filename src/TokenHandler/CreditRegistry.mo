import Principal "mo:base/Principal";
import IntMap "IntMap";

module {
  public type StableData = ([(Principal, Int)], Int);

  public type LogEvent = {
    #credited : Nat;
    #debited : Nat;
    #issuerCredited : Nat;
    #issuerDebited : Nat;
  };

  /// Tracks credited funds (usable balance) associated with each principal.
  public class CreditRegistry(ownPrincipal : Principal, log : (Principal, LogEvent) -> ()) {
    var map = IntMap.Map<Principal>(Principal.compare);

    var issuer_ : Int = 0;

    /// Retrieves the total credited funds in the credit registry.
    public func creditTotal() : Int = map.sum();

    /// Gets the current credit amount associated with a specific principal.
    public func get(p : Principal) : Int = map.get(p);

    /// Gets the current credit amount of the issuer account.
    public func issuer() : Int = issuer_;

    /// Deducts amount from the issuer account credit.
    public func debitIssuer(amount : Nat) {
      issuer_ -= amount;
      log(ownPrincipal, #issuerDebited(amount));
    };

    /// Increases the current issuer account credit.
    public func creditIssuer(amount : Nat) {
      issuer_ += amount;
      log(ownPrincipal, #issuerCredited(amount));
    };

    /// Deducts amount from P’s credit.
    /// With checking the availability of sufficient funds in the P's account.
    public func debitStrict(p : Principal, amount : Nat) : Bool {
      let res = map.addIf(p, -amount, func x = x >= amount);
      if (res) {
        creditIssuer(amount);
        log(p, #debited(amount));
      };
      res;
    };

    /// Adds amount to P’s credit.
    /// With checking the availability of sufficient funds in the issuer account.
    public func creditStrict(p : Principal, amount : Nat) : Bool {
      let res = issuer_ >= amount;
      if (res) {
        map.add(p, amount);
        debitIssuer(amount);
        log(p, #credited(amount));
      };
      res;
    };

    /// Deducts amount from P’s credit.
    /// Without checking the availability of sufficient funds.
    public func debit(p : Principal, amount : Nat) {
      map.add(p, -amount);
      log(p, #debited(amount));
    };

    /// Increases the credit amount associated with a specific principal.
    /// Without checking the availability of sufficient funds.
    public func credit(p : Principal, amount : Nat) {
      map.add(p, amount);
      log(p, #credited(amount));
    };

    /// Serializes the credit registry data.
    public func share() : StableData = (map.share(), issuer_);

    /// Deserializes the credit registry data.
    public func unshare(values : StableData) {
      map.unshare(values.0);
      issuer_ := values.1;
    };
  };
};
