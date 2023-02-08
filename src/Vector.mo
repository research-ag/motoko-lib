import Prim "mo:⛔";
import { bitcountLeadingZero = leadingZeros; fromNat = Nat32; toNat = Nat } "mo:base/Nat32";
import Array "mo:base/Array";
import Iter "mo:base/Iter";

module {
  public type Vector<X> = {
    var data_blocks : [var [var ?X]]; // the index block
    // new element should be assigned to exaclty data_blocks[i_block][i_element]
    // i_block is in range (0; data_blocks.size()]
    var i_block : Nat;
    // i_element is in range [0; data_blocks[i_block].size())
    var i_element : Nat;
  };

  public func new<X>() : Vector<X> = {
    var data_blocks = [var [var]];
    var i_block = 1;
    var i_element = 0;
  };

  public func clear<X>(vec : Vector<X>) {
    vec.data_blocks := [var [var]];
    vec.i_block := 1;
    vec.i_element := 0;
  };

  public func clone<X>(vec : Vector<X>) : Vector<X> = {
    var data_blocks = Array.tabulateVar<[var ?X]>(
      vec.data_blocks.size(),
      func(i) = Array.tabulateVar<?X>(
        vec.data_blocks[i].size(),
        func(j) = vec.data_blocks[i][j],
      ),
    );
    var i_block = vec.i_block;
    var i_element = vec.i_element;
  };

  public func size<X>(vec : Vector<X>) : Nat {
    let d = Nat32(vec.i_block);
    let i = Nat32(vec.i_element);

    // We call all data blocks of the same capacity an "epoch". We number the epochs 0,1,2,...
    // A data block is in epoch e iff the data block has capacity 2 ** e.
    // Each epoch starting with epoch 1 spans exactly two super blocks.
    // Super block s falls in epoch ceil(s/2).

    // epoch of last data block
    // e = 32 - lz
    let lz = leadingZeros(d / 3);

    // capacity of all prior epochs combined
    // capacity_before_e = 2 * 4 ** (e - 1) - 1

    // data blocks in all prior epochs combined
    // blocks_before_e = 3 * 2 ** (e - 1) - 2

    // then size = d * 2 ** e + i - c
    // where c = blocks_before_e * 2 ** e - capacity_before_e

    // there can be overflows, but the result is without overflows, so use addWrap and subWrap
    // we don't erase bits by >>, so to use <>> is ok
    Nat((d -% (1 <>> lz)) <>> lz +% i);
  };

  func new_index_block_length(i_block : Nat32) : Nat {
    // this works correct only when i_block is the first block in the super block
    if (i_block == 1) 2 else Nat(i_block +% 0x40000000 >> leadingZeros(i_block));
  };

  func grow_index_block_if_needed<X>(vec : Vector<X>) {
    if (vec.data_blocks.size() == vec.i_block) {
      vec.data_blocks := Array.tabulateVar<[var ?X]>(
        new_index_block_length(Nat32(vec.i_block)),
        func(i) {
          if (i < vec.i_block) {
            vec.data_blocks[i];
          } else {
            [var];
          };
        },
      );
    };
  };

  func shrink_index_block_if_needed<X>(vec : Vector<X>) {
    let i_block = Nat32(vec.i_block);
    // kind of index of the first block in the super block
    if ((i_block << leadingZeros(i_block)) << 2 == 0) {
      let new_length = new_index_block_length(i_block);
      if (new_length < vec.data_blocks.size()) {
        vec.data_blocks := Array.tabulateVar<[var ?X]>(
          new_length,
          func(i) {
            vec.data_blocks[i];
          },
        );
      };
    };
  };

  public func add<X>(vec : Vector<X>, element : X) {
    var i_element = vec.i_element;
    if (i_element == 0) {
      grow_index_block_if_needed(vec);
      let i_block = vec.i_block;

      // When removing last we keep one more data block, so can be not empty
      if (vec.data_blocks[i_block].size() == 0) {
        vec.data_blocks[i_block] := Array.init<?X>(
          // formula for the size of given i_block
          Nat(1 <>> leadingZeros(Nat32(i_block) / 3)),
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
  };

  public func removeLast<X>(vec : Vector<X>) : ?X {
    var i_element = vec.i_element;
    if (i_element == 0) {
      shrink_index_block_if_needed(vec);

      var i_block = vec.i_block;
      if (i_block == 0) {
        return null;
      };
      i_block -= 1;
      i_element := vec.data_blocks[i_block].size();

      // Keep one totally empty block when removing
      if (i_block + 2 < vec.data_blocks.size()) {
        if (vec.data_blocks[i_block + 2].size() == 0) {
          vec.data_blocks[i_block + 2] := [var];
        };
      };
      vec.i_block := i_block;
    };
    i_element -= 1;

    var last_data_block = vec.data_blocks[vec.i_block];

    let element = last_data_block[i_element];
    last_data_block[i_element] := null;

    vec.i_element := i_element;
    return element;
  };

  func locate(index : Nat) : (Nat, Nat) {
    // see comments in tests
    let i = Nat32(index);
    let lz = leadingZeros(i);
    let lz2 = lz >> 1;
    if (lz & 1 == 0) {
      (Nat(((i << lz2) >> 16) ^ (0x10000 >> lz2)), Nat(i & (0xFFFF >> lz2)));
    } else {
      (Nat(((i << lz2) >> 15) ^ (0x18000 >> lz2)), Nat(i & (0x7FFF >> lz2)));
    };
  };

  public func get<X>(vec : Vector<X>, index : Nat) : X {
    // inlined version of:
    //   let (a,b) = locate(index);
    //   switch(vec.data_blocks[a][b]) {
    //     case (?element) element;
    //     case (null) Prim.trap "";
    //   };
    let i = Nat32(index);
    let lz = leadingZeros(i);
    let lz2 = lz >> 1;
    switch (
      if (lz & 1 == 0) {
        vec.data_blocks[Nat(((i << lz2) >> 16) ^ (0x10000 >> lz2))][Nat(i & (0xFFFF >> lz2))];
      } else {
        vec.data_blocks[Nat(((i << lz2) >> 15) ^ (0x18000 >> lz2))][Nat(i & (0x7FFF >> lz2))];
      },
    ) {
      case (?element) element;
      case (null) Prim.trap "Vector index out of bounds in get";
    };
  };

  public func getOpt<X>(vec : Vector<X>, index : Nat) : ?X {
    let (a, b) = locate(index);
    if (a < vec.i_block or vec.i_element != 0 and a == vec.i_block) {
      vec.data_blocks[a][b];
    } else {
      null;
    };
  };

  public func put<X>(vec : Vector<X>, index : Nat, value : X) {
    let (a, b) = locate(index);
    if (a < vec.i_block or a == vec.i_block and b < vec.i_element) {
      vec.data_blocks[a][b] := ?value;
    } else Prim.trap "Vector index out of bounds in put";
  };

  public func vals<X>(vec : Vector<X>) : Iter.Iter<X> = object {
    var i_block = 1;
    var i_element = 0;

    public func next() : ?X {
      if (i_block >= vec.data_blocks.size()) {
        return null;
      };
      let block = vec.data_blocks[i_block];
      if (block.size() == 0) {
        return null;
      };
      switch (block[i_element]) {
        case (null) return null;
        case (?element) {
          i_element += 1;
          if (i_element == block.size()) {
            i_block += 1;
            i_element := 0;
          };
          return ?element;
        };
      };
    };
  };

  public func fromIter<X>(iter : Iter.Iter<X>) : Vector<X> {
    let vec = new<X>();
    for (element in iter) add(vec, element);
    vec;
  };

  public func toArray<X>(vec : Vector<X>) : [X] = Array.tabulate<X>(size(vec), func(i) = get(vec, i));

  public func fromArray<X>(array : [X]) : Vector<X> = fromIter(array.vals());

  public func toVarArray<X>(vec : Vector<X>) : [var X] = Array.tabulateVar<X>(size(vec), func(i) = get(vec, i));

  public func fromVarArray<X>(array : [var X]) : Vector<X> = fromIter(array.vals());
};
