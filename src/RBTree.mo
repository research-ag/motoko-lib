import Debug "mo:base/Debug";
import I "mo:base/Iter";
import List "mo:base/List";
import Nat "mo:base/Nat";
import O "mo:base/Order";
import Bool "mo:base/Bool";
import Prim "mo:⛔";

module {
  public type Color = { #red; #black };

  public type Node<K, V> = {
    #leaf;
    #node : (Color, Node<K, V>, (K, ?V), Node<K, V>);
  };

  public type LLRBTree<K, V> = {
    var root : Node<K, V>;
    compare : (K, K) -> O.Order;
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

  func isBlackLeftBlack<K, V>(node : Node<K, V>) : Bool {
    switch (node) {
      case (#node(#black, #leaf, _, _)) true;
      case (#node(#black, #node(#black, _, _, _), _, _)) true;
      case (_) false;
    };
  };

  func isBlackLeftRed<K, V>(node : Node<K, V>) : Bool {
    switch (node) {
      case (#node(#black, #node(#red, _, _, _), _, _)) true;
      case (_) false;
    };
  };

  func balance_left<K, V>(color : Color, left : Node<K, V>, pair : (K, ?V), right : Node<K, V>) : Node<K, V> {
    switch (color, left) {
      case (#black, #node(#red, left_left, left_pair, left_right)) {
        switch (left_left) {
          case (#node(#red, a, b, c)) {
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
      case (_) #node(color, left, pair, right);
    };
  };

  func balance_right<K, V>(color : Color, left : Node<K, V>, pair : (K, ?V), right : Node<K, V>) : Node<K, V> {
    switch (color, left, right) {
      case (
        #black,
        #node(#red, left_left, left_pair, left_right),
        #node(#red, right_left, right_pair, right_right),
      ) {
        #node(
          #red,
          #node(#red, left_left, left_pair, left_right),
          pair,
          #node(#red, right_left, right_pair, right_right),
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
        case (#leaf) #node(#red, #leaf, (key, ?value), #leaf);
        case (#node(color, left, (key_in, value_in), right)) {
          switch (compare(key, key_in)) {
            case (#less) {
              balance_left(color, insert(key, value, left, compare), (key_in, value_in), right);
            };
            case (#equal) #node(color, left, (key, ?value), right);
            case (#greater) {
              balance_right(color, left, (key_in, value_in), insert(key, value, right, compare));
            };
          };
        };
      };
    };

    tree.root := turn_black(insert(key, value, tree.root, tree.compare));
  };

  public func delete<K, V>(tree : LLRBTree<K, V>, key : K) {
    func minimum<K, V>(node : Node<K, V>) : (K, ?V) {
      switch (node) {
        case (#node(_, #leaf, pair, _)) pair;
        case (#node(_, left, _, _)) minimum(left);
        case (_) Prim.trap("");
      }
    };

    func delete_min<K, V>(key : K, node : Node<K, V>, compare : (K, K) -> O.Order) : Node<K, V> {
      switch (node) {
        case (#node(#red, #leaf, _, #leaf)) #leaf;
        case (#node(#red, #node(#black, left_left_, left_pair, left_right), pair, right)) {
          
        };
        case (_) Prim.trap("");
      }
    };
    
    func delete_less<K, V>(key : K, color : Color, left : Node<K, V>, pair : (K, ?V), right : Node<K, V>, compare : (K, K) -> O.Order) : Node<K, V> {
      if (color == #red and isBlackLeftBlack(left)) {
        switch (right) {
          case (#node(#black, #node(#red, right_left_left, right_left_pair, right_left_right), right_pair, right_right)) {
            #node(#red, #node(#black, delete(key, turn_red(left), compare), pair, right_left_left), right_left_pair, #node(#black, right_left_right, right_pair, right_right))
          };
          case (_) {
            balance_right(#black, delete(key, turn_red(left), compare), pair, turn_red(right));
          }
        }
      } else {
        #node(color, delete(key, left, compare), pair, right);
      };
      
      // switch (color, isBlackLeftBlack(left), right) {
      //   case (#red, true, #node(#black, #node(#red, right_left_left, right_left_pair, right_left_right), right_pair, right_right)) {
      //     if (isBlackLeftRed(right)) {
      //       #node(#red, #node(#black, delete(key, turn_red(left), compare), pair, right_left_left), right_left_pair, #node(#black, right_left_right, right_pair, right_right))
      //     } else {
      //       balance_right(#black, delete(key, turn_red(left), compare), pair, turn_red(right));
      //     }
      //   };
      //   case (_) #node(color, delete(key, left, compare), pair, right);
      // };
    };

    func delete_equal<K, V>(key : K, color : Color, left : Node<K, V>, pair : (K, ?V), right : Node<K, V>, compare : (K, K) -> O.Order) : Node<K, V> {
      switch (color, left, right) {
        case (#red, #leaf, #leaf) #leaf;
        case (_) {
          switch(left) {
            case (#node(#red, left_left, left_pair, left_right)) {
              balance_right(color, left_left, left_pair, delete(key, #node(#red, left_right, pair, right), compare));
            };
            case (_) {

            };
          }
        }
      }
    };

    func delete_greater<K, V>(key : K, color : Color, left : Node<K, V>, pair : (K, ?V), right : Node<K, V>, compare : (K, K) -> O.Order) : Node<K, V> {
      switch(left) {
        case (#node(#red, left_left, left_pair, left_right)) {
          balance_right(color, left_left, left_pair, delete(key, #node(#red, left_right, pair, right), compare));
        };
        case (_) {
          assert(color == #red);
          switch (isBlackLeftBlack(right), left) {
            case (true, #node(#black, #node(#red, a, b, c), left_pair, left_right)) {
              if (isBlackLeftRed(left)) {
                #node(#red, #node(#black, a, b, c), left_pair, balance_right(#black, left_right, pair, delete(key, turn_red(right), compare)));
              } else {
                balance_right(#black, turn_red(left), pair, delete(key, turn_red(right), compare));
              };
            };
            case (_) {
              #node(#red, left, pair, delete(key, right, compare));
            };
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
  }
};
