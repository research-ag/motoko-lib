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

Initialize the PRNG with a particular seed


### Function `next`
``` motoko
func next() : Nat64
```

Return the PRNG result and advance the state


### Function `jump32`
``` motoko
func jump32()
```

Advance the state 2^32 times


### Function `jump64`
``` motoko
func jump64()
```

Advance the state 2^64 times


### Function `jump96`
``` motoko
func jump96()
```

Advance the state 2^96 times

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

Initialize the PRNG with a particular seed


### Function `init`
``` motoko
func init()
```



### Function `next`
``` motoko
func next() : Nat64
```

Return the PRNG result and advance the state

## Class `SFC32`

``` motoko
class SFC32(p : Nat32, q : Nat32, r : Nat32)
```


### Function `init3`
``` motoko
func init3(seed1 : Nat32, seed2 : Nat32, seed3 : Nat32)
```

Initialize the PRNG with 3 seeds


### Function `init1`
``` motoko
func init1(seed : Nat32)
```

Initialize the PRNG with a particular seed


### Function `init`
``` motoko
func init()
```

Initialize the PRNG


### Function `next`
``` motoko
func next() : Nat32
```

Return the PRNG result and advance the state

## Function `SFC64a`
``` motoko
func SFC64a() : SFC64
```

SFC64a is same as numpy:
https:///github.com/numpy/numpy/blob/b6d372c25fab5033b828dd9de551eb0b7fa55800/numpy/random/src/sfc64/sfc64.h#L28

## Function `SFC32a`
``` motoko
func SFC32a() : SFC32
```

Use this  

## Function `SFC32b`
``` motoko
func SFC32b() : SFC32
```

Use this.

## Function `SFC64b`
``` motoko
func SFC64b() : SFC64
```

Not recommended. Use `a` version.

## Function `SFC32c`
``` motoko
func SFC32c() : SFC32
```

Not recommended. Use `a` version.
