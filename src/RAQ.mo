// Random access queue
//
import Prim "mo:⛔";
import { bitcountLeadingZero = leadingZeros; fromNat = Nat32; toNat = Nat } "mo:base/Nat32";
import Array "mo:base/Array";

module {
// Deletable vector
//
// This data structure starts with a small subset of Vector.
// Only the code for add, getOpt, size is here.
//
// Then we add deletion from the beginning. Not by shrinking the Vector, but simply
// by overwriting the entry with null. We rename add -> push and call the new function
// that deletes from the beginning pop. We track the position used pop with the new
// variable head.
//
// This is of course wasteful. But we not use this data structure as-is. We wrap it
// inside another one (see Queue<X> below).
module Vector {
  public class Vector<X>() {
    var data_blocks : [var [var ?X]] = [var [var]];
    var i_block : Nat = 1;
    var i_element : Nat = 0;
    var start : Nat = 0;

    public func size<X>() : Nat {
      let d = Nat32(i_block);
      let i = Nat32(i_element);
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

    func grow_index_block_if_needed() {
      if (data_blocks.size() == i_block) {
        let new_blocks = Array.init<[var ?X]>(new_index_block_length(Nat32(i_block)), [var]);
        var i = 0;
        while (i < i_block) {
          new_blocks[i] := data_blocks[i];
          i += 1;
        };
        data_blocks := new_blocks;
      };
    };

    public func add(element : X) : Nat {
      if (i_element == 0) {
        grow_index_block_if_needed();

        if (data_blocks[i_block].size() == 0) {
          data_blocks[i_block] := Array.init<?X>(
            data_block_size(i_block),
            null,
          );
        };
      };

      let last_data_block = data_blocks[i_block];

      last_data_block[i_element] := ?element;

      i_element += 1;
      if (i_element == last_data_block.size()) {
        i_element := 0;
        i_block += 1;
      };

      return size() - 1;
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

    public func getOpt(index : Nat) : ?X {
      let (a, b) = locate(index);
      if (a < i_block or i_element != 0 and a == i_block) {
        data_blocks[a][b];
      } else {
        null;
      };
    };

    // TODO: This can be made more sophisticated
    // * We can count in (block, element) and avoid calling locate every time
    // * We can delete the datablocks that have become empty
    public func delete<X>(n : Nat) {
      let end = start + n;
      if (end > size()) Prim.trap("index out of bounds in delete");
      var pos = start;
      while (pos < end) {
        let (a, b) = locate(pos);
        data_blocks[a][b] := null;
        pos += 1;
      };
      start := end;
    };

    public func len<X>() : Nat = size() - start; // number of non-deleted entries
    public func deleted<X>() : Nat = start; // number of deleted entries
  };
};

  // Buffer
  //
  // A linear buffer where we can add at end and delete from the beginning.
  //
  // This data structure consists of a pair of Vectors called `old` and `new`.
  // We always add to `new`.  While `old` is empty we delete from `new` but only
  // until the waste in `new` exceeds sqrt(n). When `new` has >sqrt(n) waste
  // then we rename `new` to `old` and create a fresh empty `new`. Now deletions
  // happen from old, until old is empty. Then `old` is discarded and deletions
  // happen from `new` again until the waste in `new` exceeds sqrt(n). Then the
  // shift starts all over again. Etc.
  //
  // Only the waste in `new` is limited to sqrt(n). The waste in `old` is not limited.
  // Hence, the largest waste occurs if we do n additions first, then n deletions.
  class Buffer<X>() {

    var old : ?Vector.Vector<X> = null;
    var new : Vector.Vector<X> = Vector.Vector<X>();
    var n = 0; // offset of old
    var m = 0; // offset of new

    public func add(x : X) : Nat {
      new.add(x) + m;
    };

    public func getOpt(i : Nat) : ?X {
      if (i >= m) {
        new.getOpt(i - m : Nat);
      } else if (i >= n) {
        let ?vec = old else Prim.trap("old is null in Buffer");
        vec.getOpt(i - n : Nat);
      } else null;
    };

    func rotateIfNeeded() {
      let size = new.size();
      let s = Nat32(size);
      let d = Nat32(new.deleted());
      let bits = 32 - leadingZeros(s);
      let limit = s >> (bits >> 1);
      if (d > limit) {
        old := ?new;
        n := m;
        new := Vector.Vector<X>();
        m := n + size;
      };
    };

    public func delete(n_ : Nat) {
      var ctr = n_;
      let end = deleted() + ctr;
      if (end > size()) Prim.trap("index out of bounds in Buffer.delete");
      switch (old) {
        case (?vec) {
          if (vec.size() > ctr) {
            vec.delete(ctr);
            return;
          } else {
            ctr := ctr - vec.size();
            old := null;
          };
        };
        case (null) {};
      };
      new.delete(ctr);
      rotateIfNeeded();
    };

    public func deleted() : Nat = switch (old) {
      case (?vec) { n + vec.deleted() };
      case (null) { m + new.deleted() };
    };

    public func size() : Nat = m + new.size();
    public func len() : Nat = size() - deleted();
  };

  class QueueBuffer<X>() {
    var buf : Buffer<X> = Buffer<X>();
    var head : Nat = 0;

    public func push(x : X) : Nat = buf.add(x);
    public func pop(x : X) : ?(Nat, X) = do ? {
      let x = buf.getOpt(head)!;
      (head, x);
    };
    public func pruneAll() {
      // queue.popMany(pos - queue.headPos());
    };
    public func pruneTo(n : Nat) {
      // queue.popMany(n - queue.headPos());
    };
    public func rewind() {
      head := buf.deleted();
    };
  };
};
