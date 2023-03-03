/// Implementation of the 128-bit Seiran PRNG
/// See: https://github.com/andanteyk/prng-seiran
///
/// WARNING: This is not a cryptographically secure pseudorandom
/// number generator.

import Array "mo:base/Array";
import Nat64 "mo:base/Nat64";
import Iter "mo:base/Iter";

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

            // Constrain to 2?
            for (jp in jumppoly.vals()) {
                for (b in Iter.range(0, 63)) {
                    if ((jp >> Nat64.fromNat(b)) & 1 == 1) {
                        t0 ^= state0;
                        t1 ^= state1;
                    };
                    let t = next();
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
};
