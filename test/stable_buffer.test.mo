// @testmode wasi

import Iter "mo:base/Iter";
import Text "mo:base/Text";
import Option "mo:base/Option";
import StableBuffer "../src/StableBuffer";

let buffer = StableBuffer.StableBuffer<Text>(
  func(x : Text) : Blob = Text.encodeUtf8(x),
  func(x : Blob) : Text = Option.unwrap(Text.decodeUtf8(x)),
);

var n = 0;
var t = "";
buffer.setMaxPages(?3);
while (buffer.add(t)) {
  t #= "a";
  n += 1;
};

assert buffer.pages() == 3;

t := "";
for (i in Iter.range(0, n - 1)) {
  assert buffer.get(i) == t;
  t #= "a";
};
