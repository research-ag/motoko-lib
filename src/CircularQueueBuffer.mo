import Array "mo:base/Array";
import Nat "mo:base/Nat";
import Iter "mo:base/Iter";

import { Option = { guard }; Num = { Mod } } "Prelude";
import { Num } "Prelude";

module {
  type Id = Nat;

  public class CircularBuffer<T>(capacity : Nat) {
    var array : [var ?T] = Array.init(capacity, null);
    var pushed : Nat = 0;
    var buffered : Nat = 0;
    var pruned : Nat = 0;

    public type Index = Num.Mod;

    let { mod; add } = Mod(capacity);

    func least() : ?Index = if (pushed <= capacity) ?0 else mod pushed;

    func compare(x : Index, y : Index) : { #less; #equal; #greater } {
      let ?least_ = least() else return #equal;

      if ( x < y and (least_ <= x or least_ > y) or
        x > y and least_ <= x and least_ > y
      ) #less else if (x == y) #equal else #greater
    };

    public func indexOf(id : Id) : ?Index = do ? {
      guard(
        id < pushed and (pushed <= capacity or id >= (pushed - capacity : Nat))
      )!;
      mod(id)!;
    };

    func head() : ?Id = do ? {
      let size = if (pushed <= capacity) pushed else capacity;
      guard(size > buffered + pruned + 1)!;
      buffered + pruned + if (pushed <= capacity) 0 else (pushed - capacity);
    };

    public func peek() : ?X = do ? { array[indexOf(head()!)!]! };

    public func pop() : ?X {
      let value = peek()!;
      buffered += 1;
      value;
    };

    public func push(value : T) = ignore do ? {
      array[mod(pushed)!] := ?value;
      pushed += 1;
    };

    public func put(value : T) = ignore push value;

    public func totalSize() : Nat {
      let size = if (pushed <= capacity) pushed else capacity;
      size - pruned : Nat; // TODO: constrain pruned <= size invariant
    };

    public func queueSize() : Nat = Nat {
      let size = if (pushed <= capacity) pushed else capacity;
      size - (buffered + pruned) : Nat; // TODO: constrain buffered + pruned <= size invariant
    };

    public func get(id : Id) : ?T = do ? { array[indexOf(id)!]! };

    public func range(from : Id, to : Id) : Iter.Iter<T> = object {
      let to_ : ?Index = indexOf to;

      var from_ : ?Index = indexOf from;

      public func next() : ?T = do ? {
        let i = from_!;
        guard(compare(i, to_!) != #greater)!;
        from_ := if (i == to_!) null else add(i, 1);
        array[i]!;
      }
    };

    public func share() : ([var ?T], Nat) = (array, pushed);

    public func unshare(data : ([var ?T], Nat, Nat)) {
      array := data.0;
      pushed := data.1;
    };
  };

  public type Status<X> = { #Prun; #Buf : X; #Que : X };

  type BufferedQueue<X> = {
    // toIter : Queue<X> -> Iter.Iter<X>;
    get : Id -> ?Status<X>;
    indexOf : Id -> ?Status<Nat>;

    peek : () -> ?X;
    pop : () -> ?X;
    push : X -> Id;
    put : X -> ();
    totalSize : () -> Nat;
    queueSize : () -> Nat;

    // peekValues : Nat -> ?List.List<X>;
    // popValues : Nat -> ?List.List<X>;
    // pushValues : Iter.Iter<X> -> List.List<Id>;
    // putValues : Iter.Iter<X> -> ();

    prune: () -> Bool;
    pruneTo: Id -> Bool;
    pruneAll: () -> ();
  };

  public func circularBufferedQueue(first : Id) : Nat -> BufferedQueue<X> =
    func (capacity : Nat) {

      type CircularBufferedQueueRepr<X> = {
        queue : CircularBuffer<X>;
        first : Id;
      };

      let circularBufferedQueue : CircularBufferedQueueRepr<X> = {
        queue = CircularBuffer capacity;
        first;
      };

      public func get(id : Id) : ?Status<X> = do ? {

      }

    };

  public let CircularBufferedQueue : Nat -> BufferedQueue<X> =
    circularBufferedQueue 0;

}
