import Debug "mo:base/Debug";
import I "mo:base/Iter";
import List "mo:base/List";
import Nat "mo:base/Nat";
import O "mo:base/Order";
import Bool "mo:base/Bool";

module {
  public type Color = { #red; #black };

  public type Node<K, V> = {
    #leaf;
    #node : (Color, Node<K, V>, (K, ?V), Node<K, V>);
  };

  public type LLLRBTree<K, V> = {
    var root : Node<K, V>;
    compare : (K, K) -> O.Order;
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
              #node(#black, left_right, pair, right)
            )
          };
          case (_) #node(color, left, pair, right);
        };
      };
      case (_) #node(color, left, pair, right);
    };
  };

  func balance_right<K, V>(color : Color, left : Node<K, V>, pair : (K, ?V), right : Node<K, V>) : Node<K, V> {
    switch (color, left, right) {
      case(
        #black,
        #node(#red, left_left, left_pair, left_right),
        #node(#red, right_left, right_pair, right_right)
      ) {
        #node(
          #red,
          #node(#red, left_left, left_pair, left_right),
          pair,
          #node(#red, right_left, right_pair, right_right)
        );
      };
      case(
        color,
        left,
        #node(#red, right_left, right_pair, right_right)
      ) {
        #node(
          color,
          #node(#red, left, pair, right_left),
          right_pair,
          right_right
        );
      };
      case (_, _, _) {
        #node(color, left, pair, right);
      }
    };
  };

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
}
