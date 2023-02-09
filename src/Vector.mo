/// Resizable one-dimensional array with O(sqrt(size)) memory waste.
import Prim "mo:⛔";
import { bitcountLeadingZero = leadingZeros; fromNat = Nat32; toNat = Nat } "mo:base/Nat32";
import Array "mo:base/Array";
import Iter "mo:base/Iter";

module {
  /// Class `Vector<X>` provides a mutable list of elements of type `X`.
  /// It is substitution for `Buffer<X>` with `O(sqrt(size))` memory waste instead of `O(size)`.
  /// Based on paper "Resizable Arrays in Optimal Time and Space" by Brodnik, Carlsson, Demaine, Munro and Sedgewick (1999). 
  public type Vector<X> = {
    /// the index block
    var data_blocks : [var [var ?X]];
    /// new element should be assigned to exaclty data_blocks[i_block][i_element]
    /// i_block is in range (0; data_blocks.size()]
    var i_block : Nat;
    /// i_element is in range [0; data_blocks[i_block].size())
    var i_element : Nat;
  };

  /// Creates a new Vector.
  ///
  /// Example:
  /// ```motoko name=initialize
  /// let vector = Vector.new<Nat>(); // Creates a new Vector
  /// ```
  public func new<X>() : Vector<X> = {
    var data_blocks = [var [var]];
    var i_block = 1;
    var i_element = 0;
  };


  /// Resets the buffer.
  ///
  /// Example:
  /// ```motoko include=initialize
  ///
  /// Vector.add(vector, 10);
  /// Vector.add(vector, 11);
  /// Vector.add(vector, 12);
  /// Vector.clear(vector); // buffer is now empty
  /// Vector.toArray(vector) // => []
  /// ```
  ///
  /// Runtime: O(1)
  public func clear<X>(vec : Vector<X>) {
    vec.data_blocks := [var [var]];
    vec.i_block := 1;
    vec.i_element := 0;
  };

  /// Returns a copy of `vector`, with the same capacity.
  ///
  ///
  /// Example:
  /// ```motoko include=initialize
  ///
  /// vector.add(1);
  ///
  /// let clone = Vector.clone(vector);
  /// Vector.toArray(clone); // => [1]
  /// ```
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

  /// Returns the current number of elements in the vector.
  ///
  /// Example:
  /// ```motoko include=initialize
  /// Vector.size(vector) // => 0
  /// ```
  ///
  /// Runtime: O(1) (with some calculations)
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

  /// Adds a single element to the end of the vector, 
  /// adding data block if needed, and resizing index block if needed.
  ///
  /// Example:
  /// ```motoko include=initialize
  ///
  /// Vector.add(vector, 0); // add 0 to buffer
  /// Vector.add(vector, 1);
  /// Vector.add(vector, 2);
  /// Vector.add(vector, 3);
  /// Vector.toArray(vector) // => [0, 1, 2, 3]
  /// ```
  ///
  /// Amortized Runtime: O(1), Worst Case Runtime: O(sqrt(n))
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

  /// Removes and returns the last item in the vector or `null` if
  /// the vector is empty.
  ///
  /// Example:
  /// ```motoko include=initialize
  ///
  /// Vector.add(vector, 10);
  /// Vector.add(vector, 11);
  /// Vector.removeLast(vector); // => ?11
  /// ```
  ///
  /// Amortized Runtime: O(1), Worst Case Runtime: O(sqrt(size))
  ///
  /// Amortized Space: O(1), Worst Case Space: O(sqrt(size))
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

  /// Returns the element at index `index`. Indexing is zero-based.
  /// Traps if `index >= size`, error message may be not descriptive.
  ///
  /// Example:
  /// ```motoko include=initialize
  ///
  /// Vector.add(vector, 10);
  /// Vector.add(vector, 11);
  /// Vector.get(vector, 0); // => 10
  /// ```
  ///
  /// Runtime: O(1). Approximately two times slower than the Buffer.get if measured in cycles.
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

  /// Returns the element at index `index` as an option.
  /// Returns `null` when `index >= size`. Indexing is zero-based.
  ///
  /// Example:
  /// ```motoko include=initialize
  ///
  /// Vector.add(vector, 10);
  /// Vector.add(vector, 11);
  /// let x = Vector.getOpt(vector, 0); // => ?10
  /// let y = Vector.getOpt(vector, 2); // => null
  /// ```
  ///
  /// Runtime: O(1). Approximately two times slower than the Buffer.get if measured in cycles.
  public func getOpt<X>(vec : Vector<X>, index : Nat) : ?X {
    let (a, b) = locate(index);
    if (a < vec.i_block or vec.i_element != 0 and a == vec.i_block) {
      vec.data_blocks[a][b];
    } else {
      null;
    };
  };

  /// Overwrites the current element at `index` with `element`. Traps if
  /// `index` >= size. Indexing is zero-based.
  ///
  /// Example:
  /// ```motoko include=initialize
  ///
  /// Vector.add(vector, 10);
  /// Vector.put(vector, 0, 20); // overwrites 10 at index 0 with 20
  /// Vector.toArray(buffer) // => [20]
  /// ```
  ///
  /// Runtime: O(1). Approximately two times slower than the Buffer.get if measured in cycles.
  public func put<X>(vec : Vector<X>, index : Nat, value : X) {
    let (a, b) = locate(index);
    if (a < vec.i_block or a == vec.i_block and b < vec.i_element) {
      vec.data_blocks[a][b] := ?value;
    } else Prim.trap "Vector index out of bounds in put";
  };

  /// Returns an Iterator (`Iter`) over the elements of this vector.
  /// Iterator provides a single method `next()`, which returns
  /// elements in order, or `null` when out of elements to iterate over.
  ///
  /// ```motoko include=initialize
  ///
  /// Vector.add(vector, 10);
  /// Vector.add(vector, 11);
  /// Vector.add(vector, 12);
  ///
  /// var sum = 0;
  /// for (element in Vector.vals(vector)) {
  ///   sum += element;
  /// };
  /// sum // => 33
  /// ```
  ///
  /// Runtime: O(1)
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

  /// Creates a vector containing elements from `iter`.
  ///
  /// Example:
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// let array = [1, 1, 1];
  /// let iter = array.vals();
  ///
  /// let vec = Vector.fromIter<Nat>(iter); // => [1, 1, 1]
  /// ```
  ///
  /// Runtime: O(size)
  public func fromIter<X>(iter : Iter.Iter<X>) : Vector<X> {
    let vec = new<X>();
    for (element in iter) add(vec, element);
    vec;
  };

  /// Creates an array containing elements from `vector`.
  ///
  /// Example:
  /// ```motoko include=initialize
  ///
  /// Vector.add(vector, 1);
  /// Vector.add(vector, 2);
  /// Vector.add(vector, 3);
  ///
  /// Vector.toArray<Nat>(vector); // => [1, 2, 3]
  ///
  /// ```
  ///
  /// Runtime: O(size)
  public func toArray<X>(vec : Vector<X>) : [X] = Array.tabulate<X>(size(vec), func(i) = get(vec, i));

  /// Creates a vector containing elements from `array`.
  ///
  /// Example:
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// let array = [2, 3];
  ///
  /// let vec = Vector.fromArray<Nat>(array); // => [2, 3]
  /// ```
  ///
  /// Runtime: O(size)
  public func fromArray<X>(array : [X]) : Vector<X> = fromIter(array.vals());

  /// Creates a mutable containing elements from `vector`.
  ///
  /// Example:
  /// ```motoko include=initialize
  ///
  /// Vector.add(vector, 1);
  /// Vector.add(vector, 2);
  /// Vector.add(vector, 3);
  ///
  /// Vector.toVarArray<Nat>(vector); // => [1, 2, 3]
  ///
  /// ```
  ///
  /// Runtime: O(size)
  public func toVarArray<X>(vec : Vector<X>) : [var X] = Array.tabulateVar<X>(size(vec), func(i) = get(vec, i));

  /// Creates a vector containing elements from `array`.
  ///
  /// Example:
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// let array = [var 2, 3];
  ///
  /// let vec = Vector.fromVarArray<Nat>(array); // => [2, 3]
  /// ```
  ///
  /// Runtime: O(size)
  public func fromVarArray<X>(array : [var X]) : Vector<X> = fromIter(array.vals());
};
