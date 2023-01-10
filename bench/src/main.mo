import Vector "../../src/vector";
import E "mo:base/ExperimentalInternetComputer";
import Iter "mo:base/Iter";
import Buffer "mo:base/Buffer";

actor {
    let n = 1_000_000;

    func vector_bench() {
        let a = Vector.new<Nat>();
        var i = 0;
        while (i < n) {
            Vector.add(a, i);
            i += 1;
        };
        i := 0;
        while (i < n) {
            assert(Vector.get(a, i) == i);
            i += 1;
        };
    };

    func buffer_bench() {
        let a = Buffer.Buffer<Nat>(0);
        var i = 0;
        while (i < n) {
            a.add(i);
            i += 1;
        };
        i := 0;
        while (i < n) {
            assert(a.get(i) == i);
            i += 1;
        };
    };

    public query func profile_vector() : async Nat64 = async E.countInstructions(vector_bench);

    public query func profile_buffer() : async Nat64 = async E.countInstructions(buffer_bench);
};
