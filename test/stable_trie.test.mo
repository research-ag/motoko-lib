// @testmode wasi

import Prng "mo:prng";
import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Nat8 "mo:base/Nat8";
import Nat64 "mo:base/Nat64";
import Debug "mo:base/Debug";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Result "mo:base/Result";
import Nat16 "mo:base/Nat16";
import StableTrie "../src/StableTrie";

func keyToIndices(aridity : Nat, root_aridity : Nat, key : Blob, depth : Nat16) : () -> Nat64 {
  let bytes = Blob.toArray(key);
  var first = true;
  var x : Nat64 = 0;
  for (i in Iter.range(0, key.size() - 1 : Int)) {
    x += Nat64.fromNat(Nat8.toNat(bytes[i])) << Nat64.fromNat(i * 8);
  };

  let aridity_ = Nat64.fromNat(aridity);
  let root_aridity_ = Nat64.fromNat(root_aridity);

  func() : Nat64 {
    let a = if (first and depth == 0) root_aridity_ else aridity_;
    if (first and depth != 0) x /= aridity_ ** Nat64.fromNat(Nat16.toNat(depth));
    first := false;

    let ret = x & (a - 1);
    x /= a;
    ret;
  };
};

func testKeyToIndices() {
  let bits = [2, 4, 16, 256];
  let key_size = 8;
  let rnd_key = Blob.fromArray(Array.tabulate<Nat8>(key_size, func(j) = Nat8.fromNat(Nat64.toNat(rng.next()) % 256)));

  for (bit in bits.vals()) {
    let length = key_size * 8 / Nat64.toNat(Nat64.bitcountTrailingZero(Nat64.fromNat(bit)));
    for (key in Iter.range(0, length - 1)) {
      let trie = StableTrie.StableTrie(2, bit, bit ** key, key_size, 0);
      let next = trie.keyToIndices(rnd_key, 0);
      let test_next = keyToIndices(bit, bit ** key, rnd_key, 0);
      let cnt = length - key : Nat + 1;
      for (i in Iter.range(0, cnt - 1)) {
        assert next() == test_next();
      };
    };
  };
};

let n = 2 ** 11;
let key_size = 5;

let rng = Prng.Seiran128();
rng.init(0);

func gen() : [Blob] {
  Array.tabulate<Blob>(
    n,
    func(i) {
      Blob.fromArray(Array.tabulate<Nat8>(key_size, func(j) = Nat8.fromNat(Nat64.toNat(rng.next()) % 256)));
    },
  );
};

let keys = gen();

let keysAbsent = gen();

// Note: bits = 256 and pointers = 2 requires smaller n
let bits = [2, 4, 16];
let pointers = [2, 4, 6, 8];
for (bit in bits.vals()) {
  for (pointer in pointers.vals()) {
    let trie = StableTrie.StableTrie(pointer, bit, bit * bit * bit, key_size, 0);

    var i = 0;
    for (key in keys.vals()) {
      assert trie.add(key, "") == #ok(i);
      i += 1;
    };

    // trie.print();
    i := 0;
    for (key in keys.vals()) {
      assert (trie.get(key) == ?("", i));
      i += 1;
    };

    for (key in keysAbsent.vals()) {
      assert trie.get(key) == null;
    };
  };
};

func profile() {
  let children_number = [2, 4, 16, 256];

  let key_size = 8;
  let n = 20;
  let rng = Prng.Seiran128();
  rng.init(0);
  let keys = Array.tabulate<Blob>(
    2 ** n,
    func(i) {
      Blob.fromArray(Array.tabulate<Nat8>(key_size, func(j) = Nat8.fromNat(Nat64.toNat(rng.next()) % 256)));
    },
  );
  let rows = Iter.map<Nat, (Text, Iter.Iter<Text>)>(
    children_number.vals(),
    func(k) {
      let first = Nat.toText(k);
      let trie = StableTrie.StableTrie(8, k, k, key_size, 0);
      let second = Iter.map<Nat, Text>(
        Iter.range(0, n),
        func(i) {
          if (i == 0) {
            ignore trie.add(keys[0], "");
          } else {
            for (j in Iter.range(2 ** (i - 1), 2 ** i - 1)) {
              assert Result.isOk(trie.add(keys[j], ""));
            };
          };
          "";
          // Nat.toText(trie.size() / 2 ** i);
        },
      );
      (first, second);
    },
  );
};

// profile();
