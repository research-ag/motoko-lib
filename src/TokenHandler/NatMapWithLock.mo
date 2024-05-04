import RBTree "mo:base/RBTree";
import Iter "mo:base/Iter";
import Order "mo:base/Order";
import Option "mo:base/Option";
import Prim "mo:prim";

module {
  type V<L> = { var value : Nat; var lock : ?L };
  public type StableData<K, L> = (RBTree.Tree<K, V<L>>, Nat, Nat);

  public class NatMapWithLock<K, L>(compare : (K, K) -> Order.Order) {
    let tree = RBTree.RBTree<K, V<L>>(compare);
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

    public func getLock(k : K) : ?L {
      lookupCtr += 1;
      switch (tree.get(k)) {
        case (?v) v.lock;
        case (null) null;
      };
    };

    // Obtains a lock on key `k`.
    // If successful, returns a function `f`.
    // If non-successful, returns `null`.
    // The function `f` can be used to write a new value to `k` and release the lock at the same time.
    // The new value is optional.
    // If `null` is supplied then `f` releases the lock without changing the value.
    public func obtainLock(k : K, l : L) : ?(Nat, ?Nat -> Int) {
      lookupCtr += 1;
      let info = switch (tree.get(k)) {
        case (?r) {
          if (Option.isSome(r.lock)) return null;
          r.lock := ?l;
          r;
        };
        case (null) {
          let r = {
            var value = 0;
            var lock = ?l;
          };
          lookupCtr += 1;
          tree.put(k, r);
          r;
        };
      };
      func releaseLock(arg : ?Nat) : Int {
        if (Option.isNull(info.lock)) Prim.trap("Cannot happen: lock must be set");
        info.lock := null;
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
        delta
      };
      return ?(info.value, releaseLock);
    };

    public func entries() : Iter.Iter<(K, V<L>)> = tree.entries();

    public func firstUnlocked() : ?K {
      for (e in tree.entries()) {
        if (Option.isNull(e.1.lock)) return ?e.0;
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
          if (Option.isNull(v.lock)) {
            lookupCtr += 1;
            tree.delete(k);
          };
          old_value;
        };
        case (_) 0;
      };
    };

    public func share() : StableData<K, L> = (tree.share(), sum_, size_);
    public func unshare((t, sum, size) : StableData<K, L>) {
      tree.unshare(t);
      sum_ := sum;
      size_ := size;
    };
  };
};
