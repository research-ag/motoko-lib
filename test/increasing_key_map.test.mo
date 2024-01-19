// @testmode wasi
import IncreasingKeyMap "../src/IncreasingKeyMap";
import Iter "mo:base/Iter";
import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";

let map = IncreasingKeyMap.IncreasingKeyMap();

let n = 2 ** 17;

func test() {
  for (i in Iter.range(0, n - 1)) {
    map.add(Nat32.fromNat(2 * i), Nat64.fromNat(i));
  };

  for (i in Iter.range(0, n - 1)) {
    assert map.find(Nat32.fromNat(2 * i)) == ?Nat64.fromNat(i);
    assert map.find(Nat32.fromNat(2 * i + 1)) == null;
  };
};

test();

map.reset();

test();
