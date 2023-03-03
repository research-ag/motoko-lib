/// Implementation of the 128-bit Seiran PRNG
/// See: https://github.com/andanteyk/prng-seiran
///
/// WARNING: This is not a cryptographically secure pseudorandom
/// number generator.

import Array "mo:base/Array";
import Nat64 "mo:base/Nat64";
import Iter "mo:base/Iter";

module {
    public class PRNG() {
        private let state: [var Nat64] = Array.init<Nat64>(2, 0);

        public func init(seed: Nat64) {
            var s = seed;
            for (i in Iter.range(0,1)) {
                s := Nat64.addWrap(Nat64.mulWrap(s, 6364136223846793005), 1442695040888963407);
                state[i] := s;
            };
        };

        public func next() : Nat64 {
            let s0 = state[0];
            let s1 = state[1];

            let result = Nat64.addWrap(Nat64.bitrotLeft(Nat64.mulWrap(Nat64.addWrap(s0, s1), 9), 29), s0);

            state[0] := s0 ^ Nat64.bitrotLeft(s1, 29);
            state[1] := s0 ^ (s1 << 9);

            return result;
        };

        private func jump(jumppoly: [Nat64]) {
            var t0: Nat64 = 0;
            var t1: Nat64 = 0;

            // Constrain to 2?
            for (jp in jumppoly.vals()) {
                for (b in Iter.range(0, 63)) {
                    if ((jp >> Nat64.fromNat(b)) & 1 == 1) {
                        t0 ^= state[0];
                        t1 ^= state[1];
                    };
                    let t = next();
                };
            };

            state[0] := t0;
            state[1] := t1;
        };

        public func jump32() {
            jump([0x40165CBAE9CA6DEB, 0x688E6BFC19485AB1]);
        };

        public func jump64() {
            jump([0xF4DF34E424CA5C56, 0x2FE2DE5C2E12F601]);
        };

        public func jump96() {
            jump([0x185F4DF8B7634607, 0x95A98C7025F908B2]);
        };
    };
};
