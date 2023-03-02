import Prim "mo:prim";
import Array "mo:base/Array";

module {
  public type Id = Nat;

  type Node<X> = {
    #node : {
      value : X;
      var next : Node<X>;
    };
    #leaf;
  };

  public class Queue<X>() {
    var start = #leaf : Node<X>;
    var end = #leaf : Node<X>;
    var pushes = 0;
    var size_ = 0;

    public func get(id : Id) : ?X {
      let ?index = index_of(id) else return null;
      let #node s = start else Prim.trap("Internal error in Queue");

      var i = 0;
      var node = s;
      while (i < index) {
        let #node next = node.next else Prim.trap("Internal error in Queue");
        node := next;
        i += 1;
      };
      ?node.value;
    };

    public func index_of(id : Id) : ?Nat {
      if (id >= pushes or pushes - id > size_) null else ?(size_ + id - pushes);
    };

    public func enqueue(value : X) : Id {
      switch (end) {
        case (#leaf) {
          let node = #node {
            value = value;
            var next = #leaf;
          } : Node<X>;
          end := node;
          start := node;
        };
        case (#node x) {
          let node = #node {
            value = value;
            var next = #leaf;
          } : Node<X>;
          x.next := node;
          end := node;
        };
      };

      pushes += 1;
      size_ += 1;

      pushes - 1;
    };

    public func peek() : ?X {
      let #node { value } = start else return null;
      ?value;
    };

    public func dequeue() : ?X {
      let #node x = start else return null;

      start := x.next;
      x.next := #leaf;
      
      size_ -= 1;

      ?x.value;
    };

    public func size() : Nat = size_;
  };
};
