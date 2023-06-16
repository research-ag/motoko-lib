import { xxx } "mo:base/Prelude";

import Order "mo:base/Order";
import Option "mo:base/Option";
import Iter "mo:base/Iter";
import List "mo:base/List";
import Int "mo:base/Int";


module {

  public class Id(value : Nat) { public let val = value };

  type Node<X> = { value : X; next : Queue<X> };
  type Queue_<X> = { node : () -> ?Node<X>; add : X -> () };

  class Queue<X>() : Queue_<X> {
    var node_ : ?Node<X> = null;

    var add_ : X -> () = func value {
      let next = Queue<X>();
      node_ := ?{ value; next };
      add_ := next.add;
    };

    public let node : () -> ?Node<X> = func () = node_;
    public let add : X -> () = func value { add_ value };
  };

  type BufferedQueueRepr<X> = {
    var queue : Queue<X>;
    var buffer : Queue<X>;

    var first : Id;

    cache : {
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
    pruneTo: Id -> Bool;
    pruneAll: () -> ();
  };

  public func bufferedQueueFrom<X>(first : Id) : BufferedQueue<X> = object {
      let bufferedQueue : BufferedQueueRepr<X> = do {
        let queue = Queue<X>();

        { var queue;
          var buffer = queue;

          var first;

          cache = {
            var size = 0;
            var bufferSize = 0;
          }
        }
      };

      public func toIter(queue : Queue<X>) : Iter.Iter<X> {
        var state = queue;
        { next = func () : ?X = Option.map<Node<X>, X>(state.node(),
          func ({ value; next }) { state := next; value } ) }
      };

      func getFrom(queue : Queue<X>, id : Nat) : ?X = do ? {
        var queue_ = queue;
        for (_ in Iter.range(1, id)) queue_ := queue_.node()!.next;
        queue_.node()!.value;
      };

      public func get(id : Id) : ?Status<X> = do ? {
        switch (indexOf(id)!) {
          case (#Que id_) #Que(getFrom(bufferedQueue.queue, id_)!);
          case (#Buf id_) #Buf(getFrom(bufferedQueue.buffer, id_)!);
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


      public func peek() : ?X = do ? { bufferedQueue.queue.node()!.value };

      public func pop() : ?X = do ? {
        let { value; next } = bufferedQueue.queue.node()!;
        bufferedQueue.queue := next;
        bufferedQueue.cache.size -= 1;
        bufferedQueue.cache.bufferSize += 1;
        bufferedQueue.first := Id(bufferedQueue.first.val + 1);
        value;
      };

      public func push(value : X) : Id {
        bufferedQueue.queue.add value;
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
          bufferedQueue.buffer := bufferedQueue.buffer.node()!.next;
          bufferedQueue.cache.bufferSize -= 1;
        });

      public func pruneTo(id : Id) : Bool {
        let ?#Buf(id_) = indexOf id else return false;

        bufferedQueue.cache.bufferSize -= id_ + 1;

        Option.isSome(do ? {
          for (_ in Iter.range(0, id_))
            bufferedQueue.buffer := bufferedQueue.buffer.node()!.next;
        });
      };

      public func pruneAll() {
        bufferedQueue.buffer := bufferedQueue.queue;
        bufferedQueue.cache.bufferSize := 0;
      };
  };

  public func BufferedQueue<X>() : BufferedQueue<X> = bufferedQueueFrom(Id 0);
}
