/// Implementation of the 128-bit Seiran PRNG
/// See: https://github.com/andanteyk/prng-seiran
///
/// WARNING: This is not a cryptographically secure pseudorandom
/// number generator.

import { range } "mo:base/Iter";

module {
    public class Seiran128() {

        private var state0: Nat64 = 0;
        private var state1: Nat64 = 0;

        // Initialize the PRNG with a particular seed
        public func init(seed: Nat64) {
            state0 := seed *% 6364136223846793005 +% 1442695040888963407;
            state1 := state0 *% 6364136223846793005 +% 1442695040888963407;
        };

        // Return the PRNG result and advance the state
        public func next() : Nat64 {
            let (s0, s1) = (state0, state1);

            let result = (((s0 +% s1) *% 9) <<> 29) +% s0;

            state0 := s0 ^ (s1 <<> 29);
            state1 := s0 ^ (s1 << 9);

            return result;
        };

        // Given a bit polynomial, advance the state (see below functions)
        private func jump(jumppoly: [Nat64]) {
            var t0: Nat64 = 0;
            var t1: Nat64 = 0;

            for (jp in jumppoly.vals()) {
                var w = jp;
                for (b in range(0, 63)) {
                    if (w & 1 == 1) {
                        t0 ^= state0;
                        t1 ^= state1;
                    };

                    w >>= 1;
                    ignore next();
                };
            };

            state0 := t0;
            state1 := t1;
        };

        // Advance the state 2^32 times
        public func jump32() {
            jump([0x40165CBAE9CA6DEB, 0x688E6BFC19485AB1]);
        };

        // Advance the state 2^64 times
        public func jump64() {
            jump([0xF4DF34E424CA5C56, 0x2FE2DE5C2E12F601]);
        };

        // Advance the state 2^96 times
        public func jump96() {
            jump([0x185F4DF8B7634607, 0x95A98C7025F908B2]);
        };
    };

    public class SFC64(
      p: Nat64,
      q: Nat64,
      r: Nat64,
    ) {
        private var state0: Nat64 = 0;
        private var state1: Nat64 = 0;
        private var state2: Nat64 = 0;
        private var state3: Nat64 = 0;

        public func init3(seed1: Nat64, seed2: Nat64, seed3: Nat64) {
            state0 := seed3;
            state1 := seed2;
            state2 := seed1;
            state3 := 1;

            // why 11 you ask?...
            for (i in range(0, 11)) {
                ignore next();
            };
        };

        // Initialize the PRNG with a particular seed
        public func init1(seed: Nat64) {
            init3(seed, seed, seed);
        };

        public func init() {
            let s :Nat64 = 0xcafef00dbeef5eed;
            init1(s);
        };

        public func next() : Nat64 {
            let tmp = state0 +% state1 +% state3;
            state3 +%= 1;
            state0 := state1 ^ (state1 >> q);
            state1 := state2 +% (state2 << r);
            state2 := (state2 <<> p) +% tmp;
            return tmp;
        };
    };

    public class SFC32(
      p: Nat32,
      q: Nat32,
      r: Nat32,
    ) {
        private var state0: Nat32 = 0;
        private var state1: Nat32 = 0;
        private var state2: Nat32 = 0;
        private var state3: Nat32 = 0;

        public func init3(seed1: Nat32, seed2: Nat32, seed3: Nat32) {
            state0 := seed3;
            state1 := seed2;
            state2 := seed1;
            state3 := 1;

            // why 11 you ask?...
            for (i in range(0, 11)) {
                ignore next();
            };
        };

        // Initialize the PRNG with a particular seed
        public func init1(seed: Nat32) {
            init3(seed, seed, seed);
        };

        public func init() {
            let s :Nat32 = 0xbeef5eed;
            init1(s);
        };

        public func next() : Nat32 {
            let tmp = state0 +% state1 +% state3;
            state3 +%= 1;
            state0 := state1 ^ (state1 >> q);
            state1 := state2 +% (state2 << r);
            state2 := (state2 <<> p) +% tmp;
            return tmp;
        };
    };

    // --- Use these ---
    // SFC64a is same as numpy:
    // https://github.com/numpy/numpy/blob/b6d372c25fab5033b828dd9de551eb0b7fa55800/numpy/random/src/sfc64/sfc64.h#L28
    public func SFC64a() : SFC64 { SFC64(24,11,3) };

    public func SFC32a() : SFC32 { SFC32(21,9,3) };
    public func SFC32b() : SFC32 { SFC32(15,8,3) };

    // --- Not recommended ---
    public func SFC64b() : SFC64 { SFC64(25,12,3) };

    public func SFC32c() : SFC32 { SFC32(25,8,3) };

};