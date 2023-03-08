/// Implementation of the 128-bit Seiran PRNG
/// See: https://github.com/andanteyk/prng-seiran
///
/// WARNING: This is not a cryptographically secure pseudorandom
/// number generator.

import { range } "mo:base/Iter";

module {
  public class Seiran128() {

    // state
    var a : Nat64 = 0;
    var b : Nat64 = 0;

    // Initialize the PRNG with a particular seed
    public func init(seed : Nat64) {
      a := seed *% 6364136223846793005 +% 1442695040888963407;
      b := a *% 6364136223846793005 +% 1442695040888963407;
    };

    // Return the PRNG result and advance the state
    public func next() : Nat64 {
      let (s0, s1) = (a, b);

      let result = (((s0 +% s1) *% 9) <<> 29) +% s0;

      a := s0 ^ (s1 <<> 29);
      b := s0 ^ (s1 << 9);

      result;
    };

    // Given a bit polynomial, advance the state (see below functions)
    func jump(jumppoly : [Nat64]) {
      var t0 : Nat64 = 0;
      var t1 : Nat64 = 0;

      for (jp in jumppoly.vals()) {
        var w = jp;
        for (_ in range(0, 63)) {
          if (w & 1 == 1) {
            t0 ^= a;
            t1 ^= b;
          };

          w >>= 1;
          ignore next();
        };
      };

      a := t0;
      b := t1;
    };

    // Advance the state 2^32 times
    public func jump32() = jump([0x40165CBAE9CA6DEB, 0x688E6BFC19485AB1]);

    // Advance the state 2^64 times
    public func jump64() = jump([0xF4DF34E424CA5C56, 0x2FE2DE5C2E12F601]);

    // Advance the state 2^96 times
    public func jump96() = jump([0x185F4DF8B7634607, 0x95A98C7025F908B2]);
  };

  public class SFC64(p : Nat64, q : Nat64, r : Nat64) {
    // state
    var a : Nat64 = 0;
    var b : Nat64 = 0;
    var c : Nat64 = 0;
    var d : Nat64 = 0;

    public func init3(seed1 : Nat64, seed2 : Nat64, seed3 : Nat64) {
      a := seed1;
      b := seed2;
      c := seed3;
      d := 1;

      // why 11 you ask?...
      for (_ in range(0, 11)) ignore next();
    };

    // Initialize the PRNG with a particular seed
    public func init1(seed : Nat64) = init3(seed, seed, seed);

    public func init() = init1(0xcafef00dbeef5eed);

    public func next() : Nat64 {
      let tmp = a +% b +% d;
      d +%= 1;
      a := b ^ (b >> q);
      b := c +% (c << r);
      c := (c <<> p) +% tmp;
      tmp;
    };
  };

  public class SFC32(p : Nat32, q : Nat32, r : Nat32) {
    var a : Nat32 = 0;
    var b : Nat32 = 0;
    var c : Nat32 = 0;
    var d : Nat32 = 0;

    public func init3(seed1 : Nat32, seed2 : Nat32, seed3 : Nat32) {
      a := seed1;
      b := seed2;
      c := seed3;
      d := 1;

      // why 11 you ask?...
      for (_ in range(0, 11)) ignore next();
    };

    // Initialize the PRNG with a particular seed
    public func init1(seed : Nat32) = init3(seed, seed, seed);

    public func init() = init1(0xbeef5eed);

    public func next() : Nat32 {
      let tmp = a +% b +% d;
      d +%= 1;
      a := b ^ (b >> q);
      b := c +% (c << r);
      c := (c <<> p) +% tmp;
      tmp;
    };
  };

  // --- Use these ---
  // SFC64a is same as numpy:
  // https://github.com/numpy/numpy/blob/b6d372c25fab5033b828dd9de551eb0b7fa55800/numpy/random/src/sfc64/sfc64.h#L28
  public func SFC64a() : SFC64 { SFC64(24, 11, 3) };

  public func SFC32a() : SFC32 { SFC32(21, 9, 3) };
  public func SFC32b() : SFC32 { SFC32(15, 8, 3) };

  // --- Not recommended ---
  public func SFC64b() : SFC64 { SFC64(25, 12, 3) };

  public func SFC32c() : SFC32 { SFC32(25, 8, 3) };

};
