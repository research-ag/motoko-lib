import Region "mo:base/Region";

module {
  public type StableData = {
    data : Region;
    var count : Nat64;
    var last_key : Nat32;
  };

  public class IncreasingKeyMap() {
    var state_ : ?StableData = null;

    func state() : StableData {
      switch (state_) {
        case (?s) { s };
        case (null) {
          let s : StableData = {
            data = Region.new();
            var count = 0;
            var last_key = 0;
          };
          state_ := ?s;
          s;
        };
      };
    };

    func regionEnsureSizeBytes(r : Region, new_byte_count : Nat64) {
      let pages = Region.size(r);
      if (new_byte_count > pages << 16) {
        let new_pages = ((new_byte_count + ((1 << 16) - 1)) / (1 << 16)) - pages;
        assert Region.grow(r, new_pages) == pages;
      };
    };

    public func add(key : Nat32, value : Nat64) {
      let s = state();
      assert s.last_key < key or s.last_key == 0;
      let index = s.count * 12;
      regionEnsureSizeBytes(s.data, index + 12);
      Region.storeNat32(s.data, index, key);
      Region.storeNat64(s.data, index + 4, value);
      s.last_key := key;
      s.count += 1;
    };

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

    public func share() : StableData = state();

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
