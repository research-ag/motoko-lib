import Prim "mo:prim";
import Array "mo:base/Array";

module {
  /// Unique `Id` of element added to the `Queue`.
  public type Id = Nat;

  type Node<X> = ?{
    value : X;
    var next : Node<X>;
  };

  /// FIFO queue implemented as singly linked list.
  ///
  /// Example:
  /// ```motoko
  /// let queue = Queue.Queue<Nat>();
  /// ```
  public class Queue<X>() {
    var head = null : Node<X>;
    var tail = null : Node<X>;
    var pushes = 0;
    var size_ = 0;

    /// Returns element with `id` in queue and `null` if the element was already deleted.
    ///
    /// Example:
    /// ```motoko
    /// let queue = Queue.Queue<Nat>();
    /// ignore queue.push(0);
    /// let id = queue.push(1);
    /// ignore queue.pop();
    /// assert queue.get(id) == ?1;
    /// ```
    ///
    /// Runtime: `O(n)` where `n` is the number of elements in the queue.
    public func get(id : Id) : ?X {
      let ?index = index_of(id) else return null;
      let ?s = head else Prim.trap("Internal error in Queue");

      var i = 0;
      var node = s;
      while (i < index) {
        let ?next = node.next else Prim.trap("Internal error in Queue");
        node := next;
        i += 1;
      };
      ?node.value;
    };

    /// Returns position from the beginning of an element with `id` returned by `push`.
    ///
    /// Example:
    /// ```motoko
    /// let queue = Queue.Queue<Nat>();
    /// assert queue.index_of(queue.push(1)) == ?0;
    /// ```
    ///
    /// Runtime: `O(1)`.
    public func index_of(id : Id) : ?Nat {
      if (id >= pushes or pushes > size_ + id) null else ?(size_ + id - pushes);
    };

    /// Inserts element to the back of the queue.
    /// Returns unique among all the `push` opertions `id` of the inserted element.
    ///
    /// Example:
    /// ```motoko
    /// let queue = Queue.Queue<Nat>();
    /// ignore queue.push(1);
    /// assert queue.pop() == ?1;
    /// ```
    ///
    /// Runtime: `O(1)`.
    public func push(value : X) : Id {
      switch (tail) {
        case (null) {
          let node = ?{
            value = value;
            var next = null;
          } : Node<X>;
          tail := node;
          head := node;
        };
        case (?x) {
          let node = ?{
            value = value;
            var next = null;
          } : Node<X>;
          x.next := node;
          tail := node;
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
    /// ignore queue.push(1);
    /// assert queue.peek() == ?1;
    /// ```
    ///
    /// Runtime: `O(1)`.
    public func peek() : ?X {
      let ?{ value } = head else return null;
      ?value;
    };

    /// Remove the element on the front tail of a queue.
    /// Returns `null` if `queue` is empty. Otherwise, it returns removed element.
    ///
    /// Example:
    /// ```motoko
    /// let queue = Queue.Queue<Nat>();
    /// ignore queue.push(1);
    /// assert queue.pop() == ?1;
    /// ```
    ///
    /// Runtime: `O(1)`.
    public func pop() : ?X {
      let ?x = head else return null;

      head := x.next;
      switch (head) {
        case (null) tail := null;
        case (_) {};
      };

      size_ -= 1;

      ?x.value;
    };

    /// Returns number of elements in the queue.
    ///
    /// Example:
    /// ```motoko
    /// let queue = Queue.Queue<Nat>();
    /// ignore queue.push(1);
    /// assert queue.size() == 1;
    /// ```
    ///
    /// Runtime: `O(1)`.
    public func size() : Nat = size_;
  };
};
