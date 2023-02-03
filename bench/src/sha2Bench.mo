import E "mo:base/ExperimentalInternetComputer";
import Engine32 "../../src/sha2/engine32";
import Engine64 "../../src/sha2/engine64";
import Array "mo:base/Array";
import Nat8 "mo:base/Nat8";

actor {
    let e32 = Engine32.Engine();
    let e64 = Engine64.Engine();
    e32.init(1);
    e64.init(1);
    let block64 = Array.tabulate<Nat8>(64,func(i) {Nat8.fromNat(0xff-i)});
    let block128 = Array.tabulate<Nat8>(128,func(i) {Nat8.fromNat(0xff-i)});

    func bench32() {
        e32.process_block(block64);
    };
    func bench64() {
        e64.process_block(block128);
    };

    public query func profile32() : async Nat64 = async E.countInstructions(bench32);
    public query func profile64() : async Nat64 = async E.countInstructions(bench64);

};