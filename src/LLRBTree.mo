import Debug "mo:base/Debug";
import I "mo:base/Iter";
import List "mo:base/List";
import Nat "mo:base/Nat";
import O "mo:base/Order";
import Bool "mo:base/Bool";
import Prim "mo:⛔";
import Option "mo:base/Option";
import Iter "mo:base/Iter";
import Array "mo:base/Array";

module {
  type Color = { #red; #black };

  type Node<K, V> = {
    #leaf;
    #node : (Color, Node<K, V>, (K, V), Node<K, V>);
  };

  public type LLRBTree<K, V> = {
    var root : Node<K, V>;
    compare : (K, K) -> O.Order;
  };

  public func new<K, V>(compare : (K, K) -> O.Order) : LLRBTree<K, V> {
    {
      var root = #leaf;
      compare = compare;
    };
  };

  func turn_black<K, V>(node : Node<K, V>) : Node<K, V> {
    switch (node) {
      case (#node(color, a, b, c)) #node(#black, a, b, c);
      case (#leaf) #leaf;
    };
  };

  func turn_red<K, V>(node : Node<K, V>) : Node<K, V> {
    switch (node) {
      case (#node(color, a, b, c)) #node(#red, a, b, c);
      case (#leaf) #leaf;
    };
  };

  func is_black_left_black<K, V>(node : Node<K, V>) : Bool {
    switch (node) {
      case (#node(#black, #leaf, _, _)) true;
      case (#node(#black, #node(#black, _, _, _), _, _)) true;
      case (_) false;
    };
  };

  func balance_left<K, V>(color : Color, left : Node<K, V>, pair : (K, V), right : Node<K, V>) : Node<K, V> {
    switch (color, left) {
      case (#black, #node(#red, #node(#red, a, b, c), left_pair, left_right)) {
        #node(
          #red,
          #node(#black, a, b, c),
          left_pair,
          #node(#black, left_right, pair, right),
        );
      };
      case (_) #node(color, left, pair, right);
    };
  };

  func balance_right<K, V>(color : Color, left : Node<K, V>, pair : (K, V), right : Node<K, V>) : Node<K, V> {
    switch (color, left, right) {
      case (
        #black,
        #node(#red, left_left, left_pair, left_right),
        #node(#red, right_left, right_pair, right_right),
      ) {
        #node(
          #red,
          #node(#black, left_left, left_pair, left_right),
          pair,
          #node(#black, right_left, right_pair, right_right),
        );
      };
      case (
        color,
        left,
        #node(#red, right_left, right_pair, right_right),
      ) {
        #node(
          color,
          #node(#red, left, pair, right_left),
          right_pair,
          right_right,
        );
      };
      case (_, _, _) {
        #node(color, left, pair, right);
      };
    };
  };

  public func insert<K, V>(tree : LLRBTree<K, V>, key : K, value : V) {
    func insert<K, V>(key : K, value : V, node : Node<K, V>, compare : (K, K) -> O.Order) : Node<K, V> {
      switch (node) {
        case (#node(color, left, (key_in, value_in), right)) {
          switch (compare(key, key_in)) {
            case (#less) {
              balance_left(color, insert(key, value, left, compare), (key_in, value_in), right);
            };
            case (#equal) #node(color, left, (key, value), right);
            case (#greater) {
              balance_right(color, left, (key_in, value_in), insert(key, value, right, compare));
            };
          };
        };
        case (#leaf) #node(#red, #leaf, (key, value), #leaf);
      };
    };

    tree.root := turn_black(insert(key, value, tree.root, tree.compare));
  };

  public func delete<K, V>(tree : LLRBTree<K, V>, key : K) {
    func is_red<K, V>(node : Node<K, V>) : Bool {
      switch (node) {
        case (#node(#red, _, _, _)) true;
        case _ false;
      };
    };

    func minimum<K, V>(node : Node<K, V>) : (K, V) {
      switch (node) {
        case (#node(_, #leaf, pair, _)) pair;
        case (#node(_, left, _, _)) minimum(left);
        case (_) Prim.trap("");
      };
    };

    func delete_min<K, V>(node : Node<K, V>) : Node<K, V> {
      switch (node) {
        case (#node(#red, #leaf, _, #leaf)) #leaf;
        case (#node(#red, left, pair, right)) {
          switch(left) {
            case (#node(#red, _, _, _)) {
              #node(#red, delete_min(left), pair, right);
            };
            case (#node(#black, left_left, left_pair, left_right)) {
              if (is_black_left_black(left)) {
                switch (right) {
                  case (#node(#black, #node(#red, right_left_left, right_left_pair, right_left_right), right_pair, right_right)) {
                    #node(
                      #red,
                      #node(#black, delete_min(turn_red(left)), pair, right_left_left),
                      right_left_pair,
                      #node(#black, right_left_right, right_pair, right_right),
                    );
                  };
                  case (_) {
                    balance_right(#black, delete_min(turn_red(left)), pair, turn_red(right));
                  };
                };
              } else {
                #node(#red, #node(#black, delete_min(left_left), left_pair, left_right), pair, right);
              };
            };
            case (#leaf) Prim.trap("");
          };
        };
        case (_) Prim.trap("");
      };
    };

    func delete_less<K, V>(key : K, color : Color, left : Node<K, V>, pair : (K, V), right : Node<K, V>, compare : (K, K) -> O.Order) : Node<K, V> {
      if (color == #red and is_black_left_black(left)) {
        switch (right) {
          case (#node(#black, #node(#red, right_left_left, right_left_pair, right_left_right), right_pair, right_right)) {
            #node(#red, #node(#black, delete(key, turn_red(left), compare), pair, right_left_left), right_left_pair, #node(#black, right_left_right, right_pair, right_right));
          };
          case (_) {
            balance_right(#black, delete(key, turn_red(left), compare), pair, turn_red(right));
          };
        };
      } else {
        #node(color, delete(key, left, compare), pair, right);
      };
    };

    func delete_equal<K, V>(key : K, color : Color, left : Node<K, V>, pair : (K, V), right : Node<K, V>, compare : (K, K) -> O.Order) : Node<K, V> {
      switch (color, left, right, is_black_left_black(right)) {
        case (#red, #leaf, #leaf, _) #leaf;
        case (color, #node(#red, left_left, left_pair, left_right), right, _) {
          balance_right(color, left_left, left_pair, delete(key, #node(#red, left_right, pair, right), compare));
        };
        case (#red, left, right, true) {
          switch (left) {
            case (#node(#black, #node(#red, a, b, c), left_pair, left_right)) {
              balance_right(#red, #node(#black, a, b, c), left_pair, balance_right(#black, left_right, minimum(right), delete_min(turn_red(right))));
            };
            case (_) {
              balance_right(#black, turn_red(left), minimum(right), delete_min(turn_red(right)));
            };
          };
        };
        case (#red, left, #node(#black, right_left, right_pair, right_right), _) {
          #node(#red, left, minimum(right), #node(#black, delete_min(right_left), right_pair, right_right));
        };
        case (_) {
          Prim.trap("");
        };
      };
    };

    func delete_greater<K, V>(key : K, color : Color, left : Node<K, V>, pair : (K, V), right : Node<K, V>, compare : (K, K) -> O.Order) : Node<K, V> {
      switch (left) {
        case (#node(#red, left_left, left_pair, left_right)) {
          balance_right(color, left_left, left_pair, delete(key, #node(#red, left_right, pair, right), compare));
        };
        case (_) {
          assert (color == #red);
          if (is_black_left_black(right)) {
            switch (left) {
              case (#node(#black, #node(#red, a, b, c), left_pair, left_right)) {
                #node(#red, #node(#black, a, b, c), left_pair, balance_right(#black, left_right, pair, delete(key, turn_red(right), compare)));
              };
              case (_) {
                balance_right(#black, turn_red(left), pair, delete(key, turn_red(right), compare));
              };
            };
          } else {
            #node(#red, left, pair, delete(key, right, compare));
          };
        };
      };
    };

    func delete<K, V>(key : K, node : Node<K, V>, compare : (K, K) -> O.Order) : Node<K, V> {
      switch (node) {
        case (#leaf) #leaf;
        case (#node(color, left, (key_in, value_in), right)) {
          switch (compare(key, key_in)) {
            case (#less) delete_less(key, color, left, (key_in, value_in), right, compare);
            case (#equal) delete_equal(key, color, left, (key_in, value_in), right, compare);
            case (#greater) delete_greater(key, color, left, (key_in, value_in), right, compare);
          };
        };
      };
    };

    tree.root := turn_black(delete(key, turn_red(tree.root), tree.compare));
  };

  public func get<K, V>(tree : LLRBTree<K, V>, key : K) : ?V {
    func get(node : Node<K, V>, key : K) : ?V {
      switch (node) {
        case (#node(_, left, (key_in, value), right)) {
          switch (tree.compare(key, key_in)) {
            case (#less) get(left, key);
            case (#equal) ?value;
            case (#greater) get(right, key);
          };
        };
        case (#leaf) null;
      };
    };

    get(tree.root, key);
  };

  public func toArray<K, V>(tree : LLRBTree<K, V>) : [(K, V)] {
    func toArray(node : Node<K, V>) : [(K, V)] {
      switch (node) {
        case (#leaf) [];
        case (#node(_, left, pair, right)) {
          Array.flatten([toArray(left), [pair], toArray(right)]);
        };
      };
    };

    toArray(tree.root);
  };

  public func valid<K, V>(tree : LLRBTree<K, V>) : Bool {
    func is_black_same<K, V>(node : Node<K, V>) : ?Nat {
      switch (node) {
        case (#leaf) ?0;
        case (#node(color, left, _, right)) {
          let a = if (color == #red) { 0 } else { 1 };
          switch(is_black_same(left), is_black_same(right)) {
            case (?x, ?y) {
              if (x == y) { ?(x + a) } else { null };
            };
            case (_, _) null;
          };
        };
      };
    };

    func is_red_separate<K, V>(color : Color, node : Node<K, V>) : Bool {
      switch (color, node) {
        case (_, #leaf) true;
        case (#red, #node(#red, _, _, _)) false;
        case (_, #node(color, left, _, right)) is_red_separate(color, left) and is_red_separate(color, right);
      };
    };

    func is_left_lean<K, V>(node : Node<K, V>) : Bool {
      switch (node) {
        case (#leaf) true;
        case (#node(#black, _, _, #node(#red, _, _, _))) false;
        case (#node(_, left, _, right)) is_left_lean(left) and is_left_lean(right);
      }
    };

    func is_ordered<K, V>(tree : LLRBTree<K, V>) : Bool {
      let a = toArray(tree);
      var i = 0;

      while (i + 1 < a.size()) {
        if (tree.compare(a[i].0, a[i + 1].0) != #less) return false;
        i += 1;
      };
      return true;
    };

    not Option.isNull(is_black_same(tree.root)) and is_red_separate(#black, tree.root) and is_left_lean(tree.root) and is_ordered(tree);
  };

  func print<K, V>(node : Node<K, V>) : Text {
    switch (node) {
      case (#leaf) { "" };
      case (#node(color, left, pair, right)) {
        "(" # print(left) # (if (color == #black) { "black" } else { "red" }) # print(right) # ")";
      };
    };
  };
};
