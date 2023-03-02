import Prim "mo:prim";
import Array "mo:base/Array";

module {
  /// Unique `Id` of element added to the `Queue`.
  public type Id = Nat;

  type Node<X> = {
    #node : {
      value : X;
      var next : Node<X>;
    };
    #leaf;
  };

  /// FIFO queue implemented as singly linked list.
  ///
  /// Example:
  /// ```motoko
  /// let queue = Queue.Queue<Nat>();
  /// ```
  public class Queue<X>() {
    var start = #leaf : Node<X>;
    var end = #leaf : Node<X>;
    var pushes = 0;
    var size_ = 0;

    /// Returns element with `id` in queue and `null` if the element was already deleted.
    ///
    /// Example:
    /// ```motoko
    /// let queue = Queue.Queue<Nat>();
    /// ignore queue.enqueue(0);
    /// let id = queue.enqueue(1);
    /// ignore queue.dequeue();
    /// assert queue.get(id) == ?1;
    /// ```
    ///
    /// Runtime: `O(n)` where `n` is the number of elements in the queue.
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

    /// Returns position from the beginning of an element with `id` returned by `enqueue`.
    ///
    /// Example:
    /// ```motoko
    /// let queue = Queue.Queue<Nat>();
    /// assert queue.index_of(queue.enqueue(1)) == ?0;
    /// ```
    ///
    /// Runtime: `O(1)`.
    public func index_of(id : Id) : ?Nat {
      if (id >= pushes or pushes - id > size_) null else ?(size_ + id - pushes);
    };

    /// Inserts element to the back of the queue.
    /// Returns unique among all the `enqueue` opertions `id` of the inserted element.
    ///
    /// Example:
    /// ```motoko
    /// let queue = Queue.Queue<Nat>();
    /// ignore queue.enqueue(1);
    /// assert queue.dequeue() == ?1;
    /// ```
    ///
    /// Runtime: `O(1)`.
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

    /// Returns `null` if `queue` is empty. Otherwise, it returns first element in the queue.
    ///
    /// Example:
    /// ```motoko
    /// let queue = Queue.Queue<Nat>();
    /// ignore queue.enqueue(1);
    /// assert queue.peek() == ?1;
    /// ```
    ///
    /// Runtime: `O(1)`.
    public func peek() : ?X {
      let #node { value } = start else return null;
      ?value;
    };

    /// Remove the element on the front end of a queue.
    /// Returns `null` if `queue` is empty. Otherwise, it returns removed element.
    ///
    /// Example:
    /// ```motoko
    /// let queue = Queue.Queue<Nat>();
    /// ignore queue.enqueue(1);
    /// assert queue.dequeue() == ?1;
    /// ```
    ///
    /// Runtime: `O(1)`.
    public func dequeue() : ?X {
      let #node x = start else return null;

      start := x.next;
      x.next := #leaf;

      size_ -= 1;

      ?x.value;
    };

    /// Returns number of elements in the queue.
    ///
    /// Example:
    /// ```motoko
    /// let queue = Queue.Queue<Nat>();
    /// ignore queue.enqueue(1);
    /// assert queue.size() == 1;
    /// ```
    ///
    /// Runtime: `O(1)`.
    public func size() : Nat = size_;
  };
};
