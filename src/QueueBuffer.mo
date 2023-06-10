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

  class Idx<A, X>(value : X, add : (X, X) -> X) = self {
    public func abstract(a : A) : A = a;
    public let val = value;

    public func inc(x : X) : Idx<A, X> =
      ( func incOf(this : Idx<A, X>) : X -> Idx<A, X> = func (x : X) = let self =
        { this with val = add(this.val, x)
        ; inc = func (x : X) : Idx<A, X> = (incOf self) x }
      ) self x;
  };

  type Status<X> = { #Prun; #Buf : X; #Que : X };

  type Id<A> = Idx<A, Nat>;

  type BufferedQueue_<A, X> = {
    toIter : Queue<X> -> Iter.Iter<X>;
    get : Id<A> -> ?Status<X>;
    indexOf : Id<A> -> ?Status<Nat>;

    peek : () -> ?X;
    pop : () -> ?X;
    push : X -> Id<A>;
    put : X -> ();
    size : () -> Nat;

    peekValues : Nat -> ?List.List<X>;
    popValues : Nat -> ?List.List<X>;
    pushValues : Iter.Iter<X> -> Id<A>;
    putValues : Iter.Iter<X> -> ();

    prune: () -> ();
    pruneAll: () -> ();
    pruneTo: Id<A> -> ();
  };

  type Node<X> = { value : X; next : Queue<X> };
  type Queue<X> = { var node : ?Node<X> };

  type BufferedQueueRepr<A, X> = {
    queue : Queue<X>;
    buffer : Queue<X>;

    var first : Id<A>;

    cache : {
      var last : Queue<X>;
      var size : Nat;
      var bufferSize : Nat;
    }
  };

  public type BufferedQueue<X> = BufferedQueue_<None, X>;

  public func BufferedQueue<X>() : BufferedQueue<X> =
    ( func <A, X>(first : Id<A>) : BufferedQueue_<A, X> = object {
      func empty() : Queue<X> = { var node = null };

      var bufferedQueue : BufferedQueueRepr<A, X> = do {
        let queue = empty();

        { queue;
          buffer = empty();

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

      public func get(id : Id<A>) : ?Status<X> =
        Option.chain<Status<Nat>, Status<X>>(indexOf id, func index {
        func get(queue : Queue<X>) : Nat -> ?X = func (index : Nat) : ?X =
          ( func get_(queue : Queue<X>, step : Nat) : ?X =
            Option.chain<Node<X>, X>(queue.node,
              func ({ value; next }) = if (step == index) ?value
                else get_(next, step + 1))
          )(queue, 0);
        switch index {
          case (#Que index) Option.map<X, Status<X>>(
            get(bufferedQueue.queue) index, func idx = #Que idx);
          case (#Buf index) Option.map<X, Status<X>>(
            get(bufferedQueue.buffer) index, func idx = #Buf idx);
          case (#Prun) ?#Prun;
        };
      });

      public func indexOf(id : Id<A>) : ?Status<Nat> =
        if (id.val >= bufferedQueue.first.val + bufferedQueue.cache.size) null
        else {
          let index : Int = id.val - bufferedQueue.first.val;
          if (index > 0) ?#Que(Int.abs index) else {
            let index_ : Int = bufferedQueue.cache.bufferSize + index;
            if (index_ > 0) ?#Buf(Int.abs index) else ?#Prun
          }
        };


      public func peek() : ?X = Option.map<Node<X>, X>(
        bufferedQueue.queue.node,
        func ({ value }) = value );

      public func pop() : ?X = Option.map<Node<X>, X>(
        bufferedQueue.queue.node,
        func ({ value; next }) {
          bufferedQueue.queue.node := next.node;
          bufferedQueue.cache.size -= 1;
          bufferedQueue.cache.bufferSize += 1;
          bufferedQueue.first := bufferedQueue.first.inc 1;
          value;
        } );

      public func push(value : X) : Id<A> = do {
        let node = { value; next = empty() };
        bufferedQueue.cache.last.node := ?node;
        bufferedQueue.cache.last := node.next;
        bufferedQueue.cache.size += 1;
        bufferedQueue.first.inc(bufferedQueue.cache.size - 1);
      };

      public func put(value : X) = ignore push value;
      public func size() : Nat = bufferedQueue.cache.size;


      public func peekValues(size : Nat) : ?List.List<X> = xxx();
      public func popValues(size : Nat) : ?List.List<X> = xxx();
      public func pushValues(values : Iter.Iter<X>) : Id<A> = xxx();
      public func putValues(values : Iter.Iter<X>) = xxx();


      public func prune() = if (bufferedQueue.cache.bufferSize > 0) {
        bufferedQueue.buffer.node := Option.chain<Node<X>, Node<X>>(
          bufferedQueue.buffer.node, func node = node.next.node);
        bufferedQueue.cache.bufferSize -= 1;
      };

      public func pruneAll() = xxx();
      public func pruneTo(id : Id<A>) = xxx();
  } )(Idx<None, Nat>(0, func (x : Nat, y : Nat) : Nat = x + y));
}
