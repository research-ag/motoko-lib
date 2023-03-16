# Enumeration

Enumeration of `Blob`s in order they are added, essentially in case `n` `Blob`s have been added the Enumeration is an efficient append-only bijective map `[0,n) -> Blob`. The key functions are:

- `add` function adds `Blob` searches if the given `Blob` is already in data structure and returns it's index, and adds `Blob` to the end of the array and returns size of the array minus one.

- The data structure does not support the delition of `Blob`s.

- `lookup` function from `Blob` to `Nat`, which returns number in which given `Blob` was added or null if there is no such `Blob`. For this map there is a red-black tree, so `lookup` works in `O(log(n))`.

- `get` function from `Nat` to `Blob`, which returns `Blob` with given index. For this map there is an array, so `get` works in `O(1)`.

## Implementation notes

`Blob`s are stored once, in the array, while in red-black tree we store the index of a `Blob`.

The array is being growed by $\approx \sqrt{2}$ when is full.

## Examples

<iframe src="https://embed.smartcontracts.org/motoko/g/ErXSnfAra9mvwuXbkEcz5cAeADEuozpd4pS3RH7arZNJNxB6ds7HkXH9ZfsVYQe3dFaDLcQYd1ZSxaX3tHFGxY9PfudsLuiJ8FsRZbBj9uz7CEWtLHZ6TrnguHGCpEsenSpLG1LhCU1K6y3gwLG3wsLWFaE3uyPt9vyUJ8QbUs68ryNDSRkhpAkNc37YYMUDsnE2FocCC17eDzPuhykMXizhxCEchCMJszBvMLhVaQfncXrCWrsEmQfXGh7cBx5Xjjc2nobHD4rohvZyz5ZsTw46PJkttbzdKpuzdE2Rqm7BSdNadn2Bo4PZcSdWe?lines=13" width="100%" height="408" style="border:0" title="Motoko code snippet" />