import Vector "../../src/vector";
import E "mo:base/ExperimentalInternetComputer";
import Iter "mo:base/Iter";
import Buffer "mo:base/Buffer";

actor {
    let n = 1_000_000;

    func vector_bench() {
        let a = Vector.new<Nat>();
        for (i in Iter.range(0, n - 1)) {
            Vector.add(a, i);
        };
        for (i in Iter.range(0, n - 1)) {
            assert(Vector.get(a, i) == i);
        };
    };

    func buffer_bench() {
        let a = Buffer.Buffer<Nat>(0);
        for (i in Iter.range(0, n - 1)) {
            a.add(i);
        };
        for (i in Iter.range(0, n - 1)) {
            assert(a.get(i) == i);
        };
    };

    public query func profile_vector() : async Nat64 = async E.countInstructions(vector_bench);

    public query func profile_buffer() : async Nat64 = async E.countInstructions(buffer_bench);
};
