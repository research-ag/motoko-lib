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
`data_blocks[i_block][i_element]$.
We do not store any more information to reduce memory.
But we also do not store less any information (such as only the total size in a single variable)
as to not slow down access.

When growing we resize `data_blocks` (the outer array) so that it can store exactly one next super block. But unused data blocks in the last super block are not allocated, i.e. set to the empty array. 

When shrinking we keep space in `data_blocks` for two additional super blocks. But unused data blocks in the last two super blocks are deallocated, i.e. set to the empty array.

## Examples

<iframe src="https://embed.smartcontracts.org/motoko/g/2fkWTFU9s4KAePQnz2SPmGQV6TQnhFUVpxE4BxC6YdxAbDUE7gF2Ukk6xL9BmniiJq8Pk9NYNwrMcmk6f9V4dN3HsvkCv75rWQCW2TMiSNg4okGghT8HgAGbL725V5zgucuAQV9D151NLDSkrhQ896mxCkDufa7is9Z2Wiz6EnnF5aEbebnyBtSyTNUPnY4NhysUWCQEurQfLEegNhD?lines=12" width="100%" height="408" style="border:0" title="Motoko code snippet" />