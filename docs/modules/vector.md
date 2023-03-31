# Vector

The Vector data structure is meant to be a replacement for Array when a growable and/or shrinkable data structure is needed.
It provides random access like Array and Buffer and can grow and shrink at the end like Buffer can.
Unlike Buffer, the memory overhead for allocated but no yet used space is $O(\sqrt{n})$ instead of $O(n)$.

## Design

The data structure is based on the paper ["Resizable Arrays in Optimal Time and Space"](https://sedgewick.io/wp-content/themes/sedgewick/papers/1999Optimal.pdf) by Brodnik, Carlsson, Demaine, Munro and Sedgewick (1999).

The vector elements are stored in so-called data blocks and
the whole data structure consists of a sequence of data blocks of increasing size.
Hence it is in fact a two-dimensional array (but not a "square" one).

The trick lies in the selection of the sizes of the data blocks. 
They are chosen such that the conversion of the externally used single index 
to the internally used index pair can be cheaply done by bit shifts.

The data block sizes can be better understood when thinking of the data blocks being arranged in "super blocks".
Super blocks are merely a virtual concept and have no manifestation in the implementation.
The capacity of a super block is always a $2$-power.
The $i$-th super block has capacity $2^i$ and consists of $2^{\lfloor i / 2\rfloor}$ data blocks of size $2^{\lceil i / 2 \rceil}$.
This is followed by the next super block of capacity $2^{i+1}$ and so on.

Hence, the sequence of data block sizes look like this:

$$1,\ \ 2,\ \ 2,2,\ \ 4,4,\ \ 4,4,4,4,\ \ 8,8,8,8,\ \ ...$$

where the additional white space indicates super block boundaries. 

## Implementation notes

Each data block is a mutable array of type `[var ?X]` where `X` is the element type.
The data blocks themselves are stored in the mutable array called `data_blocks`.
Hence `data_blocks` has type `[var [var ?X]]`.

The present implementation differs from the article in that the data block indices are shifted by $2$ and we introduce two data blocks of size $0$ and $1$ at the beginning of the sequence.
This makes the access faster because it eliminates the frequent computation of $i+2$ in the internal formulas needed for index conversion.

Besides the `data_blocks` array, the `Vector` type constains the index pair `i_block`, `i_element` which means the next position that should be written by an `add` operation:
`data_blocks[i_block][i_element]`.
We do not store any more information to reduce memory.
But we also do not store less any information (such as only the total size in a single variable)
as to not slow down access.

When growing we resize `data_blocks` (the outer array) so that it can store exactly one next super block. But unused data blocks in the last super block are not allocated, i.e. set to the empty array. 

When shrinking we keep space in `data_blocks` for two additional super blocks. But unused data blocks in the last two super blocks are deallocated, i.e. set to the empty array.

### Explanation of `locate` function

One of the core functions is `locate` which returns a data block and location in that data block of the given index.

```
func locate_readable<X>(index : Nat) : (Nat, Nat) {
  // index is any Nat32 except for
  // blocks before super block s == 2 ** s
  let i = Nat32.fromNat(index);
  // element with index 0 located in data block with index 1
  if (i == 0) {
    return (1, 0);
  };
  let lz = Nat32.bitcountLeadingZero(i);
  // super block s = bit length - 1 = (32 - leading zeros) - 1
  // i in binary = zeroes; 1; bits blocks mask; bits element mask
  // bit lengths =     lz; 1;     floor(s / 2);       ceil(s / 2)
  let s = 31 - lz;
  // floor(s / 2)
  let down = s >> 1;
  // ceil(s / 2) = floor((s + 1) / 2)
  let up = (s + 1) >> 1;
  // element mask = ceil(s / 2) ones in binary
  let e_mask = 1 << up - 1;
  //block mask = floor(s / 2) ones in binary
  let b_mask = 1 << down - 1;
  // data blocks in even super blocks before current = 2 ** ceil(s / 2)
  // data blocks in odd super blocks before current = 2 ** floor(s / 2)
  // data blocks before the super block = element mask + block mask
  // elements before the super block = 2 ** s
  // first floor(s / 2) bits in index after the highest bit = index of data block in super block
  // the next ceil(s / 2) to the end of binary representation of index + 1 = index of element in data block
  (Nat32.toNat(e_mask + b_mask + 2 + (i >> up) & b_mask), Nat32.toNat(i & e_mask));
};
```

```
// this was optimized in terms of instructions
func locate_optimal<X>(index : Nat) : (Nat, Nat) {
  // super block s = bit length - 1 = (32 - leading zeros) - 1
  // blocks before super block s == 2 ** s
  let i = Nat32.fromNat(index);
  let lz = Nat32.bitcountLeadingZero(i);
  let lz2 = lz >> 1;
  // we split into cases to apply different optimizations in each one
  if (lz & 1 == 0) {
    // ceil(s / 2)  = 16 - lz2
    // floor(s / 2) = 15 - lz2
    // i in binary = zeroes; 1; bits blocks mask; bits element mask
    // bit lengths =     lz; 1;         15 - lz2;          16 - lz2
    // blocks before = 2 ** ceil(s / 2) + 2 ** floor(s / 2)

    // so in order to calculate index of the data block
    // we need to shift i by 16 - lz2 and set bit with number 16 - lz2, bit 15 - lz2 is already set

    // element mask = 2 ** (16 - lz2) = (1 << 16) >> lz2 = 0xFFFF >> lz2
    let mask = 0xFFFF >> lz2;
    (Nat32.toNat(((i << lz2) >> 16) ^ (0x10000 >> lz2)), Nat32.toNat(i & (0xFFFF >> lz2)));
  } else {
    // s / 2 = ceil(s / 2) = floor(s / 2) = 15 - lz2
    // i in binary = zeroes; 1; bits blocks mask; bits element mask
    // bit lengths =     lz; 1;         15 - lz2;          15 - lz2
    // block mask = element mask = mask = 2 ** (s / 2) - 1 = 2 ** (15 - lz2) - 1 = (1 << 15) >> lz2 = 0x7FFF >> lz2
    // blocks before = 2 * 2 ** (s / 2)

    // so in order to calculate index of the data block
    // we need to shift i by 15 - lz2, set bit with number 16 - lz2 and unset bit 15 - lz2

    let mask = 0x7FFF >> lz2;
    (Nat32.toNat(((i << lz2) >> 15) ^ (0x18000 >> lz2)), Nat32.toNat(i & (0x7FFF >> lz2)));
  };
};
```

## Examples

<iframe src="https://embed.smartcontracts.org/motoko/g/2fkWTFU9s4KAePQnz2SPmGQV6TQnhFUVpxE4BxC6YdxAbDUE7gF2Ukk6xL9BmniiJq8Pk9NYNwrMcmk6f9V4dN3HsvkCv75rWQCW2TMiSNg4okGghT8HgAGbL725V5zgucuAQV9D151NLDSkrhQ896mxCkDufa7is9Z2Wiz6EnnF5aEbebnyBtSyTNUPnY4NhysUWCQEurQfLEegNhD?lines=12" width="100%" height="408" style="border:0" title="Motoko code snippet" />