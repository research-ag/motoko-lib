# Sha256/Sha512

The two modules `Sha256` and `Sha512` provide all hash functions from the Sha2 family.
Those based on 32 byte state (sha256 and its variant sha224) are in `Sha256`,
those based on 64 byte state (sha512 and its variants sha512-224, sha512-256, sha384) are in `Sha512`.

Unlike other packages out there, which often only accept type `[Nat8]` as input, 
this package directly and more efficiently accepts input types `Blob` and `Iter<Nat8>`. 

The output type of the digest is `Blob`.

The modules are cycle optimized. To our knowledge they are the fastest Sha2 libraries.

The cost per block/chunk is (per moc 0.8.3):

* sha224/sha256: 34,578 cycles per chunk (64 bytes) or 540 cycles per byte
* sha512 variants: 53,801 cycles per chunk (128 bytes) or 420 cycles per byte

The cost for hashing the empty message is (per moc 0.8.3):

* sha256: 36,193 cycles
* sha512: 54,590 cycles

This means the per message overhead for setting up the Digest class, padding, length bytes, and extraction of the digest is not noticeable.

We measured the most commonly used sha256 implementations at between 48k - 52k cycles per chunk and the empty message at around 100k cycles.

## Examples

<iframe src="https://embed.smartcontracts.org/motoko/g/5YAikwp8VvVu8AfcaT8L8ji7wBvpt7SX8vBTzLrVouknSbV7GVWT6HESKFfMmREbLYYEUowKobUxB1hQNo52ysC8AFF1JTS5AriGfgb7ur7QczG1tcYCYDYYqsJaU6xHgPXQAWMzEp7i8toUa9m9jqS1P3Bx6aNJZzMcSCsFRTc4PPYLSSyqprA9YbwLRm3bz?lines=7" width="100%" height="408" style="border:0" title="Motoko code snippet" />