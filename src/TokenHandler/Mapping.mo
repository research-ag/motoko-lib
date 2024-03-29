import Blob "mo:base/Blob";
import Nat8 "mo:base/Nat8";
import Principal "mo:base/Principal";
import Array "mo:base/Array";

import ICRC1 "./ICRC1";

module {
  /// Converts `Principal` to `ICRC1.Subaccount`.
  public func toSubaccount(p : Principal) : ICRC1.Subaccount {
    // p blob size can vary, but 29 bytes as most. We preserve it'subaccount size in result blob
    // and it'subaccount data itself so it can be deserialized back to p
    let bytes = Blob.toArray(Principal.toBlob(p));
    let size = bytes.size();

    assert size <= 29;

    Array.tabulate<Nat8>(
      32,
      func(i : Nat) : Nat8 {
        if (i + size < 31) {
          0;
        } else if (i + size == 31) {
          Nat8.fromNat(size);
        } else {
          bytes[i + size - 32];
        };
      },
    ) |> Blob.fromArray(_);
  };

  /// Converts `ICRC1.Subaccount` to `Principal`.
  public func toPrincipal(subaccount : ICRC1.Subaccount) : ?Principal {
    func first(bytes : [Nat8]) : Nat {
      var i = 0;
      while (i < 32) {
        if (bytes[i] != 0) {
          return i;
        };
        i += 1;
      };
      i;
    };

    let bytes = Blob.toArray(subaccount);
    assert bytes.size() == 32;

    let size_index = first(bytes);
    if (size_index == 32) return null;

    let size = Nat8.toNat(bytes[size_index]);
    if (size_index + size != 31) return null;
    Array.tabulate(size, func(i : Nat) : Nat8 = bytes[i + 1 + size_index])
    |> Blob.fromArray(_)
    |> ?Principal.fromBlob(_);
  };
};
