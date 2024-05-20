import RBTree "mo:base/RBTree";
import Order "mo:base/Order";
import Prim "mo:prim";

module {
  type V = { var value : Nat; var lock : Bool };
  public type StableData<K> = (RBTree.Tree<K, V>, Nat, Nat, Nat);

  public class NatMapWithLock<K>(compare : (K, K) -> Order.Order, initialMinimum : Nat) {
    let tree = RBTree.RBTree<K, V>(compare);
    var size_ : Nat = 0;
    var sum_ : Nat = 0;
    var minimum_ : Nat = initialMinimum;

    // For benchmarking purposes we track how often we lookup a key in the tree
    // TODO: remove in production
    var lookupCtr = 0;
    public func lookups() : Nat = lookupCtr;

    // Returns the number of non-zero entries in the map (locked or not).
    public func size() : Nat = size_;

    // Returns the sum of all entries.
    public func sum() : Nat = sum_;

    // Returns the minimum value.
    public func minimum() : Nat = minimum_;

    // Returns the Nat value associated with the key `k`.
    public func get(k : K) : Nat {
      lookupCtr += 1;
      switch (tree.get(k)) {
        case (?v) v.value;
        case (null) 0;
      };
    };

    // Like `get` but returns null if key `k` is locked.
    public func getOpt(k : K) : ?Nat {
      lookupCtr += 1;
      switch (tree.get(k)) {
        case (?v) if (v.lock) null else ?v.value;
        case (null) ?0;
      };
    };

    public func setMinimum(m : Nat, zeroed : (K, Nat) -> ()) {
      let increase = m > minimum_;
      minimum_ := m;
      if (not increase) return;
      label L for ((k, info) in tree.entries()) {
        let v = info.value;
        if (v == 0 or v >= m) continue L;
        info.value := 0;
        sum_ -= v;
        size_ -= 1;
        clean(k, info);
        zeroed(k, v);
      };
    };

    func clean(k : K, info : V) {
      if (info.value == 0 and not info.lock) {
        lookupCtr += 1;
        tree.delete(k);
      };
    };

    // Obtains a lock on key `k`.
    // If successful, returns a function `f`.
    // If non-successful, returns `null`.
    // The function `f` can be used to write a new value to `k` and release the lock at the same time.
    // The new value is optional.
    // If `null` is supplied then `f` releases the lock without changing the value.
    public func obtainLock(k : K) : ?(?Nat -> Int) {
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
      return ?(releaseFunc(k, info));
    };

    func releaseFunc(k : K, info : V) : ?Nat -> Int {
      func(arg : ?Nat) : Int {
        if (not info.lock) Prim.trap("Cannot happen: lock must be set");
        info.lock := false;
        // enter new value
        let delta : Int = switch (arg) {
          case (?v) {
            let (old, new) = (info.value, if (v < minimum_) 0 else v);
            if (old == 0 and new > 0) size_ += 1;
            if (old > 0 and new == 0) size_ -= 1;
            sum_ -= old;
            sum_ += new;
            info.value := new;
            new - old;
          };
          case (null) 0;
        };
        clean(k, info);
        delta;
      };
    };

    public func iterate(f : (K, Nat) -> ()) {
      for (e in tree.entries()) {
        if (e.1.value != 0) f(e.0, e.1.value);
      };
    };

    public func nextLock() : ?(K, Nat, ?Nat -> Int) {
      label L for (e in tree.entries()) {
        let info = e.1;
        if (info.lock) continue L;
        let k = e.0;
        info.lock := true;
        return ?(k, info.value, releaseFunc(k, info));
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
          clean(k, v);
          old_value;
        };
        case (_) 0;
      };
    };

    public func share() : StableData<K> = (tree.share(), sum_, size_, minimum_);
    public func unshare((t, sum, size, minimum) : StableData<K>) {
      tree.unshare(t);
      sum_ := sum;
      size_ := size;
      minimum_ := minimum;
    };
  };
};
