/// Resizable one-dimensional array with `O(sqrt(n))` memory waste.
import Prim "mo:⛔";
import { bitcountLeadingZero = leadingZeros; fromNat = Nat32; toNat = Nat } "mo:base/Nat32";
import Array "mo:base/Array";
import Iter "mo:base/Iter";

module {
  /// Class `Vector<X>` provides a mutable list of elements of type `X`.
  /// It is a substitution for `Buffer<X>` with `O(sqrt(n))` memory waste instead of `O(n)` where
  /// n is the size of the data strucuture.
  /// Based on the paper "Resizable Arrays in Optimal Time and Space" by Brodnik, Carlsson, Demaine, Munro and Sedgewick (1999).
  /// Since this is internally a two-dimensional array the access times for put and get operations
  /// will naturally be 2x slower than Buffer and Array. However, Array is not resizable and Buffer
  /// has `O(n)` memory waste.
  public type Vector<X> = {
    /// the index block
    var data_blocks : [var [var ?X]];
    /// new element should be assigned to exaclty data_blocks[i_block][i_element]
    /// i_block is in range (0; data_blocks.size()]
    var i_block : Nat;
    /// i_element is in range [0; data_blocks[i_block].size())
    var i_element : Nat;
  };

  /// Creates a new empty Vector for elements of type X.
  ///
  /// Example:
  /// ```
  /// let vec = Vector.new<Nat>(); // Creates a new Vector
  /// ```
  public func new<X>() : Vector<X> = {
    var data_blocks = [var [var]];
    var i_block = 1;
    var i_element = 0;
  };

  /// Create a Vector with `size` copies of the initial value.
  ///
  /// ```
  /// let vec = Vector.init<Nat>(4, 2); // [2, 2, 2, 2]
  /// ```
  ///
  /// Runtime: O(size)
  public func init<X>(size : Nat, initValue : X) : Vector<X> {
    let (i_block, i_element) = locate(size);

    var capacity = 0;
    var blocks = 1;
    while (capacity < size) {
      blocks := new_index_block_length(Nat32(blocks));
      capacity := if (capacity == 0) { 1 } else { capacity * 2 };
    };

    let data_blocks = Array.tabulateVar<[var ?X]>(
      blocks,
      func(i) {
        if (i < i_block) {
          Array.init<?X>(data_block_size(i), ?initValue);
        } else if (i == i_block and i_element != 0) {
          Array.tabulateVar<?X>(data_block_size(i), func(j) = if (j < i_element) { ?initValue } else { null });
        } else { [var] };
      },
    );

    {
      var data_blocks = data_blocks;
      var i_block = i_block;
      var i_element = i_element;
    };
  };

  /// Add to vector `count` copies of the initial value.
  ///
  /// ```
  /// let vec = Vector.init<Nat>(4, 2); // [2, 2, 2, 2]
  /// Vector.addMany(vec, 2, 1); // [2, 2, 2, 2, 1, 1]
  /// ```
  ///
  /// Runtime: O(count)
  public func addMany<X>(vec : Vector<X>, count : Nat, initValue : X) {
    var i = 0;
    while (i < count) {
      add(vec, initValue);
      i += 1;
    };
  };

  /// Resets the vector to size 0, de-referencing all elements.
  ///
  /// Example:
  /// ```
  ///
  /// Vector.add(vec, 10);
  /// Vector.add(vec, 11);
  /// Vector.add(vec, 12);
  /// Vector.clear(vec); // vector is now empty
  /// Vector.toArray(vec) // => []
  /// ```
  ///
  /// Runtime: O(1)
  public func clear<X>(vec : Vector<X>) {
    vec.data_blocks := [var [var]];
    vec.i_block := 1;
    vec.i_element := 0;
  };

  /// Returns a copy of a Vector, with the same size.
  ///
  /// Example:
  /// ```
  ///
  /// vec.add(1);
  ///
  /// let clone = Vector.clone(vec);
  /// Vector.toArray(clone); // => [1]
  /// ```
  ///
  /// Runtime: O(n)
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
  /// ```
  /// Vector.size(vec) // => 0
  /// ```
  ///
  /// Runtime: O(1) (with some internal calculations)
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

  func data_block_size(i_block : Nat) : Nat {
    // formula for the size of given i_block
    Nat(1 <>> leadingZeros(Nat32(i_block) / 3));
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

  /// Adds a single element to the end of a Vector,
  /// allocating a new internal data block if needed,
  /// and resizing the internal index block if needed.
  ///
  /// Example:
  /// ```
  ///
  /// Vector.add(vec, 0); // add 0 to vector
  /// Vector.add(vec, 1);
  /// Vector.add(vec, 2);
  /// Vector.add(vec, 3);
  /// Vector.toArray(vec) // => [0, 1, 2, 3]
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
  };

  /// Removes and returns the last item in the vector or `null` if
  /// the vector is empty.
  ///
  /// Example:
  /// ```
  ///
  /// Vector.add(vec, 10);
  /// Vector.add(vec, 11);
  /// Vector.removeLast(vec); // => ?11
  /// ```
  ///
  /// Amortized Runtime: O(1), Worst Case Runtime: O(sqrt(n))
  ///
  /// Amortized Space: O(1), Worst Case Space: O(sqrt(n))
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
  /// Traps if `index >= size`, error message may not be descriptive.
  ///
  /// Example:
  /// ```
  ///
  /// Vector.add(vec, 10);
  /// Vector.add(vec, 11);
  /// Vector.get(vec, 0); // => 10
  /// ```
  ///
  /// Runtime: O(1)
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
    let ?result = if (lz & 1 == 0) {
      vec.data_blocks[Nat(((i << lz2) >> 16) ^ (0x10000 >> lz2))][Nat(i & (0xFFFF >> lz2))];
    } else {
      vec.data_blocks[Nat(((i << lz2) >> 15) ^ (0x18000 >> lz2))][Nat(i & (0x7FFF >> lz2))];
    } else {
      Prim.trap "Vector index out of bounds in get";
    };
    result;
  };

  /// Returns the element at index `index` as an option.
  /// Returns `null` when `index >= size`. Indexing is zero-based.
  ///
  /// Example:
  /// ```
  ///
  /// Vector.add(vec, 10);
  /// Vector.add(vec, 11);
  /// let x = Vector.getOpt(vec, 0); // => ?10
  /// let y = Vector.getOpt(vec, 2); // => null
  /// ```
  ///
  /// Runtime: O(1)
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
  /// ```
  ///
  /// Vector.add(vec, 10);
  /// Vector.put(vec, 0, 20); // overwrites 10 at index 0 with 20
  /// Vector.toArray(vec) // => [20]
  /// ```
  ///
  /// Runtime: O(1)
  public func put<X>(vec : Vector<X>, index : Nat, value : X) {
    let (a, b) = locate(index);
    if (a < vec.i_block or a == vec.i_block and b < vec.i_element) {
      vec.data_blocks[a][b] := ?value;
    } else Prim.trap "Vector index out of bounds in put";
  };

  /// Finds the first index of `element` in `vector` using equality of elements defined
  /// by `equal`. Returns `null` if `element` is not found.
  ///
  /// Example:
  /// ```
  ///
  /// let vector = Vector.new<Nat>();
  /// vector.add(1);
  /// vector.add(2);
  /// vector.add(3);
  /// vector.add(4);
  ///
  /// Vector.indexOf<Nat>(3, vector, Nat.equal); // => ?2
  /// ```
  ///
  /// Runtime: O(size)
  ///
  /// *Runtime and space assumes that `equal` runs in O(1) time and space.
  public func indexOf<X>(element : X, vec : Vector<X>, equal : (X, X) -> Bool) : ?Nat {
    for ((x, i) in items(vec)) {
      if (equal(x, element)) return ?i;
    };
    null;
  };

  /// Finds the last index of `element` in `vector` using equality of elements defined
  /// by `equal`. Returns `null` if `element` is not found.
  ///
  /// Example:
  /// ```
  /// let vector = Vector.new<Nat>();
  /// vector.add(1);
  /// vector.add(2);
  /// vector.add(3);
  /// vector.add(4);
  /// vector.add(2);
  /// vector.add(2);
  ///
  /// Vector.lastIndexOf<Nat>(2, vector, Nat.equal); // => ?5
  /// ```
  ///
  /// Runtime: O(size)
  ///
  /// *Runtime and space assumes that `equal` runs in O(1) time and space.
  public func lastIndexOf<X>(element : X, vec : Vector<X>, equal : (X, X) -> Bool) : ?Nat {
    for ((x, i) in itemsRev(vec)) {
      if (equal(x, element)) return ?i;
    };
    null;
  };

  /// Returns an Iterator (`Iter`) over the elements of a Vector.
  /// Iterator provides a single method `next()`, which returns
  /// elements in order, or `null` when out of elements to iterate over.
  ///
  /// ```
  ///
  /// Vector.add(vec, 10);
  /// Vector.add(vec, 11);
  /// Vector.add(vec, 12);
  ///
  /// var sum = 0;
  /// for (element in Vector.vals(vec)) {
  ///   sum += element;
  /// };
  /// sum // => 33
  /// ```
  ///
  /// Note: This does not create a snapshot. If the returned iterator is not consumed at once,
  /// and instead the consumption of the iterator is interleaved with other operations on the
  /// Vector, then this may lead to unexpected results.
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
        case (?element) {
          i_element += 1;
          if (i_element == block.size()) {
            i_block += 1;
            i_element := 0;
          };
          ?element;
        };
        case (null) null;
      };
    };
  };

  /// Returns an Iterator (`Iter`) over the items, i.e. pairs of value and index of a Vector.
  /// Iterator provides a single method `next()`, which returns
  /// elements in order, or `null` when out of elements to iterate over.
  ///
  /// ```
  ///
  /// Vector.add(vec, 10);
  /// Vector.add(vec, 11);
  /// Vector.add(vec, 12);
  /// Iter.toArray(Vector.items(vec)); // [(10, 0), (11, 1), (12, 2)]
  /// ```
  ///
  /// Note: This does not create a snapshot. If the returned iterator is not consumed at once,
  /// and instead the consumption of the iterator is interleaved with other operations on the
  /// Vector, then this may lead to unexpected results.
  ///
  /// Runtime: O(1)
  public func items<X>(vec : Vector<X>) : Iter.Iter<(X, Nat)> = object {
    var i_block = 1;
    var i_element = 0;
    var i = 0;

    public func next() : ?(X, Nat) {
      if (i_block >= vec.data_blocks.size()) {
        return null;
      };
      let block = vec.data_blocks[i_block];
      if (block.size() == 0) {
        return null;
      };
      switch (block[i_element]) {
        case (?element) {
          let ret = ?(element, i);
          i += 1;
          i_element += 1;
          if (i_element == block.size()) {
            i_block += 1;
            i_element := 0;
          };
          ret;
        };
        case (null) null;
      };
    };
  };

  /// Returns an Iterator (`Iter`) over the elements of a Vector in reverse order.
  /// Iterator provides a single method `next()`, which returns
  /// elements in reverse order, or `null` when out of elements to iterate over.
  ///
  /// ```
  ///
  /// Vector.add(vec, 10);
  /// Vector.add(vec, 11);
  /// Vector.add(vec, 12);
  ///
  /// var sum = 0;
  /// for (element in Vector.vals(vec)) {
  ///   sum += element;
  /// };
  /// sum // => 33
  /// ```
  ///
  /// Note: This does not create a snapshot. If the returned iterator is not consumed at once,
  /// and instead the consumption of the iterator is interleaved with other operations on the
  /// Vector, then this may lead to unexpected results.
  ///
  /// Runtime: O(1)
  public func valsRev<X>(vec : Vector<X>) : Iter.Iter<X> = object {
    var i_block = vec.i_block;
    var i_element = vec.i_element;

    public func next() : ?X {
      if (i_block == 1) {
        return null;
      };
      let block = if (i_element == 0) {
        i_block -= 1;
        let b = vec.data_blocks[i_block];
        i_element := b.size() - 1;
        b;
      } else {
        i_element -= 1;
        vec.data_blocks[i_block];
      };

      block[i_element];
    };
  };

  /// Returns an Iterator (`Iter`) over the items in reverse order, i.e. pairs of value and index of a Vector.
  /// Iterator provides a single method `next()`, which returns
  /// elements in reverse order, or `null` when out of elements to iterate over.
  ///
  /// ```
  ///
  /// Vector.add(vec, 10);
  /// Vector.add(vec, 11);
  /// Vector.add(vec, 12);
  /// Iter.toArray(Vector.items(vec)); // [(12, 0), (11, 1), (10, 2)]
  /// ```
  ///
  /// Note: This does not create a snapshot. If the returned iterator is not consumed at once,
  /// and instead the consumption of the iterator is interleaved with other operations on the
  /// Vector, then this may lead to unexpected results.
  ///
  /// Runtime: O(1)
  public func itemsRev<X>(vec : Vector<X>) : Iter.Iter<(X, Nat)> = object {
    var i_block = vec.i_block;
    var i_element = vec.i_element;
    var i = size(vec);

    public func next() : ?(X, Nat) {
      if (i_block == 1) {
        return null;
      };
      let block = if (i_element == 0) {
        i_block -= 1;
        let b = vec.data_blocks[i_block];
        i_element := b.size() - 1;
        b;
      } else {
        i_element -= 1;
        vec.data_blocks[i_block];
      };
      i -= 1;

      let ?x = block[i_element] else Prim.trap("Internal error in Vector");

      ?(x, i);
    };
  };

  /// Returns an Iterator (`Iter`) over the keys (indices) of a Vector.
  /// Iterator provides a single method `next()`, which returns
  /// elements in order, or `null` when out of elements to iterate over.
  ///
  /// ```
  ///
  /// Vector.add(vec, 10);
  /// Vector.add(vec, 11);
  /// Vector.add(vec, 12);
  /// Iter.toArray(Vector.items(vec)); // [0, 1, 2]
  /// ```
  ///
  /// Note: This does not create a snapshot. If the returned iterator is not consumed at once,
  /// and instead the consumption of the iterator is interleaved with other operations on the
  /// Vector, then this may lead to unexpected results.
  ///
  /// Runtime: O(1)
  public func keys<X>(vec : Vector<X>) : Iter.Iter<Nat> = Iter.range(0, size(vec));

  /// Creates a Vector containing elements from `iter`.
  ///
  /// Example:
  /// ```
  /// import Nat "mo:base/Nat";
  ///
  /// let array = [1, 1, 1];
  /// let iter = array.vals();
  ///
  /// let vec = Vector.fromIter<Nat>(iter); // => [1, 1, 1]
  /// ```
  ///
  /// Runtime: O(n)
  public func fromIter<X>(iter : Iter.Iter<X>) : Vector<X> {
    let vec = new<X>();
    for (element in iter) add(vec, element);
    vec;
  };

  /// Appends elements to a Vector from `iter`.
  ///
  /// Example:
  /// ```
  /// import Nat "mo:base/Nat";
  ///
  /// let array = [1, 1, 1];
  /// let iter = array.vals();
  /// let vec = Vector.init<Nat>(1, 2);
  ///
  /// let vec = Vector.append<Nat>(vec, iter); // => [2, 1, 1, 1]
  /// ```
  ///
  /// Runtime: O(n), where n is the size of iter.
  public func append<X>(vec : Vector<X>, iter : Iter.Iter<X>) {
    for (element in iter) add(vec, element);
  };

  /// Creates an immutable array containing elements from a Vector.
  ///
  /// Example:
  /// ```
  ///
  /// Vector.add(vec, 1);
  /// Vector.add(vec, 2);
  /// Vector.add(vec, 3);
  ///
  /// Vector.toArray<Nat>(vec); // => [1, 2, 3]
  ///
  /// ```
  ///
  /// Runtime: O(n)
  public func toArray<X>(vec : Vector<X>) : [X] = Array.tabulate<X>(size(vec), func(i) = get(vec, i));

  /// Creates a Vector containing elements from an Array.
  ///
  /// Example:
  /// ```
  /// import Nat "mo:base/Nat";
  ///
  /// let array = [2, 3];
  ///
  /// let vec = Vector.fromArray<Nat>(array); // => [2, 3]
  /// ```
  ///
  /// Runtime: O(n)
  public func fromArray<X>(array : [X]) : Vector<X> = fromIter(array.vals());

  /// Creates a mutable Array containing elements from a Vector.
  ///
  /// Example:
  /// ```
  ///
  /// Vector.add(vec, 1);
  /// Vector.add(vec, 2);
  /// Vector.add(vec, 3);
  ///
  /// Vector.toVarArray<Nat>(vec); // => [1, 2, 3]
  ///
  /// ```
  ///
  /// Runtime: O(n)
  public func toVarArray<X>(vec : Vector<X>) : [var X] = Array.tabulateVar<X>(size(vec), func(i) = get(vec, i));

  /// Creates a Vector containing elements from a mutable Array.
  ///
  /// Example:
  /// ```
  /// import Nat "mo:base/Nat";
  ///
  /// let array = [var 2, 3];
  ///
  /// let vec = Vector.fromVarArray<Nat>(array); // => [2, 3]
  /// ```
  ///
  /// Runtime: O(n)
  public func fromVarArray<X>(array : [var X]) : Vector<X> = fromIter(array.vals());
};
