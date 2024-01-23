// @testmode wasi

import Iter "mo:base/Iter";
import Text "mo:base/Text";
import Option "mo:base/Option";
import StableBuffer "../src/StableBuffer";

let buffer = StableBuffer.StableBuffer<Text>(
  func(x : Text) : Blob = Text.encodeUtf8(x),
  func(x : Blob) : Text = Option.unwrap(Text.decodeUtf8(x)),
);

let n = 100;
var t = "";
for (i in Iter.range(0, n - 1)) {
  buffer.add(t);
  t #= "a";
};

t := "";
for (i in Iter.range(0, n - 1)) {
  assert buffer.get(i) == t;
  t #= "a";
};
