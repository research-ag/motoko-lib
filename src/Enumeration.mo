import Blob "mo:base/Blob";
import Array "mo:base/Array";
import Prim "mo:⛔";

module {
  public type Tree = {
    #red : (Tree, Nat, Tree);
    #black : (Tree, Nat, Tree);
    #leaf;
  };

  /// Bidirectional enumeration of `Blob`s in order they are added.
  /// For map from `Blob` to index `Nat` it's implemented as red-black tree, for map from index `Nat` to `Blob` the implementation is an array.
  public class Enumeration() {
    private var array = ([var ""] : [var Blob]);
    private var size_ = 0;

    private var tree = (#leaf : Tree);

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

    /// Add `key` to enumeration. Returns `size` if the key in new to the enumeration and index of key in enumeration otherwise.
    public func add(key : Blob) : Nat {
      var index = size_;

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

      if (index == size_) {
        if (size_ == array.size()) {
          // sqrt(2) ~ 90 / 77
          array := Array.tabulateVar<Blob>(((size_ * 90) + 77 - 1) / 77, func(i) = if (i < size_) { array[i] } else { "" });
        };
        array[size_] := key;
        size_ += 1;
      };

      index;
    };

    /// Returns `?index` where `index` is the index of `key` in order it was added to enumeration, or `null` it `key` wasn't added.
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
    public func get(index : Nat) : Blob {
      if (index < size_) { array[index] } else {
        Prim.trap("Index out of bounds");
      };
    };

    /// Returns number of unique keys added to enumration.
    public func size() : Nat = size_;

    /// Returns pair of red-black tree for map from `Blob` to `Nat` and array of `Blob` for map from `Nat` to `Blob`.
    public func share() : (Tree, [var Blob], Nat) = (tree, array, size_);

    /// Sets internal content from red-black tree for map from `Blob` to `Nat` and array of `Blob` for map from `Nat` to `Blob`.
    /// `t` should be a valid red-black tree and correspond to array `a`. This function doesn't do validation.
    public func unsafeUnshare(data : (Tree, [var Blob], Nat)) {
      tree := data.0;
      array := data.1;
      size_ := data.2;
    };
  };
};
