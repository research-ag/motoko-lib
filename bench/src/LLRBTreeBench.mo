import LLRBTree "../../src/LLRBTree";
import E "mo:base/ExperimentalInternetComputer";
import Debug "mo:base/Debug";
import Nat64 "mo:base/Nat64";
import Nat "mo:base/Nat";
import RBTree "mo:base/RBTree";

actor {
  let n = 100_000;

  func print(f : () -> ()) {
    Debug.print(Nat64.toText(E.countInstructions(f)));
  };

  func llrb_bench() {
    var t = LLRBTree.new<Nat, Nat>(Nat.compare);
    var i = 0;
    while (i < n) {
      LLRBTree.insert(t, i, i);
      i += 1;
    };
  };

  func rb_bench() {
    var t = RBTree.RBTree<Nat, Nat>(Nat.compare);
    var i = 0;
    while (i < n) {
      t.put(i, i);
      i += 1;
    };
  };

  public query func profile_llrb() : async Nat64 = async E.countInstructions(llrb_bench);

  public query func profile_rb() : async Nat64 = async E.countInstructions(rb_bench);
};
