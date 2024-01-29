# StableBuffer

## Type `StableData`
``` motoko
type StableData = { bytes : Region; var bytes_count : Nat64; elems : Region; var elems_count : Nat64 }
```


## Class `StableBuffer<T>`

``` motoko
class StableBuffer<T>(serialize : (T) -> Blob, deserialize : (Blob) -> T)
```


### Function `add`
``` motoko
func add(item : T) : Bool
```



### Function `get`
``` motoko
func get(index : Nat) : T
```



### Function `size`
``` motoko
func size() : Nat
```



### Function `bytes`
``` motoko
func bytes() : Nat
```



### Function `pages`
``` motoko
func pages() : Nat
```



### Function `setMaxPages`
``` motoko
func setMaxPages(max : ?Nat64)
```



### Function `share`
``` motoko
func share() : StableData
```



### Function `unshare`
``` motoko
func unshare(data : StableData)
```

