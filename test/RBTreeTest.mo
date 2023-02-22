import RbTree "mo:base/RBTree";
import LLRBTree "../src/LLRBTree";
import Random "mo:base/Random";
import Nat "mo:base/Nat";
import Debug "mo:base/Debug";

class RNG() {
    var seed = 0;

    public func next() : Nat {
        seed += 1;
        let a = seed * 15485863;
        a * a * a % 2038074743;
    };
};
let t = LLRBTree.new<Nat, Nat>(Nat.compare);

var r = RNG();
var i = 0;
while (i < 1000) {
    LLRBTree.insert(t, r.next(), i);
    assert(LLRBTree.valid(t));
    i += 1;
};

r := RNG();
i := 0;
while (i < 1000) {
    assert(LLRBTree.get(t, r.next()) == ?i);
    i += 1;
};

r := RNG();
i := 0;
while (i < 1000) {
    LLRBTree.delete(t, r.next());
    assert(LLRBTree.valid(t));
    i += 1;
};
