import Region "mo:base/Region";

module {
  /// Stable data type
  public type StableData = {
    data : Region;
    var count : Nat64;
    var last_key : ?Nat32;
  };

  /// Map from keys to values, keys should be incresing in order of addition
  public class IncreasingKeyMap() {
    var state_ : ?StableData = null;

    func state() : StableData {
      switch (state_) {
        case (?s) { s };
        case (null) {
          let s : StableData = {
            data = Region.new();
            var count = 0;
            var last_key = null;
          };
          state_ := ?s;
          s;
        };
      };
    };

    /// Add key-value pair to array assuming keys are increasing in order of addition
    public func add(key : Nat32, value : Nat64) {
      let s = state();
      assert switch (s.last_key) {
        case (?x) x < key;
        case (null) true;
      };
      let index = s.count * 12;
      if (index % (2 ** 16) == 0 and index / (2 ** 16) == Region.size(s.data)) {
        assert Region.grow(s.data, 1) != 0xFFFF_FFFF_FFFF_FFFF;
      };
      Region.storeNat32(s.data, index, key);
      Region.storeNat64(s.data, index + 4, value);
      s.last_key := ?key;
      s.count += 1;
    };

    /// Find value corresponding to `key` or return null if there is no such `key`
    public func find(key : Nat32) : ?Nat64 {
      let s = state();
      var left : Nat64 = 0;
      var right = s.count;
      while (right - left > 1) {
        let mid = left + (right - left) / 2;
        let index = mid * 12;
        let in_mid = Region.loadNat32(s.data, index);
        if (in_mid <= key) {
          left := mid;
        } else {
          right := mid;
        };
      };
      if (Region.loadNat32(s.data, left * 12) == key) {
        ?Region.loadNat64(s.data, left * 12 + 4);
      } else {
        null;
      };
    };

    /// Reset state with saving region
    public func reset() {
      let s = state();
      s.count := 0;
      s.last_key := null;
    };

    /// Share stable content
    public func share() : StableData = state();

    /// Unshare from stable content
    public func unshare(data : StableData) {
      switch (state_) {
        case (?s) {
          assert false;
        };
        case (null) {
          state_ := ?data;
        };
      };
    };
  };
};
