import StableTrie "../src/StableTrie";
import Prng "mo:prng";
import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Nat8 "mo:base/Nat8";
import Nat64 "mo:base/Nat64";
import Iter "mo:base/Iter";
import Buffer "mo:base/Buffer";
import Nat "mo:base/Nat";
import Float "mo:base/Float";
import Debug "mo:base/Debug";
import Text "mo:base/Text";
import Option "mo:base/Option";
import Bench "mo:bench";

module {
  public func init() : Bench.Bench {
    let bench = Bench.Bench();

    let n = 18;
    let cols = 4;
    let key_size = 8;
    bench.cols(["2", "4", "16", "256"]);
    bench.rows(Array.tabulate<Text>(n, func(i) = Nat.toText(i)));

    var trie = Array.tabulate<StableTrie.StableTrie>(cols, func(i) = StableTrie.StableTrie(2 ** (2 ** i), key_size, 0));

    let rng = Prng.Seiran128();
    rng.init(0);
    let keys = Array.tabulate<Blob>(
      2 ** n,
      func(i) {
        Blob.fromArray(Array.tabulate<Nat8>(key_size, func(j) = Nat8.fromNat(Nat64.toNat(rng.next()) % 256)));
      },
    );

    var k = 0;
    bench.runner(
      func(row, col) {
        let r = Option.unwrap(Nat.fromText(row));

        let tr = trie[k];

        if (r == 0) {
          ignore tr.add(keys[0], "");
        } else {
          for (j in Iter.range(2 ** (r - 1), 2 ** r - 1)) {
            assert tr.add(keys[j], "");
          };
        };
        k += 1;
        if (k == cols) {
          k := 0;
        };
      }
    );

    bench;
  };
};
