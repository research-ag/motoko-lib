import Blob "mo:base/Blob";
import Array "mo:base/Array";
import Nat32 "mo:base/Nat32";
import Prim "mo:⛔";

module {
  /// Red-black tree of key `Nat`.
  public type Tree = {
    #red : (Tree, Nat, Tree);
    #black : (Tree, Nat, Tree);
    #leaf;
  };

  /// Bidirectional enumeration of `Blob`s in order they are added.
  /// For map from `Blob` to index `Nat` it's implemented as red-black tree, for map from index `Nat` to `Blob` the implementation is an array.
  /// ```
  /// let e = Enumeration.Enumeration();
  /// ```
  public class Enumeration() {
    private var array = ([var ""] : [var Blob]);
    private var size_ = 0;

    private var tree = (#leaf : Tree);

    /// Add `key` to enumeration. Returns `size` if the key in new to the enumeration and index of key in enumeration otherwise.
    /// ```
    /// let e = Enumeration.Enumeration();
    /// assert(e.add("abc") == 0);
    /// assert(e.add("aaa") == 1);
    /// assert(e.add("abc") == 0);
    /// ```
    /// Runtime: O(log(n))
    public func add(key : Blob) : Nat {
      var index = size_;

      func lbalance(left : Tree, y : Nat, right : Tree) : Tree {
        switch (left, right) {
          case (#red(#red(l1, y1, r1), y2, r2), r) #red(#black(l1, y1, r1), y2, #black(r2, y, r));
          case (#red(l1, y1, #red(l2, y2, r2)), r) #red(#black(l1, y1, l2), y2, #black(r2, y, r));
          case _ #black(left, y, right);
        };
      };

      func rbalance(left : Tree, y : Nat, right : Tree) : Tree {
        switch (left, right) {
          case (l, #red(l1, y1, #red(l2, y2, r2))) #red(#black(l, y, l1), y1, #black(l2, y2, r2));
          case (l, #red(#red(l1, y1, r1), y2, r2)) #red(#black(l, y, l1), y1, #black(r1, y2, r2));
          case _ #black(left, y, right);
        };
      };

      func insert(tree : Tree) : Tree {
        switch tree {
          case (#black(left, y, right)) {
            switch (Blob.compare(key, array[y])) {
              case (#less) lbalance(insert(left), y, right);
              case (#greater) rbalance(left, y, insert(right));
              case (#equal) {
                index := y;
                tree;
              };
            };
          };
          case (#red(left, y, right)) {
            switch (Blob.compare(key, array[y])) {
              case (#less) #red(insert(left), y, right);
              case (#greater) #red(left, y, insert(right));
              case (#equal) {
                index := y;
                tree;
              };
            };
          };
          case (#leaf) {
            index := size_;
            #red(#leaf, size_, #leaf);
          };
        };
      };

      tree := switch (insert(tree)) {
        case (#red(left, y, right)) #black(left, y, right);
        case other other;
      };

      // approximate growth by sqrt(2) by 2-powers
      // the function will trap if n == 0 or n >= 3 * 2 ** 30
      func next_size(n_ : Nat) : Nat {
        if (n_ == 1) return 2;
        let n = Nat32.fromNat(n_); // traps if n >= 2 ** 32
        let s = 30 - Nat32.bitcountLeadingZero(n); // traps if n == 0
        let m = ((n >> s) +% 1) << s;
        assert (m != 0); // traps if n >= 3 * 2 ** 30
        Nat32.toNat(m);
      };
      
      if (index == size_) {
        if (size_ == array.size()) {
          array := Array.tabulateVar<Blob>(next_size(size_), func(i) = if (i < size_) { array[i] } else { "" });
        };
        array[size_] := key;
        size_ += 1;
      };

      index;
    };

    /// Returns `?index` where `index` is the index of `key` in order it was added to enumeration, or `null` it `key` wasn't added.
    /// ```
    /// let e = Enumeration.Enumeration();
    /// assert(e.add("abc") == 0);
    /// assert(e.add("aaa") == 1);
    /// assert(e.lookup("abc") == ?0);
    /// assert(e.lookup("aaa") == ?1);
    /// assert(e.lookup("bbb") == null);
    /// ```
    /// Runtime: O(log(n))
    public func lookup(key : Blob) : ?Nat {
      func get_in_tree(x : Blob, t : Tree) : ?Nat {
        switch t {
          case (#red(l, y, r)) {
            switch (Blob.compare(x, array[y])) {
              case (#less) get_in_tree(x, l);
              case (#equal) ?y;
              case (#greater) get_in_tree(x, r);
            };
          };
          case (#black(l, y, r)) {
            switch (Blob.compare(x, array[y])) {
              case (#less) get_in_tree(x, l);
              case (#equal) ?y;
              case (#greater) get_in_tree(x, r);
            };
          };
          case (#leaf) null;
        };
      };

      get_in_tree(key, tree);
    };

    /// Returns `Blob` with index `index`. Traps it index is out of bounds.
    /// ```
    /// let e = Enumeration.Enumeration();
    /// assert(e.add("abc") == 0);
    /// assert(e.add("aaa") == 1);
    /// assert(e.get(0) == "abc");
    /// assert(e.get(1) == "aaa");
    /// ```
    /// Runtime: O(1)
    public func get(index : Nat) : Blob {
      if (index < size_) { array[index] } else {
        Prim.trap("Index out of bounds");
      };
    };

    /// Returns number of unique keys added to enumration.
    /// ```
    /// let e = Enumeration.Enumeration();
    /// assert(e.add("abc") == 0);
    /// assert(e.add("aaa") == 1);
    /// assert(e.size() == 2);
    /// ```
    /// Runtime: O(1)
    public func size() : Nat = size_;

    /// Returns pair of red-black tree for map from `Blob` to `Nat` and array of `Blob` for map from `Nat` to `Blob`.
    /// Returns number of unique keys added to enumration.
    /// ```
    /// let e = Enumeration.Enumeration();
    /// assert(e.add("abc") == 0);
    /// assert(e.add("aaa") == 1);
    /// e.unsafeUnshare(e.share()); // Nothing changed
    /// ```
    /// Runtime: O(1)
    public func share() : (Tree, [var Blob], Nat) = (tree, array, size_);

    /// Sets internal content from red-black tree for map from `Blob` to `Nat` and array of `Blob` for map from `Nat` to `Blob`.
    /// `t` should be a valid red-black tree and correspond to array `a`. This function doesn't do validation.
    /// ```
    /// let e = Enumeration.Enumeration();
    /// assert(e.add("abc") == 0);
    /// assert(e.add("aaa") == 1);
    /// e.unsafeUnshare(e.share()); // Nothing changed
    /// ```
    /// Runtime: O(1)
    public func unsafeUnshare(data : (Tree, [var Blob], Nat)) {
      tree := data.0;
      array := data.1;
      size_ := data.2;
    };
  };
};
