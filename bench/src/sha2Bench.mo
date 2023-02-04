import E "mo:base/ExperimentalInternetComputer";
import Engine32 "../../src/sha2/engine32";
import Engine64 "../../src/sha2/engine64";
import Sha2 "../../src/Sha2";
import Array "mo:base/Array";
import Nat8 "mo:base/Nat8";
import Blob "mo:base/Blob";
import Buffer "mo:base/Buffer";
import BigEndian "../../src/sha2/bigendian";

actor {
    let e32 = Engine32.Engine();
    let e64 = Engine64.Engine();
    e32.init(1);
    e64.init(1);
    let block64 = Array.tabulate<Nat8>(64,func(i) {Nat8.fromNat(0xff-i)});
    let block128 = Array.tabulate<Nat8>(128,func(i) {Nat8.fromNat(0xff-i)});
    let block0 = Blob.fromArray([] : [Nat8]);
    let block48 = Blob.fromArray(Array.tabulate<Nat8>(48,func(i){1}));
    let d32 = Sha2.Digest(#sha256);

    public query func profile32() : async (Nat64, Nat64, Nat64, Nat64) {
        let a = E.countInstructions(func(){e32.process_block(block64)});
        let b = E.countInstructions(func(){ignore e32.state()});
        let c = E.countInstructions(func(){ignore Sha2.fromBlob(#sha256, block0)});
        let sha256 = Sha2.Digest(#sha256);
        let d = E.countInstructions(func(){ignore sha256.sum()});
        (a, b, c, d)
        // process_block, state, fromBlob, sum
    };

    public query func profile64() : async Nat64 {
        E.countInstructions(func(){e64.process_block(block128)});
    };

    public query func profile_state() : async (Nat64, Nat64, Nat64, Nat64) {
      let a = E.countInstructions(func(){
        let buf = Buffer.Buffer<Nat8>(32);
      });
      let buf = Buffer.Buffer<Nat8>(32);
      let b = E.countInstructions(func(){
        let w = BigEndian.fromNat32(0x7f7f7f7f : Nat32);
      });      
      let c = E.countInstructions(func(){
        buf.add(0x7f : Nat8);
      });
      let d = E.countInstructions(func(){
        ignore Buffer.toArray(buf);
      });
      (a, b, c, d)
    };
    // a + 8 * b + 32 * c + d
    // 1.9 + 400 + 6.4 + 0.3
};