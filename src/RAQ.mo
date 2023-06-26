// Random access queue
//
import Prim "mo:⛔";
import { bitcountLeadingZero = leadingZeros; fromNat = Nat32; toNat = Nat } "mo:base/Nat32";
import Array "mo:base/Array";

module {
  // Deletable vector
  //
  // This data structure starts with a small subset of Vector.
  // Only the code for add, getOpt, put, size is here (put is only for internal use).
  //
  // Then we add deletion from the beginning. Not by shrinking the Vector, but simply
  // by overwriting the entry with null. We rename add -> push and call the new function
  // that deletes from the beginning pop. We track the position used pop with the new 
  // variable head.
  // 
  // This is of course wasteful. But we not use this data structure as-is. We wrap it 
  // inside another one (see Queue<X> below).
  module VectorQueue {
    public type Queue<X> = {
      var data_blocks : [var [var ?X]];
      var i_block : Nat;
      var i_element : Nat;
      var head : Nat;
    };

    public func new<X>() : Queue<X> = {
      var data_blocks = [var [var]];
      var i_block = 1;
      var i_element = 0;
      var head = 0;
    };

    public func size<X>(vec : Queue<X>) : Nat {
      let d = Nat32(vec.i_block);
      let i = Nat32(vec.i_element);
      let lz = leadingZeros(d / 3);
      Nat((d -% (1 <>> lz)) <>> lz +% i);
    };

    func data_block_size(i_block : Nat) : Nat {
      Nat(1 <>> leadingZeros(Nat32(i_block) / 3));
    };

    func new_index_block_length(i_block : Nat32) : Nat {
      if (i_block <= 1) 2 else {
        let s = 30 - leadingZeros(i_block);
        Nat(((i_block >> s) +% 1) << s);
      };
    };

    func grow_index_block_if_needed<X>(vec : Queue<X>) {
      if (vec.data_blocks.size() == vec.i_block) {
        let new_blocks = Array.init<[var ?X]>(new_index_block_length(Nat32(vec.i_block)), [var]);
        var i = 0;
        while (i < vec.i_block) {
          new_blocks[i] := vec.data_blocks[i];
          i += 1;
        };
        vec.data_blocks := new_blocks;
      };
    };

    public func push<X>(vec : Queue<X>, element : X) : Nat {
      var i_element = vec.i_element;
      if (i_element == 0) {
        grow_index_block_if_needed(vec);
        let i_block = vec.i_block;

        if (vec.data_blocks[i_block].size() == 0) {
          vec.data_blocks[i_block] := Array.init<?X>(
            data_block_size(i_block),
            null,
          );
        };
      };

      let last_data_block = vec.data_blocks[vec.i_block];

      last_data_block[i_element] := ?element;

      i_element += 1;
      if (i_element == last_data_block.size()) {
        i_element := 0;
        vec.i_block += 1;
      };
      vec.i_element := i_element;

      return size(vec) - 1;
    };

    func locate(index : Nat) : (Nat, Nat) {
      let i = Nat32(index);
      let lz = leadingZeros(i);
      let lz2 = lz >> 1;
      if (lz & 1 == 0) {
        (Nat(((i << lz2) >> 16) ^ (0x10000 >> lz2)), Nat(i & (0xFFFF >> lz2)));
      } else {
        (Nat(((i << lz2) >> 15) ^ (0x18000 >> lz2)), Nat(i & (0x7FFF >> lz2)));
      };
    };

    public func getOpt<X>(vec : Queue<X>, index : Nat) : ?X {
      let (a, b) = locate(index);
      if (a < vec.i_block or vec.i_element != 0 and a == vec.i_block) {
        vec.data_blocks[a][b];
      } else {
        null;
      };
    };

    public func peek<X>(vec : Queue<X>) : ?(Nat, X) = do ? {
      let v = getOpt(vec, vec.head)!;
      (vec.head, v);
    };

    func del<X>(vec : Queue<X>, index : Nat) {
      let (a, b) = locate(index);
      if (a < vec.i_block or a == vec.i_block and b < vec.i_element) {
        vec.data_blocks[a][b] := null;
      } else Prim.trap "Vector index out of bounds in put";
    };

    public func pop<X>(vec : Queue<X>) : ?(Nat, X) = do ? {
      let v = getOpt(vec, vec.head)!;
      let ret = (vec.head, v);
      del(vec, vec.head);
      vec.head += 1;
      ret;
    };

    public func len<X>(vec : Queue<X>) : Nat = size(vec) - vec.head;
    // public func head<X>(vec : Queue<X>) : Nat = vec.head;
    public func pushCtr<X>(vec : Queue<X>) : Nat = size(vec);
    public func popCtr<X>(vec : Queue<X>) : Nat = vec.head;
  };

  let VQ = VectorQueue;

  // Random access queue
  //
  // This data structure consists of a pair of QueueVectors called old and new.
  // We start pushing to new and also pop from new but only until the waste in new
  // exceed sqrt(n). When new has >sqrt(n) waste then we rename new to old and create
  // a fresh empty new. Now pushes happen to new and pops happen from old, until old 
  // is empty. Then pops happen from new until the waste in new exceeds sqrt(n). Then
  // the shift starts all over again. Etc.
  class Queue<X>() {

    var old : VQ.Queue<X> = VectorQueue.new<X>();
    var new : VQ.Queue<X> = VectorQueue.new<X>();
    var n = 0; // offset of old
    var m = 0; // offset of new

    public func push(x : X) : Nat {
      VQ.push(new, x) + m;
    };

    public func getOpt(i : Nat) : ?X {
      if (i >= m) {
        VQ.getOpt(new, i - m : Nat);
      } else if (i >= n) {
        VQ.getOpt(old, i - n : Nat);
      } else null;
    };

    func rotateIfNeeded() {
      let l = VQ.pushCtr(new);
      if (VQ.popCtr(new)**2 > VQ.pushCtr(new)) {
        old := new;
        n := m;
        new := VQ.new<X>(); 
        m := n + VQ.pushCtr(old);
      }
    };

    public func pop() : ?(Nat, X) = do ? {
      if (VQ.len(old) == 0) {
        let (i, x) = VQ.pop(new)!;
        let m_ = m;
        rotateIfNeeded();
        (i + m_, x)
      } else {
        let (i, x) = VQ.pop(old)!;
        (i + n, x);
      };
    };
  };
};
