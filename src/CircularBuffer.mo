import Array "mo:base/Array";
import Nat "mo:base/Nat";
import Iter "mo:base/Iter";

import { Option = { guard }; Num = { Mod } } "Prelude";
import { Num } "Prelude";

module {
  public class CircularBuffer<T>(capacity : Nat) {
    var array : [var ?T] = Array.init(capacity, null);
    var pushes : Nat = 0;

    type Index = Num.Mod;
    let { mod; add } = Mod(capacity);

    public func least() : ?Index = if (pushes <= capacity) ?0 else mod pushes;

    public func compare(x : Index, y : Index) : { #less; #equal; #greater } {
      let ?least_ = least() else return #equal;

      if (
        x < y and (least_ <= x or least_ > y) or
          x > y and least_ <= x and least_ > y
      ) #less else if (x == y) #equal else #greater
    };


    type Id = Nat;

    public func first() : ?Id = if (pushes <= capacity)
      do ? { guard(pushes >= 1)!; 0 } else ?(pushes - capacity);

    public func last() : ?Id = do ? { guard(pushes >= 1)!; pushes - 1 : Nat };

    public func indexOf(id : Id) : ?Index = do ? {
      guard(
        id < pushes and (pushes <= capacity or id >= (pushes - capacity : Nat))
      )!;
      mod(id)!;
    };


    public func pushesAmount() : Nat = pushes;

    public func push(item : T) = ignore do ? {
      array[mod(pushes)!] := ?item;
      pushes += 1;
    };

    public func available() : ?(Id, Id) = do ? { (first()!, last()!) };

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

    public func share() : ([var ?T], Nat) = (array, pushes);

    public func unshare(data : ([var ?T], Nat, Nat)) {
      array := data.0;
      pushes := data.1;
    };
  };
};
