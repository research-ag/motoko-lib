import Array "mo:base/Array";
import Iter "mo:base/Iter";
import P "mo:base/Prelude";

module {
  /* 
    A fixed length buffer of type T that can be filled from an iterator
    until the buffer is full or the iterator is exhausted.
    val is an arbitrary value of type T, used only to initialize an array
  */
  public class BlockBuffer<T>(size : Nat) {
    private let buffer : [var ?T] = Array.init<?T>(size, null);
    private var pos : Nat = 0;

    public func reset() {
      pos := 0;
    };

    public func fill(i : Iter.Iter<T>) : Nat {
      let start = pos;
      label emptied while (pos < size) {
        switch (i.next()) {
          case (?v) {
            buffer[pos] := ?v;
            pos += 1;
          };
          case (null) {
            break emptied;
          };
        };
      };
      pos - start;
    };

    public func refill(i : Iter.Iter<T>) : Nat {
      reset();
      fill(i);
    };

    public func isFull() : Bool {
      pos == size;
    };

    public func toArray(dir : { #fwd; #bwd }) : [T] {
      switch dir {
        case (#fwd) {
          Array.tabulate<T>(pos, get);
        };
        case (#bwd) {
          Array.tabulate<T>(pos, func(i) { get((pos -1) -i) });
        };
      };
    };

    public func get(i : Nat) : T {
      assert (i < pos);
      switch (buffer[i]) {
        case (null) { P.unreachable() };
        case (?v) { v };
      };
    };
  };
};