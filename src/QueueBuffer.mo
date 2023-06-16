import { xxx } "mo:base/Prelude";

import Order "mo:base/Order";
import Option "mo:base/Option";
import Iter "mo:base/Iter";
import List "mo:base/List";
import Int "mo:base/Int";


// why (?!!) the Id (the `pushes`) is the part of Queue state, not an `X`
// field??? How queue id state consintency supposed to be handled on queue
// re-creation or in case of several queues?

// Should Id be just a Nat, or some ordered salted randomized UUID?

// What in general is the common approach to mutability, state and consistency
// management, and values passing around (composing)?

//
// - - - -
//

// Actually, we can't make the `BufferedQueue` a static module with static
// functions that passes a `BufferedQueueRepr` representation instance value
// around.  Because it countain mutable fields, and Motoko have no other
// abstract types except objects.  So we supposed to pass those functions with
// data as a dynamic binded methods to avoid breaking encapsulation (providing
// an access to an instance of the representation itself allow leaking the
// representation, and so ability to broke it's state).

module {

  public class Id(value : Nat) { public let val = value };

  type Node<X> = { value : X; next : Queue<X> };
  type Queue<X> = { var node : ?Node<X> };  // { node: ?Node<X>; setLast: Node<X> -> () }

  type BufferedQueueRepr<X> = {
    var queue : Queue<X>;
    var buffer : Queue<X>;

    var first : Id;

    cache : {
      var last : Queue<X>;
      var size : Nat;
      var bufferSize : Nat;
    }
  };

  public type Status<X> = { #Prun; #Buf : X; #Que : X };

  type BufferedQueue<X> = {
    toIter : Queue<X> -> Iter.Iter<X>;
    get : Id -> ?Status<X>;
    indexOf : Id -> ?Status<Nat>;

    peek : () -> ?X;
    pop : () -> ?X;
    push : X -> Id;
    put : X -> ();
    size : () -> Nat;

    peekValues : Nat -> ?List.List<X>;
    popValues : Nat -> ?List.List<X>;
    pushValues : Iter.Iter<X> -> Id;
    putValues : Iter.Iter<X> -> ();

    prune: () -> Bool;
    pruneAll: () -> ();
    pruneTo: Id -> ();
  };

  public func bufferedQueueFrom<X>(first : Id) : BufferedQueue<X> = object {
      func empty() : Queue<X> = { var node = null };

      let bufferedQueue : BufferedQueueRepr<X> = do {
        let queue = empty();

        { var queue;
          var buffer = queue;

          var first;

          cache = {
            var last = queue;
            var size = 0;
            var bufferSize = 0;
          }
        }
      };

      public func toIter(queue : Queue<X>) : Iter.Iter<X> {
        var state = queue;
        { next = func () : ?X = Option.map<Node<X>, X>(state.node,
          func ({ value; next }) { state := next; value } ) }
      };

      func getFrom(queue : Queue<X>, id : Nat) : ?X = do ? {
        var queue_ = queue;
        var id_ = 0;

        while (id_ < id) {
          queue_ := queue_.node!.next;
          id_ += 1;
        };
        queue_.node!.value;
      };

      public func get(id : Id) : ?Status<X> = do ? {
        switch (indexOf(id)!) {
          case (#Que index_) #Que(getFrom(bufferedQueue.queue, index_)!);
          case (#Buf index_) #Buf(getFrom(bufferedQueue.buffer, index_)!);
          case (#Prun) #Prun;
        };
      };

      public func indexOf(id : Id) : ?Status<Nat> = do ? {
        if (id.val >= bufferedQueue.first.val + bufferedQueue.cache.size) null!;
        let index : Int = id.val - bufferedQueue.first.val;

        if (index >= 0) #Que(Int.abs index) else {
          let index_ : Int = bufferedQueue.cache.bufferSize + index;
          if (index_ >= 0) #Buf(Int.abs index_) else #Prun
        }
      };


      public func peek() : ?X = do ? { bufferedQueue.queue.node!.value };

      public func pop() : ?X = do ? {
        let { value; next } = bufferedQueue.queue.node!;
        bufferedQueue.queue := next;
        bufferedQueue.cache.size -= 1;
        bufferedQueue.cache.bufferSize += 1;
        bufferedQueue.first := Id(bufferedQueue.first.val + 1);
        value;
      };

      public func push(value : X) : Id {
        let node = { value; next = empty() };
        bufferedQueue.cache.last.node := ?node;
        bufferedQueue.cache.last := node.next;
        bufferedQueue.cache.size += 1;
        Id(bufferedQueue.first.val + bufferedQueue.cache.size - 1);
      };

      public func put(value : X) = ignore push value;
      public func size() : Nat = bufferedQueue.cache.size;


      public func peekValues(size : Nat) : ?List.List<X> = xxx();
      public func popValues(size : Nat) : ?List.List<X> = xxx();
      public func pushValues(values : Iter.Iter<X>) : Id = xxx();
      public func putValues(values : Iter.Iter<X>) = xxx();


      public func prune() : Bool =
        bufferedQueue.cache.bufferSize > 0 and Option.isSome(do ? {
          bufferedQueue.buffer := bufferedQueue.buffer.node!.next;
          bufferedQueue.cache.bufferSize -= 1;
        });

      public func pruneAll() = xxx();
      public func pruneTo(id : Id) = xxx();
  };

  public func BufferedQueue<X>() : BufferedQueue<X> = bufferedQueueFrom<X>(Id 0);
}
