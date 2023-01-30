import Vector "../../src/vector";
import E "mo:base/ExperimentalInternetComputer";
import Buffer "mo:base/Buffer";
import Array "mo:base/Array";
import Option "mo:base/Option";
import Debug "mo:base/Debug";
import Nat64 "mo:base/Nat64";

actor {
  let sqrt = 1000;
  let n = 1_000_000;

  func print(f : () -> ()) {
    Debug.print(Nat64.toText(E.countInstructions(f)));
  };

  func vector_bench() {
    let a = Vector.new<Nat>();
    var i = 0;
    while (i < n) {
      Vector.add(a, i);
      i += 1;
    };
    i := 0;
    while (i < n) {
      assert (Vector.get(a, i) == i);
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
      assert (a.get(i) == i);
      i += 1;
    };
  };

  func array_bench() {
    let a = Array.init<?[var ?Nat]>(sqrt, null);
    var i = 0;
    var x = 0;
    while (i < sqrt) {
      a[i] := ?Array.init<?Nat>(sqrt, null);
      var j = 0;
      while (j < sqrt) {
        Option.unwrap(a[i])[j] := ?x;
        x += 1;
        j += 1;
      };
      i += 1;
    };

    x := 0;
    while (x < sqrt * sqrt) {
      let i = x / sqrt;
      let j = x % sqrt;
      assert (Option.unwrap(Option.unwrap(a[i])[j]) == x);
      x += 1;
    };
  };

  public query func profile_vector() : async Nat64 = async E.countInstructions(vector_bench);

  public query func profile_buffer() : async Nat64 = async E.countInstructions(buffer_bench);

  public query func profile_array() : async Nat64 = async E.countInstructions(array_bench);
};
