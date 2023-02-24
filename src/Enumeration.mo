import Blob "mo:base/Blob";
import Array "mo:base/Array";
import Prim "mo:⛔";

module {
  public type Tree = {
    #node : ({ #R; #B }, Tree, Nat, Tree);
    #leaf;
  };

  public class Enumeration() {
    private var array = ([var ""] : [var Blob]);
    private var size = 0;

    public var tree = (#leaf : Tree);

    func get_in_tree(x : Blob, t : Tree) : ?Nat {
      switch t {
        case (#leaf) { null };
        case (#node(c, l, y, r)) {
          switch (Blob.compare(x, array[y])) {
            case (#less) { get_in_tree(x, l) };
            case (#equal) { ?y };
            case (#greater) { get_in_tree(x, r) };
          };
        };
      };
    };

    func lbalance(left : Tree, y : Nat, right : Tree) : Tree {
      switch (left, right) {
        case (#node(#R, #node(#R, l1, y1, r1), y2, r2), r) {
          #node(
            #R,
            #node(#B, l1, y1, r1),
            y2,
            #node(#B, r2, y, r),
          );
        };
        case (#node(#R, l1, y1, #node(#R, l2, y2, r2)), r) {
          #node(
            #R,
            #node(#B, l1, y1, l2),
            y2,
            #node(#B, r2, y, r),
          );
        };
        case _ {
          #node(#B, left, y, right);
        };
      };
    };

    func rbalance(left : Tree, y : Nat, right : Tree) : Tree {
      switch (left, right) {
        case (l, #node(#R, l1, y1, #node(#R, l2, y2, r2))) {
          #node(
            #R,
            #node(#B, l, y, l1),
            y1,
            #node(#B, l2, y2, r2),
          );
        };
        case (l, #node(#R, #node(#R, l1, y1, r1), y2, r2)) {
          #node(
            #R,
            #node(#B, l, y, l1),
            y1,
            #node(#B, r1, y2, r2),
          );
        };
        case _ {
          #node(#B, left, y, right);
        };
      };
    };

    public func add(x : Blob) {
      func ins(tree : Tree) : Tree {
        switch tree {
          case (#leaf) {
            #node(#R, #leaf, size - 1, #leaf);
          };
          case (#node(#B, left, y, right)) {
            switch (Blob.compare(x, array[y])) {
              case (#less) {
                lbalance(ins left, y, right);
              };
              case (#greater) {
                rbalance(left, y, ins right);
              };
              case (#equal) {
                #node(#B, left, size - 1, right);
              };
            };
          };
          case (#node(#R, left, y, right)) {
            switch (Blob.compare(x, array[y])) {
              case (#less) {
                #node(#R, ins left, y, right);
              };
              case (#greater) {
                #node(#R, left, y, ins right);
              };
              case (#equal) {
                #node(#R, left, size - 1, right);
              };
            };
          };
        };
      };

      if (size == array.size()) {
        array := Array.tabulateVar<Blob>(size * 2, func(i) = if (i < size) { array[i] } else { "" });
      };
      array[size] := x;
      size += 1;

      tree := switch (ins tree) {
        case (#node(#R, left, y, right)) {
          #node(#B, left, y, right);
        };
        case other { other };
      };
    };

    public func get_inverse(key : Blob) : ?Nat {
      get_in_tree(key, tree);
    };

    public func get(i : Nat) : Blob {
      if (i < size) { array[i]; } else { Prim.trap("Index out of bounds"); };
    };

    public func toArray() : [var Blob] {
      array;
    };
  };
};
