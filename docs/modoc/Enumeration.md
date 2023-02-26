# Enumeration

## Type `Tree`
``` motoko 
type Tree = {#node : ({#R; #B}, Tree, Nat, Tree); #leaf}
```


## Class `Enumeration`

``` motoko 
class Enumeration()
```


### Function `add`
``` motoko 
func add(x : Blob)
```



### Function `lookup`
``` motoko 
func lookup(key : Blob) : ?Nat
```



### Function `get`
``` motoko 
func get(i : Nat) : Blob
```



### Function `share`
``` motoko 
func share() : (Tree, [Blob])
```



### Function `unshare`
``` motoko 
func unshare(t : Tree, a : [Blob])
```

