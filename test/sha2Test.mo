import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";
import Blob "mo:base/Blob";
import Array "mo:base/Array";
import Iter "mo:base/Iter";
import Sha2 "../src/Sha2";
import BigEndian "../src/sha2/bigendian";

var n = 20;
assert BigEndian.fromNat(4, n) == BigEndian.fromNat32(Nat32.fromNat(n));
assert BigEndian.fromNat(8, n) == BigEndian.fromNat64(Nat64.fromNat(n));

n := 1234567890;
assert BigEndian.fromNat(4, n) == BigEndian.fromNat32(Nat32.fromNat(n));
n := 12345678910111213141;
assert BigEndian.fromNat(8, n) == BigEndian.fromNat64(Nat64.fromNat(n));

// empty string

let b = Blob.fromArray([] : [Nat8]);
// sha256
do {
  let h = Blob.fromArray([227 : Nat8, 176, 196, 66, 152, 252, 28, 20, 154, 251, 244, 200, 153, 111, 185, 36, 39, 174, 65, 228, 100, 155, 147, 76, 164, 149, 153, 27, 120, 82, 184, 85]);
  assert(Sha2.fromBlob(#sha256,b) == h);
};

// sha224
do {
  let h = Blob.fromArray([209 : Nat8, 74, 2, 140, 42, 58, 43, 201, 71, 97, 2, 187, 40, 130, 52, 196, 21, 162, 176, 31, 130, 142, 166, 42, 197, 179, 228, 47]);
  assert(Sha2.fromBlob(#sha224,b) == h);
};

// sha512
do {
  let h = Blob.fromArray([207 : Nat8, 131, 225, 53, 126, 239, 184, 189, 241, 84, 40, 80, 214, 109, 128, 7, 214, 32, 228, 5, 11, 87, 21, 220, 131, 244, 169, 33, 211, 108, 233, 206, 71, 208, 209, 60, 93, 133, 242, 176, 255, 131, 24, 210, 135, 126, 236, 47, 99, 185, 49, 189, 71, 65, 122, 129, 165, 56, 50, 122, 249, 39, 218, 62]);
  assert(Sha2.fromBlob(#sha512,b) == h);
};

// sha512-224
do {
  let h = Blob.fromArray([110, 208, 221, 2, 128, 111, 168, 158, 37, 222, 6, 12, 25, 211, 172, 134, 202, 187, 135, 214, 160, 221, 208, 92, 51, 59, 132, 244]);
  assert(Sha2.fromBlob(#sha512_224,b) == h);
};

// sha512-256
do {
  let h = Blob.fromArray([198, 114, 184, 209, 239, 86, 237, 40, 171, 135, 195, 98, 44, 81, 20, 6, 155, 221, 58, 215, 184, 249, 115, 116, 152, 208, 192, 30, 206, 240, 150, 122]);
  assert(Sha2.fromBlob(#sha512_256,b) == h);
};

// sha384
do {
  let h = Blob.fromArray([56 : Nat8, 176, 96, 167, 81, 172, 150, 56, 76, 217, 50, 126, 177, 177, 227, 106, 33, 253, 183, 17, 20, 190, 7, 67, 76, 12, 199, 191, 99, 246, 225, 218, 39, 78, 222, 191, 231, 111, 101, 251, 213, 26, 210, 241, 72, 152, 185, 91]);
  assert(Sha2.fromBlob(#sha384,b) == h);
};

// string of 640,000 zero bytes

do {
  let data = Blob.fromArrayMut(Array.init<Nat8>(64, 0));
  let (digest256, digest512) = (
    Sha2.Digest(#sha256),
    Sha2.Digest(#sha512)
    );
  var read256 = 0;
  var read512 = 0;
  for (i in Iter.range(1,10000)) {
    read256 += digest256.write(data.vals());
    read512 += digest512.write(data.vals());
  };
  assert(read256 == 10000 * 64);
  assert(read512 == 10000 * 64);
  let h256 = Blob.fromArray([61 : Nat8, 0, 237, 134, 182, 99, 205, 27, 138, 200, 43, 16, 82, 87, 205, 16, 148, 18, 249, 45, 202, 68, 32, 72, 83, 36, 57, 249, 32, 167, 246, 69]);
  let h512 = Blob.fromArray([185, 210, 89, 99, 251, 49, 143, 153, 12, 142, 84, 169, 249, 148, 175, 61, 145, 199, 69, 11, 148, 254, 140, 119, 61, 28, 58, 131, 83, 32, 14, 171, 33, 173, 242, 36, 122, 71, 210, 182, 28, 141, 145, 66, 148, 64, 86, 232, 73, 25, 31, 130, 115, 13, 234, 231, 152, 183, 217, 138, 153, 112, 120, 205]);
  assert(digest256.sum() == h256);
  assert(digest512.sum() == h512);
};