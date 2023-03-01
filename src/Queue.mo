import Deque "mo:base/Deque";
import Prim "mo:prim";
import Array "mo:base/Array";

module {
  public type Id = Nat;

  public class Queue<X>() {
    var array = [var (null : ?X)];
    var size = 0;
    var start = 0;
    var pushes = 0;

    func sum(a : Nat, b : Nat) : Nat {
      let result = a + b;
      if (result >= array.size()) { result - array.size() } else result;
    };

    public func get(id : Id) : ?X {
      if (id >= pushes or pushes - id > size) {
        null;
      } else {
        array[(start + size + id - pushes) % array.size()];
      };
    };

    public func enqueue(value : X) : Id {
      if (size == array.size()) {
        array := Array.tabulateVar<?X>(
          array.size() * 2,
          func(i) = if (i < array.size()) {
            array[sum(start, i)];
          } else null,
        );
      };
      array[sum(start, size)] := ?value;
      size += 1;
      pushes += 1;

      pushes - 1;
    };

    public func peek() : ?X {
      if (size == 0) null else array[sum(start, size - 1)];
    };

    public func dequeue() : ?X {
      if (size == 0) return null;
      let result = array[start];
      start := sum(start, 1);
      size -= 1;
      result;
    };
  };
};
