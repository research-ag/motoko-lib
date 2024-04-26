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
    let key_size = 8;
    bench.rows(["2", "4", "16", "256"]);
    bench.cols(Array.tabulate<Text>(n, func(i) = Nat.toText(i)));

    var k = 2;
    var trie = StableTrie.StableTrie(k, key_size, 0);

    let rng = Prng.Seiran128();
    rng.init(0);
    let keys = Array.tabulate<Blob>(
      2 ** n,
      func(i) {
        Blob.fromArray(Array.tabulate<Nat8>(key_size, func(j) = Nat8.fromNat(Nat64.toNat(rng.next()) % 256)));
      },
    );

    bench.runner(
      func(row, col) {
        let r = Option.unwrap(Nat.fromText(row));
        let c = Option.unwrap(Nat.fromText(col));
        if (r != k) {
          k := r;
          trie := StableTrie.StableTrie(k, key_size, 0);
        };

        if (c == 0) {
          ignore trie.add(keys[0], "");
        } else {
          for (j in Iter.range(2 ** (c - 1), 2 ** c - 1)) {
            assert trie.add(keys[j], "");
          };
        };
      }
    );

    bench;
  };
};
