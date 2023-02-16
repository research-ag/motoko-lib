import RbTree "mo:base/RBTree";
import LLRBTree "../src/LLRBTree";
import Random "mo:base/Random";
import Nat "mo:base/Nat";
import Debug "mo:base/Debug";

let t = LLRBTree.new<Nat, Nat>(Nat.compare);

var i = 0;
while (i < 1000) {
    LLRBTree.insert(t, i, i);
    i += 1;
};

i := 0;
while (i < 1000) {
    LLRBTree.delete(t, i);
    i += 1;
    // Debug.print(Nat.toText(i));
};
