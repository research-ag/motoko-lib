import E "mo:base/ExperimentalInternetComputer";
import Sha256 "../../src/Sha256";
import Sha512 "../../src/Sha512";
import Array "mo:base/Array";
import Buffer "mo:base/Buffer";
import Nat8 "mo:base/Nat8";
import Blob "mo:base/Blob";

actor {
  let block48 = Array.tabulate<Nat8>(48, func(i) { Nat8.fromNat(0xff -i) });
  let block55 = Array.tabulate<Nat8>(55, func(i) { Nat8.fromNat(0xff -i) });
  let block64 = Array.tabulate<Nat8>(64, func(i) { Nat8.fromNat(0xff -i) });
  let block128 = Array.tabulate<Nat8>(128, func(i) { Nat8.fromNat(0xff -i) });
  let blob0 = Blob.fromArray([] : [Nat8]);
  let blob48 = Blob.fromArray(block48);
  let blob55 = Blob.fromArray(block55);
  let blob64 = Blob.fromArray(block64);
  let blob128 = Blob.fromArray(block128);

  public query func profile32() : async [Nat64] {
    var res = Buffer.Buffer<Nat64>(10);
    for (i in [0, 1, 2, 5, 10, 100, 1000].vals()) {
      let len = if (i == 0) 0 else 64*i-9;
      let arr = Array.freeze(Array.init<Nat8>(len, 0));
      let b = Blob.fromArray(arr);
      let x = E.countInstructions(func() { ignore Sha256.fromBlob(#sha256, b) });
      res.add(x);
    };
    Buffer.toArray(res);
  };

  public query func profile64() : async [Nat64] {
    var res = Buffer.Buffer<Nat64>(10);
    for (i in [0, 1, 2, 5, 10, 100, 1000].vals()) {
      let len = if (i == 0) 0 else 128*i-17;
      let arr = Array.freeze(Array.init<Nat8>(len, 0));
      let b = Blob.fromArray(arr);
      let x = E.countInstructions(func() { ignore Sha512.fromBlob(#sha512, b) });
      res.add(x);
    };
    Buffer.toArray(res);
  };
};