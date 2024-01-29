# IncreasingKeyMap

## Type `StableData`
``` motoko
type StableData = { data : Region; var count : Nat64; var last_key : Nat32 }
```

Stable data type

## Class `IncreasingKeyMap`

``` motoko
class IncreasingKeyMap()
```

Map from keys to values, keys should be incresing in order of addition

### Function `add`
``` motoko
func add(key : Nat32, value : Nat64)
```

Add key-value pair to array assuming keys are increasing in order of addition


### Function `find`
``` motoko
func find(key : Nat32) : ?Nat64
```

Find value corresponding to `key` or return null if there is no such `key`


### Function `reset`
``` motoko
func reset()
```

Reset state with saving region


### Function `share`
``` motoko
func share() : StableData
```

Share stable content


### Function `unshare`
``` motoko
func unshare(data : StableData)
```

Unshare from stable content
