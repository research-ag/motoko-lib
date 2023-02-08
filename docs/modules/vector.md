# Vector

The Vector data structure is meant to be a replacement for Array when a growable and/or shrinkable data structure is needed.
It provides random access like Array and Buffer and can grow and shrink at the end like Buffer can.
Unlike Buffer the memory overhead for allocated but no yet used space is $O(\sqrt{n})$ instead of $O(n)$.

## Design

The data structure is based on the paper "Resizable Arrays in Optimal Time and Space" by Brodnik, Carlsson, Demaine, Munro and Sedgewick (1999) ([pdf](https://sedgewick.io/wp-content/themes/sedgewick/papers/1999Optimal.pdf)).

## Implementation notes

Our data structure is slightly different from that in the article. Here's explanation.
The data structure consists of virtual super blocks, each super block consists of physical data blocks. Data blocks of each super block stored one by one in data_blocks array. Let $f(i)$ be size of $i$-th  super block, then
$f(0) = 0, f(1) = 1, f(i + 2) = 2 ^ i$ for $i >= 0$.

Each super block of size $2 ^ i$ consists of $2^{\lfloor i / 2\rfloor}$ data blocks of size $2^{\lceil i / 2 \rceil}$.

Except for data_blocks array the Vector itself constains pair i_block, i_element meaning that the next element should be assigned to $\verb|data_blocks|[\verb|i_block|][\verb|i_element|]$. We don't store more fields to reduce memory, but we don't store only size to make addition faster.

When growing we resize data_blocks array so that it can store exactly one next super block. When shrkinking we keep space in data_blocks array for two next super blocks.

## Optimal memory waste

The minimal possible memory waste is $O(\sqrt{n})$, here is idea of proof.

Assume store in n elements in A different sequential arrays. Let B be maximum size of such an array. Then memory waste is $O(max(A, B))$, because we have to store somehow pointers to all the arrays and we count it as memory waste, and maximum empty space is $O(B)$, when new array is allocated. $A * B >= n$ then minimal memory waste is $O(\sqrt{n})$.

## Examples

<iframe src="https://embed.smartcontracts.org/motoko/g/2fkWTFU9s4KAePQnz2SPmGQV6TQnhFUVpxE4BxC6YdxAbDUE7gF2Ukk6xL9BmniiJq8Pk9NYNwrMcmk6f9V4dN3HsvkCv75rWQCW2TMiSNg4okGghT8HgAGbL725V5zgucuAQV9D151NLDSkrhQ896mxCkDufa7is9Z2Wiz6EnnF5aEbebnyBtSyTNUPnY4NhysUWCQEurQfLEegNhD?lines=12" width="100%" height="408" style="border:0" title="Motoko code snippet" />