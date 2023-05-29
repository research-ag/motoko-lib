import Enumeration "../src/Enumeration";
import Array "mo:base/Array";
import Debug "mo:base/Debug";
import Blob "mo:base/Blob";
import Principal "mo:base/Principal";
import Text "mo:base/Text";
import Nat8 "mo:base/Nat8";
import Option "mo:base/Option";

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

  public func maxBlob() : Blob {
    let a = Array.tabulate<Nat8>(29, func(i) = Nat8.fromNat(0));
    Blob.fromArray(a);
  };

  public func principal() : Principal = Principal.fromBlob(blob());
  public func maxPrincipal() : Principal = Principal.fromBlob(maxBlob());
  public func text() : Text = Principal.toText(Principal.fromBlob(blob()));
  public func maxText() : Text = Principal.toText(Principal.fromBlob(maxBlob()));
};

let n = 100;
let r = RNG();
let b = Enumeration.Enumeration<Blob>(Blob.compare, "");
let p = Enumeration.Enumeration(Principal.compare, Principal.fromBlob "");
let t = Enumeration.Enumeration(Text.compare, "");
let blobs = Array.tabulate<Blob>(n, func(i) = r.blob());
let principalities = Array.tabulate<Principal>(n, func(i) = r.principal());
let texts = Array.tabulate<Text>(n, func(i) = r.text());

/** blob **/

assert(b.size() == 0);
var i = 0;
while (i < n) {
  assert(b.add(blobs[i]) == i);
  assert(b.size() == i + 1);
  i += 1;
};

i := 0;
while (i < n) {
  assert(b.add(blobs[i]) == i);
  assert(b.size() == n);
  i += 1;
};

b.unsafeUnshare(b.share());

i := 0;
while (i < n) {
  assert (b.lookup(blobs[i]) == ?i);
  i += 1;
};

i := 0;
while (i < n) {
  assert (b.lookup(r.blob()) == null);
  i += 1;
};

i := 0;
while (i < n) {
  assert (b.get(i) == blobs[i]);
  i += 1;
};

/** principal **/


assert(p.size() == 0);
i := 0;
while (i < n) {
  assert(p.add(principalities[i]) == i);
  assert(p.size() == i + 1);
  i += 1;
};

i := 0;
while (i < n) {
  assert(p.add(principalities[i]) == i);
  assert(p.size() == n);
  i += 1;
};

p.unsafeUnshare(p.share());

i := 0;
while (i < n) {
  assert (p.lookup(principalities[i]) == ?i);
  i += 1;
};

i := 0;
while (i < n) {
  assert (p.lookup(r.principal()) == null);
  i += 1;
};

i := 0;
while (i < n) {
  assert (p.get(i) == principalities[i]);
  i += 1;
};

/** text **/

assert(t.size() == 0);
i := 0;
while (i < n) {
  assert(t.add(texts[i]) == i);
  assert(t.size() == i + 1);
  i += 1;
};

i := 0;
while (i < n) {
  assert(t.add(texts[i]) == i);
  assert(t.size() == n);
  i += 1;
};

t.unsafeUnshare(t.share());

i := 0;
while (i < n) {
  assert (t.lookup(texts[i]) == ?i);
  i += 1;
};

i := 0;
while (i < n) {
  assert (t.lookup(r.text()) == null);
  i += 1;
};

i := 0;
while (i < n) {
  assert (t.get(i) == texts[i]);
  i += 1;
};
