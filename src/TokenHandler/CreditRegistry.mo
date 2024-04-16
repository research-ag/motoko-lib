import RBTree "mo:base/RBTree";
import Principal "mo:base/Principal";
import Time "mo:base/Time";
import Option "mo:base/Option";
import Iter "mo:base/Iter";

import Journal "Journal";

module {
  public type StableData = (Int, [(Principal, Int)]);

  /// Tracks credited funds (usable balance) associated with each principal.
  public class CreditRegistry(
    journal : Journal.Journal,
    isFrozen : () -> Bool,
  ) {
    var map : RBTree.RBTree<Principal, Int> = RBTree.RBTree<Principal, Int>(Principal.compare);

    /// Total sum of credited funds in the credit registry.
    var creditTotal_ : Int = 0;

    /// Retrieves the total credited funds in the credit registry.
    public func creditTotal() : Int = creditTotal_;

    /// Gets the current credit amount associated with a specific principal.
    public func get(p : Principal) : Int = Option.get(map.get(p), 0);

    /// Deducts amount from P’s usable balance.
    /// The flag `strict` enables checking the availability of sufficient funds.
    func debit_(p : Principal, amount : Nat, strict : Bool) : Bool {
      if (isFrozen()) {
        return false;
      };

      let ?currentCredit = map.get(p) else return false;

      if (strict and currentCredit < amount) {
        return false;
      };

      let nextCredit = currentCredit - amount;

      if (nextCredit != 0) {
        map.put(p, nextCredit);
      } else {
        map.delete(p);
      };

      creditTotal_ -= amount;
      journal.push((Time.now(), p, #debited(amount)));
      true;
    };

    /// Deducts amount from P’s usable balance.
    /// With checking the availability of sufficient funds.
    public func debitStrict(p : Principal, amount : Nat) : Bool = debit_(p, amount, true);

    /// Deducts amount from P’s usable balance.
    /// Without checking the availability of sufficient funds.
    public func debit(p : Principal, amount : Nat) : Bool = debit_(p, amount, false);

    /// Increases the credit amount associated with a specific principal
    /// (the credit is created out of thin air).
    public func credit(p : Principal, amount : Nat) : Bool {
      if (isFrozen()) {
        return false;
      };

      let currentCredit = Option.get(map.get(p), 0);

      let nextCredit = currentCredit + amount;

      if (nextCredit != 0) {
        map.put(p, nextCredit);
      } else {
        map.delete(p);
      };

      creditTotal_ += amount;
      journal.push((Time.now(), p, #credited(amount)));
      true;
    };

    /// Serializes the credit registry data.
    public func share() : StableData {
      return (
        creditTotal_,
        Iter.toArray(map.entries()),
      );
    };

    /// Deserializes the credit registry data.
    public func unshare(values : StableData) {
      creditTotal_ := values.0;
      map := RBTree.RBTree<Principal, Int>(Principal.compare);
      for ((p, value) in values.1.vals()) {
        map.put(p, value);
      };
    };
  };
};
