import Option "mo:base/Option";
import Iter "mo:base/Iter";
import List "mo:base/List";
import Int "mo:base/Int";


module {
  public class Id(value : Nat) { public let val = value };

  type Node<X> = { value : X; next : Queue<X> };
  type Queue<X> = { node : () -> ?Node<X> };

  type QueueMutable<X> = {
    queue : () -> Queue<X>;
    push : X -> ();
    pop : () -> Bool
  };

  func QueueMutable<X>() : QueueMutable<X> = do {
    var push_ : X -> () = func _ = ();

    type QueuePush<X> = {
      queue : Queue<X>;
      push : X -> ();
    };

    func newQueue() : QueuePush<X> = do {
      var node_ : ?Node<X> = null;

      { queue = { node = func () : ?Node<X> = node_ };

        push = func (value : X) {
          let { queue; push } = newQueue();
          node_ := ?{ value; next = queue };
          push_ := push;
        };
      }
    };

    let { queue; push } = newQueue();
    push_ := push;
    var queue_ : Queue<X> = queue;

    let self = {
      queue : () -> Queue<X> = func () = queue_;
      push : X -> () = func value { push_ value };

      pop : () -> Bool = func () =
        Option.isSome(do ? { queue_ := self.queue().node()!.next });
    };
  };

  type BufferedQueueRepr<X> = {
    queue : QueueMutable<X>;
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
    pushValues : Iter.Iter<X> -> List.List<Id>;
    putValues : Iter.Iter<X> -> ();

    prune: () -> Bool;
    pruneTo: Id -> Bool;
    pruneAll: () -> ();
  };

  public func bufferedQueueFrom<X>(first : Id) : BufferedQueue<X> = object {
      let bufferedQueue : BufferedQueueRepr<X> = do {
        let queue = QueueMutable<X>();

        { queue;
          var buffer = queue.queue();

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
          case (#Que id_) #Que(getFrom(bufferedQueue.queue.queue(), id_)!);
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


      public func peek() : ?X = do ? { bufferedQueue.queue.queue().node()!.value };

      public func pop() : ?X = do ? {
        let { value } = bufferedQueue.queue.queue().node()!;
        if (not bufferedQueue.queue.pop()) null!;
        bufferedQueue.cache.size -= 1;
        bufferedQueue.cache.bufferSize += 1;
        bufferedQueue.first := Id(bufferedQueue.first.val + 1);
        value;
      };

      public func push(value : X) : Id {
        bufferedQueue.queue.push value;
        bufferedQueue.cache.size += 1;
        Id(bufferedQueue.first.val + bufferedQueue.cache.size - 1);
      };

      public func put(value : X) = ignore push value;
      public func size() : Nat = bufferedQueue.cache.size;


      public func peekValues(size : Nat) : ?List.List<X> = do ? {
        var values : List.List<X> = null;
        if (size == 0) return ?values;
        var node = bufferedQueue.queue.queue().node()!;
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

      public func putValues(values : Iter.Iter<X>) = for (value in values) put value;


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
        bufferedQueue.buffer := bufferedQueue.queue.queue();
        bufferedQueue.cache.bufferSize := 0;
      };
  };

  public func BufferedQueue<X>() : BufferedQueue<X> = bufferedQueueFrom(Id 0);
}
