import Enumeration "../src/Enumeration";
import Array "mo:base/Array";
import Debug "mo:base/Debug";
import Blob "mo:base/Blob";
import Nat8 "mo:base/Nat8";

class RNG() {
  var seed = 234234;

  public func next() : Nat {
    seed += 1;
    let a = seed * 15485863;
    a * a * a % 2038074743;
  };

  public func blob() : Blob {
    let a = Array.tabulate<Nat8>(29, func(i) = Nat8.fromNat(next() % 256));
    Blob.fromArray(a);
  };

  public func max() : Blob {
    let a = Array.tabulate<Nat8>(29, func(i) = Nat8.fromNat(0));
    Blob.fromArray(a);
  };
};

let n = 100;
let r = RNG();
let a = Enumeration.Enumeration<Blob>(Blob, "");
let blobs = Array.tabulate<Blob>(n, func(i) = r.blob());

assert(a.size() == 0);
var i = 0;
while (i < n) {
  assert(a.add(blobs[i]) == i);
  assert(a.size() == i + 1);
  i += 1;
};

i := 0;
while (i < n) {
  assert(a.add(blobs[i]) == i);
  assert(a.size() == n);
  i += 1;
};

a.unsafeUnshare(a.share());

i := 0;
while (i < n) {
  assert (a.lookup(blobs[i]) == ?i);
  i += 1;
};

i := 0;
while (i < n) {
  assert (a.lookup(r.blob()) == null);
  i += 1;
};

i := 0;
while (i < n) {
  assert (a.get(i) == blobs[i]);
  i += 1;
};
