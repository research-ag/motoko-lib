import RBTree "mo:base/RBTree";
import Iter "mo:base/Iter";
import Order "mo:base/Order";
import Prim "mo:prim";

module {
  type V = { var value : Nat; var lock : Bool };
  public type StableData<K> = (RBTree.Tree<K, V>, Nat, Nat);

  public class NatMapWithLock<K>(compare : (K, K) -> Order.Order) {
    let tree = RBTree.RBTree<K, V>(compare);
    var size_ : Nat = 0;
    var sum_ : Nat = 0;

    // For benchmarking purposes we track how often we lookup a key in the tree
    // TODO: remove in production
    var lookupCtr = 0;
    public func lookups() : Nat = lookupCtr;

    // Returns the Nat value associated with the key `k`.
    public func get(k : K) : Nat {
      lookupCtr += 1;
      switch (tree.get(k)) {
        case (?v) v.value;
        case (null) 0;
      };
    };

    // Returns the number of non-zero entries in the map (locked or not).
    public func size() : Nat = size_;

    // Returns the sum of all entries.
    public func sum() : Nat = sum_;

    // Currently not used
    /*
    public func getLock(k : K) : Bool {
      lookupCtr += 1;
      switch (tree.get(k)) {
        case (?v) v.lock;
        case (null) false;
      };
    };
    */

    // Obtains a lock on key `k`.
    // If successful, returns a function `f`.
    // If non-successful, returns `null`.
    // The function `f` can be used to write a new value to `k` and release the lock at the same time.
    // The new value is optional.
    // If `null` is supplied then `f` releases the lock without changing the value.
    public func obtainLock(k : K) : ?(Nat, ?Nat -> Int) {
      lookupCtr += 1;
      let info = switch (tree.get(k)) {
        case (?r) {
          if (r.lock) return null;
          r.lock := true;
          r;
        };
        case (null) {
          let r = {
            var value = 0;
            var lock = true;
          };
          lookupCtr += 1;
          tree.put(k, r);
          r;
        };
      };
      func releaseLock(arg : ?Nat) : Int {
        if (not info.lock) Prim.trap("Cannot happen: lock must be set");
        info.lock := false;
        let delta : Int = switch (arg) {
          case (?new_value) {
            let old_value = info.value;
            if (old_value == 0 and new_value > 0) size_ += 1;
            if (old_value > 0 and new_value == 0) size_ -= 1;
            sum_ -= old_value;
            sum_ += new_value;
            info.value := new_value;
            new_value - old_value;
          };
          case (null) 0;
        };
        if (info.value == 0) {
          lookupCtr += 1;
          tree.delete(k);
        };
        delta;
      };
      return ?(info.value, releaseLock);
    };

    public func entries() : Iter.Iter<(K, V)> = tree.entries();

    public func obtainAnyLock() : ?(K, Nat, ?Nat -> Int) {
      label L for (e in tree.entries()) {
        let info = e.1;
        if (info.lock) continue L;
        let k = e.0;
        info.lock := true;
        func releaseLock(arg : ?Nat) : Int {
          if (not info.lock) Prim.trap("Cannot happen: lock must be set");
          info.lock := false;
          let delta : Int = switch (arg) {
            case (?new_value) {
              let old_value = info.value;
              if (old_value == 0 and new_value > 0) size_ += 1;
              if (old_value > 0 and new_value == 0) size_ -= 1;
              sum_ -= old_value;
              sum_ += new_value;
              info.value := new_value;
              new_value - old_value;
            };
            case (null) 0;
          };
          if (info.value == 0) {
            lookupCtr += 1;
            tree.delete(k);
          };
          delta;
        };
        return ?(k, info.value, releaseLock);
      };
      return null;
    };

    public func erase(k : K) : Nat {
      lookupCtr += 1;
      switch (tree.get(k)) {
        case (?v) {
          let old_value = v.value;
          v.value := 0;
          if (old_value != 0) size_ -= 1;
          sum_ -= old_value;
          if (not v.lock) {
            lookupCtr += 1;
            tree.delete(k);
          };
          old_value;
        };
        case (_) 0;
      };
    };

    public func share() : StableData<K> = (tree.share(), sum_, size_);
    public func unshare((t, sum, size) : StableData<K>) {
      tree.unshare(t);
      sum_ := sum;
      size_ := size;
    };
  };
};
