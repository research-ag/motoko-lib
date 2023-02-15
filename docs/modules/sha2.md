# Sha256/Sha512

The two modules `Sha256` and `Sha512` provide all hash functions from the Sha2 family.
Those based on 32 byte state (sha256 and its variant sha224) are in `Sha256`,
those based on 64 byte state (sha512 and its variants sha512-224, sha512-256, sha384) are in `Sha512`.

Unlike other packages out there, which often only accept type `[Nat8]` as input, 
this package directly and more efficiently accepts input types `Blob` and `Iter<Nat8>`. 

The output type of the digest is `Blob`.

The modules are cycle optimized. To our knowledge they are the fastest Sha2 libraries.