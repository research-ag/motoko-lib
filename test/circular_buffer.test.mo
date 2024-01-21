// @testmode wasi
import CircularBuffer "../src/CircularBuffer";
import Iter "mo:base/Iter";
import Debug "mo:base/Debug";
import Text "mo:base/Text";
import Option "mo:base/Option";

do {
  let c = CircularBuffer.CircularBuffer<Nat>(5);

  c.push(0);
  c.push(1);
  c.push(2);

  assert Iter.toArray(c.slice(0, 3)) == [0, 1, 2];
  assert Iter.toArray(c.slice(1, 3)) == [1, 2];
  assert Iter.toArray(c.slice(2, 3)) == [2];
  assert Iter.toArray(c.slice(0, 1)) == [0];

  c.push(3);
  c.push(4);
  c.push(5);
  c.push(6);
  c.push(7);
  c.push(8);

  let (a, b) = c.available();
  assert Iter.toArray(c.slice(a, b)) == [4, 5, 6, 7, 8];
  assert Iter.toArray(c.slice(a + 1, b - 1)) == [5, 6, 7];
};

do {

  func test_pop(len : Nat, cap : Nat) {
    let c = CircularBuffer.CircularBufferStable<Text>(
      func(x : Text) : Blob = Text.encodeUtf8(x),
      func(x : Blob) : Text = Option.unwrap(Text.decodeUtf8(x)),
      cap,
      len,
    );
    let n = len;
    var i = 0;
    var t = "";
    label w while (i * (i + 1) / 2 < n and i + 1 < n) {
      t #= "a";
      if (Text.encodeUtf8(t).size() > len) break w;
      assert c.push(t);
      let s = c.pop();
      assert s == ?t;
    };
  };

  func test(len : Nat, cap : Nat) {
    let c = CircularBuffer.CircularBufferStable<Text>(
      func(x : Text) : Blob = Text.encodeUtf8(x),
      func(x : Blob) : Text = Option.unwrap(Text.decodeUtf8(x)),
      cap,
      len,
    );

    let n = len;
    var t = "";
    for (i in Iter.range(0, n - 1)) {
      t #= "a";
      c.push_force(t);
    };
    t := "";
    for (i in Iter.range(0, n - 1)) {
      t #= "a";
      switch (c.get(i)) {
        case (?s) {
          assert s == t;
        };
        case (null) {};
      };
    };

    // test slice
    let (l, r) = c.available();
    var i = l;
    for (item in c.slice(l, r)) {
      assert item.size() == i + 1;
      i += 1;
    };

    // test share/unshare
    let data = c.share();
    let nc = CircularBuffer.CircularBufferStable<Text>(
      func(x : Text) : Blob = Text.encodeUtf8(x),
      func(x : Blob) : Text = Option.unwrap(Text.decodeUtf8(x)),
      cap,
      len,
    );
    nc.unshare(data);
  };

  for (i in Iter.range(0, 10)) {
    for (j in Iter.range(0, 10)) {
      test(2 ** i, 2 ** j);
      test_pop(2 ** i, 2 ** j);
    };
  };

  test(2 ** 12 / 4, 2 ** 12);
};
