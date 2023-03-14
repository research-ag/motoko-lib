# Prng
Implementation of the 128-bit Seiran PRNG
See: https://github.com/andanteyk/prng-seiran

WARNING: This is not a cryptographically secure pseudorandom
number generator.

## Class `Seiran128`

``` motoko
class Seiran128()
```


### Function `init`
``` motoko
func init(seed : Nat64)
```



### Function `next`
``` motoko
func next() : Nat64
```



### Function `jump32`
``` motoko
func jump32()
```



### Function `jump64`
``` motoko
func jump64()
```



### Function `jump96`
``` motoko
func jump96()
```


## Class `SFC64`

``` motoko
class SFC64(p : Nat64, q : Nat64, r : Nat64)
```


### Function `init3`
``` motoko
func init3(seed1 : Nat64, seed2 : Nat64, seed3 : Nat64)
```



### Function `init1`
``` motoko
func init1(seed : Nat64)
```



### Function `init`
``` motoko
func init()
```



### Function `next`
``` motoko
func next() : Nat64
```


## Class `SFC32`

``` motoko
class SFC32(p : Nat32, q : Nat32, r : Nat32)
```


### Function `init3`
``` motoko
func init3(seed1 : Nat32, seed2 : Nat32, seed3 : Nat32)
```



### Function `init1`
``` motoko
func init1(seed : Nat32)
```



### Function `init`
``` motoko
func init()
```



### Function `next`
``` motoko
func next() : Nat32
```


## Function `SFC64a`
``` motoko
func SFC64a() : SFC64
```


## Function `SFC32a`
``` motoko
func SFC32a() : SFC32
```


## Function `SFC32b`
``` motoko
func SFC32b() : SFC32
```


## Function `SFC64b`
``` motoko
func SFC64b() : SFC64
```


## Function `SFC32c`
``` motoko
func SFC32c() : SFC32
```

