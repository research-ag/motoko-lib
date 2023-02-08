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

Except for data_blocks array the Vector itself constains pair i_block, i_element meaning that the next element should be assigned to data_blocks[i_block][i_element]. We don't store more fields to reduce memory, but we don't store only size to make addition faster.

When growing we resize data_blocks array so that it can store exactly one next super block. When shrkinking we keep space in data_blocks array for two next super blocks.

## Examples

<iframe src="https://embed.smartcontracts.org/motoko/g/DLr1Cy6mYjpKc4apwqWWSzBL6iYPq9EvGHUa5dDxt8wHhRUJJBCPZv6NdPU3fEvaaxG6iEdcybWdGHJ1sUFJADPeWmrv2WAgxwd35aesNfnqm6U5CfKJ2VM9iYjfj7udbiDNQLaEKSvmzpR4YoQBFVUt3pzMLoHiCk6wu8u5keX2JaE?lines=9" width="100%" height="336" style="border:0" title="Motoko code snippet" />
