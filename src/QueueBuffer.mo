import Option "mo:base/Option";
import Iter "mo:base/Iter";
import List "mo:base/List";
import Int "mo:base/Int";

import { Option = { guard } } "Prelude";


module {
  type Node<X> = { value : X; next : Queue<X> };
  type Queue<X> = { node : () -> ?Node<X> };

  class QueueMutable<X>() = self {
    class QueuePush<X>() {
      var node_ : ?Node<X> = null;

      public let head = { node = func () : ?Node<X> = node_ };

      public func push(value : X) : QueuePush<X> {
        let queue = QueuePush<X>();
        node_ := ?{ value; next = queue.head };
        queue;
      };
    };
    var last : QueuePush<X> = QueuePush();
    var head_ : Queue<X> = last.head;

    public func head() : Queue<X> = head_;
    public func node() : ?Node<X> = self.head().node();
    public func push(value : X) { last := last.push value };
    public func pop() : Bool =
      Option.isSome(do ? { head_ := self.node()!.next });
  };

  type Id = Nat;
  public type Status<X> = { #Prun; #Buf : X; #Que : X };

  type BufferedQueue<X> = {
    toIter : Queue<X> -> Iter.Iter<X>;
    get : Id -> ?Status<X>;
    indexOf : Id -> ?Status<Nat>;

    peek : () -> ?X;
    pop : () -> ?X;
    push : X -> Id;
    put : X -> ();
    totalSize : () -> Nat;
    queueSize : () -> Nat;

    peekValues : Nat -> ?List.List<X>;
    popValues : Nat -> ?List.List<X>;
    pushValues : Iter.Iter<X> -> List.List<Id>;
    putValues : Iter.Iter<X> -> ();

    prune: () -> Bool;
    pruneTo: Id -> Bool;
    pruneAll: () -> ();
  };

  public func bufferedQueueFrom<X>(first : Id) : BufferedQueue<X> = object {

    type BufferedQueueRepr<X> = {
      queue : QueueMutable<X>;
      var buffer : Queue<X>;

      var first : Id;

      cache : {
        var size : Nat;
        var bufferSize : Nat;
      }
    };

    let bufferedQueue : BufferedQueueRepr<X> = do {
      let queue = QueueMutable<X>();

      { queue;
        var buffer = queue.head();

        var first;

        cache = {
          var size = 0;
          var bufferSize = 0;
        }
      }
    };

    public func toIter(queue : Queue<X>) : Iter.Iter<X> {
      var state = queue;

      { next =
        func () : ?X = do ? {
          let { value; next } = state.node()!;
          state := next;
          value;
        }
      };
    };

    func getFrom(queue : Queue<X>, id : Nat) : ?X = do ? {
      var queue_ = queue;
      for (_ in Iter.range(1, id)) queue_ := queue_.node()!.next;
      queue_.node()!.value;
    };

    public func get(id : Id) : ?Status<X> = do ? {
      switch (indexOf(id)!) {
        case (#Que id_) #Que(getFrom(bufferedQueue.queue.head(), id_)!);
        case (#Buf id_) #Buf(getFrom(bufferedQueue.buffer, id_)!);
        case (#Prun) #Prun;
      };
    };

    public func indexOf(id : Id) : ?Status<Nat> = do ? {
      guard(id < bufferedQueue.first + bufferedQueue.cache.size)!;
      let index : Int = id - bufferedQueue.first;

      if (index >= 0) #Que(Int.abs index) else {
        let index_ : Int = bufferedQueue.cache.bufferSize + index;
        if (index_ >= 0) #Buf(Int.abs index_) else #Prun
      }
    };


    public func peek() : ?X = do ? { bufferedQueue.queue.node()!.value };

    public func pop() : ?X = do ? {
      let { value } = bufferedQueue.queue.node()!;
      guard(bufferedQueue.queue.pop())!;
      bufferedQueue.cache.size -= 1;  // Move to: bufferedQueue.queue.pop()
      bufferedQueue.cache.bufferSize += 1;  // Move to: bufferedQueue.buffer.push()
      bufferedQueue.first := bufferedQueue.first + 1;
      value;
    };

    public func push(value : X) : Id {
      bufferedQueue.queue.push value;
      bufferedQueue.cache.size += 1;
      bufferedQueue.first + bufferedQueue.cache.size - 1;
    };

    public func put(value : X) = ignore push value;

    public func totalSize() : Nat = bufferedQueue.cache.size +
      bufferedQueue.cache.bufferSize;

    public func queueSize() : Nat = bufferedQueue.cache.size;


    public func peekValues(size : Nat) : ?List.List<X> = do ? {
      var values : List.List<X> = null;
      if (size == 0) return ?values;
      var node = bufferedQueue.queue.node()!;
      func peekValue() { values := ?(node.value, values) };
      peekValue();
      if (size == 1) return ?values;

      for (_ in Iter.range(2, size)) {
        node := node.next.node()!;
        peekValue();
      };
      values;
    };

    public func popValues(size : Nat) : ?List.List<X> = do ? {
      var values : List.List<X> = null;
      for (_ in Iter.range(1, size)) values := ?(pop()!, values);
      values;
    };

    public func pushValues(values : Iter.Iter<X>) : List.List<Id> {
      var ids : List.List<Id> = null;
      for (value in values) ids := ?(push value, ids);
      ids;
    };

    public func putValues(values : Iter.Iter<X>) =
      for (value in values) put value;


    public func prune() : Bool =
      bufferedQueue.cache.bufferSize > 0 and Option.isSome(do ? {  // Move to: bufferedQueue.buffer.prune()
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
      bufferedQueue.buffer := bufferedQueue.queue.head();
      bufferedQueue.cache.bufferSize := 0;
    };
  };

  public func BufferedQueue<X>() : BufferedQueue<X> = bufferedQueueFrom 0;
}
