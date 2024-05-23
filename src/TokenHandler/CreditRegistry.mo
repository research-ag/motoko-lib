import Principal "mo:base/Principal";
import IntMap "IntMap";

module {
  public type StableData = ([(Principal, Int)], Int);

  public type Account = { #pool; #user : Principal };

  public type LogEvent = {
    #credited : Nat;
    #debited : Nat;
    #issued : Int;
    #burned : Nat;
  };

  /// Tracks credited funds (usable balance) associated with each principal.
  public class CreditRegistry(log : (Principal, LogEvent) -> ()) {
    var map = IntMap.Map<Principal>(Principal.compare);
    var pool_ : Int = 0;

    var issuer_ : Int = 0;

    /// Retrieves the total credited funds in the credit registry.
    public func totalBalance() : Int = map.sum() + pool_;

    /// Retrieves the total credited funds in the pool.
    public func poolBalance() : Int = pool_;

    /// Gets the current credit amount associated with a specific principal.
    public func userBalance(p : Principal) : Int = map.get(p);

    // transfer is checked, doesn't allow balances to go negative
    func transfer(from : Account, to : Account or { #burn }, amount : Nat) : Bool {
      switch (from) {
        case (#pool) {
          if (pool_ < amount) return false;
          pool_ -= amount;
        };
        case (#user p) {
          map.addIf(p, -amount, func x = x >= amount)
          |> (if (not _) return false);
        };
      };
      switch (to) {
        case (#pool) {
          pool_ += amount;
        };
        case (#user p) {
          map.add(p, amount);
        };
        case (#burn) {
        };
      };
      true
    };

    // The creditUser/debitUser functions transfer credit from the
    // user to/from the pool.
    public func creditUser(p : Principal, amount : Nat) : Bool {
      let success = transfer(#pool, #user p, amount);
      if (success) log(p, #credited(amount));
      success;
    };

    public func debitUser(p : Principal, amount : Nat) : Bool {
      let success = transfer(#user p, #pool, amount);
      if (success) log(p, #debited(amount));
      success;
    };

    // Issue credit to any user (or burn from user)
    // This is called on deposits or recalculation
    // No check is performed, balances can go negative as a result
    public func issue(account : Account, amount : Int) {
      switch (account) {
        case (#pool) {
          pool_ += amount;
          log(Principal.fromBlob(""), #issued(amount));
        };
        case (#user p) {
          map.add(p, amount);
          log(p, #issued(amount));
        };
      };
    };

    // Burn credit from a user or the pool
    // This is called on withdrawals
    // A check is performed, balances can not go negative
    public func burn(account : Account, amount : Nat) : Bool {
      let success = transfer(account, #burn, amount);
      if (success) switch (account) {
        case (#pool) log(Principal.fromBlob(""), #burned(amount));
        case (#user p) log(p, #burned(amount));
      };
      success;
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
