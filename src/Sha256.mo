import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Nat8 "mo:base/Nat8";
import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";

module {
  public type Algorithm = {
    #sha224;
    #sha256;
  };

  let K : [Nat32] = [
    0x428a2f98,
    0x71374491,
    0xb5c0fbcf,
    0xe9b5dba5,
    0x3956c25b,
    0x59f111f1,
    0x923f82a4,
    0xab1c5ed5,
    0xd807aa98,
    0x12835b01,
    0x243185be,
    0x550c7dc3,
    0x72be5d74,
    0x80deb1fe,
    0x9bdc06a7,
    0xc19bf174,
    0xe49b69c1,
    0xefbe4786,
    0x0fc19dc6,
    0x240ca1cc,
    0x2de92c6f,
    0x4a7484aa,
    0x5cb0a9dc,
    0x76f988da,
    0x983e5152,
    0xa831c66d,
    0xb00327c8,
    0xbf597fc7,
    0xc6e00bf3,
    0xd5a79147,
    0x06ca6351,
    0x14292967,
    0x27b70a85,
    0x2e1b2138,
    0x4d2c6dfc,
    0x53380d13,
    0x650a7354,
    0x766a0abb,
    0x81c2c92e,
    0x92722c85,
    0xa2bfe8a1,
    0xa81a664b,
    0xc24b8b70,
    0xc76c51a3,
    0xd192e819,
    0xd6990624,
    0xf40e3585,
    0x106aa070,
    0x19a4c116,
    0x1e376c08,
    0x2748774c,
    0x34b0bcb5,
    0x391c0cb3,
    0x4ed8aa4a,
    0x5b9cca4f,
    0x682e6ff3,
    0x748f82ee,
    0x78a5636f,
    0x84c87814,
    0x8cc70208,
    0x90befffa,
    0xa4506ceb,
    0xbef9a3f7,
    0xc67178f2,
  ];

  let ivs : [[Nat32]] = [
    [
      // 224
      0xc1059ed8,
      0x367cd507,
      0x3070dd17,
      0xf70e5939,
      0xffc00b31,
      0x68581511,
      0x64f98fa7,
      0xbefa4fa4,
    ],
    [
      // 256
      0x6a09e667,
      0xbb67ae85,
      0x3c6ef372,
      0xa54ff53a,
      0x510e527f,
      0x9b05688c,
      0x1f83d9ab,
      0x5be0cd19,
    ],
  ];

  // indices used in the 48 expansion rounds
  let expansion_rounds = [(0, 1, 9, 14, 16), (1, 2, 10, 15, 17), (2, 3, 11, 16, 18), (3, 4, 12, 17, 19), (4, 5, 13, 18, 20), (5, 6, 14, 19, 21), (6, 7, 15, 20, 22), (7, 8, 16, 21, 23), (8, 9, 17, 22, 24), (9, 10, 18, 23, 25), (10, 11, 19, 24, 26), (11, 12, 20, 25, 27), (12, 13, 21, 26, 28), (13, 14, 22, 27, 29), (14, 15, 23, 28, 30), (15, 16, 24, 29, 31), (16, 17, 25, 30, 32), (17, 18, 26, 31, 33), (18, 19, 27, 32, 34), (19, 20, 28, 33, 35), (20, 21, 29, 34, 36), (21, 22, 30, 35, 37), (22, 23, 31, 36, 38), (23, 24, 32, 37, 39), (24, 25, 33, 38, 40), (25, 26, 34, 39, 41), (26, 27, 35, 40, 42), (27, 28, 36, 41, 43), (28, 29, 37, 42, 44), (29, 30, 38, 43, 45), (30, 31, 39, 44, 46), (31, 32, 40, 45, 47), (32, 33, 41, 46, 48), (33, 34, 42, 47, 49), (34, 35, 43, 48, 50), (35, 36, 44, 49, 51), (36, 37, 45, 50, 52), (37, 38, 46, 51, 53), (38, 39, 47, 52, 54), (39, 40, 48, 53, 55), (40, 41, 49, 54, 56), (41, 42, 50, 55, 57), (42, 43, 51, 56, 58), (43, 44, 52, 57, 59), (44, 45, 53, 58, 60), (45, 46, 54, 59, 61), (46, 47, 55, 60, 62), (47, 48, 56, 61, 63)];
  // indices used in the 64 compression rounds
  let compression_rounds = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63];

  let rot = Nat32.bitrotRight;

  public class Digest(algo_ : Algorithm) {
    let (sum_bytes, iv) = switch (algo_) {
      case (#sha224) { (28, 0) };
      case (#sha256) { (32, 1) };
    };

    public func algo() : Algorithm = algo_;

    let state_ : [var Nat32] = Array.init<Nat32>(8, 0);
    let msg : [var Nat32] = Array.init<Nat32>(64, 0);
    let digest = Array.init<Nat8>(sum_bytes, 0);
    var word : Nat32 = 0;

    var i_msg : Nat8 = 0;
    var i_byte : Nat8 = 4;
    var i_block : Nat64 = 0;

    public func reset() {
      i_msg := 0;
      i_byte := 4;
      i_block := 0;
      for (i in [0, 1, 2, 3, 4, 5, 6, 7].vals()) {
        state_[i] := ivs[iv][i];
      };
    };

    reset();

    private func writeByte(val : Nat8) : () {
      word := (word << 8) ^ Nat32.fromIntWrap(Nat8.toNat(val));
      i_byte -%= 1;
      if (i_byte == 0) {
        msg[Nat8.toNat(i_msg)] := word;
        i_byte := 4;
        i_msg +%= 1;
        if (i_msg == 16) {
          process_block();
          i_msg := 0;
          i_block +%= 1;
        };
      };
    };

    private func process_block() : () {
      for ((i, j, k, l, m) in expansion_rounds.vals()) {
        // (j,k,l,m) = (i+1,i+9,i+14,i+16)
        let (v0, v1) = (msg[j], msg[l]);
        // Below is an inlined version of this code:
        //   let s0 = rot(v0, 07) ^ rot(v0, 18) ^ (v0 >> 03);
        //   let s1 = rot(v1, 17) ^ rot(v1, 19) ^ (v1 >> 10);
        //   msg[m] := msg[i] +% s0 +% msg[k] +% s1;
        // Inlining has saved 144 cycles per block.
        msg[m] := msg[i] +% rot(v0, 07) ^ rot(v0, 18) ^ (v0 >> 03) +% msg[k] +% rot(v1, 17) ^ rot(v1, 19) ^ (v1 >> 10);
      };
      // compress
      var a = state_[0];
      var b = state_[1];
      var c = state_[2];
      var d = state_[3];
      var e = state_[4];
      var f = state_[5];
      var g = state_[6];
      var h = state_[7];
      for (i in compression_rounds.keys()) {
        //  Below is an inlined version of this code:
        //    let ch = (e & f) ^ (^ e & g);
        //    let maj = (a & b) ^ (a & c) ^ (b & c);
        //    let sigma0 = rot(a, 02) ^ rot(a, 13) ^ rot(a, 22);
        //    let sigma1 = rot(e, 06) ^ rot(e, 11) ^ rot(e, 25);
        //    let t = h +% K[i] +% msg[i] +% ch +% sigma1;
        //    h := g;
        //    g := f;
        //    f := e;
        //    e := d +% t;
        //    d := c;
        //    c := b;
        //    b := a;
        //    a := t +% maj +% sigma0;
        //  Inlining saves 608 cycles per block.
        let maj = (a & b) ^ (a & c) ^ (b & c);
        let t = h +% K[i] +% msg[i] +% (e & f) ^ (^ e & g) +% rot(e, 06) ^ rot(e, 11) ^ rot(e, 25);
        h := g;
        g := f;
        f := e;
        e := d +% t;
        d := c;
        c := b;
        b := a;
        a := t +% maj +% rot(a, 02) ^ rot(a, 13) ^ rot(a, 22);
      };
      // final addition
      state_[0] +%= a;
      state_[1] +%= b;
      state_[2] +%= c;
      state_[3] +%= d;
      state_[4] +%= e;
      state_[5] +%= f;
      state_[6] +%= g;
      state_[7] +%= h;
    };

    public func writeIter(iter : { next() : ?Nat8 }) : () {
      label reading loop {
        switch (iter.next()) {
          case (?val) {
            writeByte(val);
            continue reading;
          };
          case (null) {
            break reading;
          };
        };
      };
    };

    public func writeArray(arr : [Nat8]) : () = writeIter(arr.vals());
    public func writeBlob(blob : Blob) : () = writeIter(blob.vals());

    public func sum() : Blob {
      // calculate padding
      // t = bytes in the last incomplete block (0-63)
      let t : Nat8 = (i_msg << 2) +% 4 -% i_byte;
      // p = length of padding (1-64)
      var p = if (t < 56) (56 -% t) else (120 -% t);
      // n_bits = length of message in bits
      // Note: This implementation only handles messages < 2^61 bytes
      let n_bits = ((i_block << 6) +% Nat64.fromIntWrap(Nat8.toNat(t))) << 3;

      // write padding
      writeByte(0x80);
      p -%= 1;
      while (p != 0) {
        writeByte(0x00);
        p -%= 1;
      };

      // write length (8 bytes)
      // Note: this exactly fills the block buffer, hence process_block will get
      // triggered by the last writeByte call
      writeByte(Nat8.fromIntWrap(Nat64.toNat((n_bits >> 56) & 0xff)));
      writeByte(Nat8.fromIntWrap(Nat64.toNat((n_bits >> 48) & 0xff)));
      writeByte(Nat8.fromIntWrap(Nat64.toNat((n_bits >> 40) & 0xff)));
      writeByte(Nat8.fromIntWrap(Nat64.toNat((n_bits >> 32) & 0xff)));
      writeByte(Nat8.fromIntWrap(Nat64.toNat((n_bits >> 24) & 0xff)));
      writeByte(Nat8.fromIntWrap(Nat64.toNat((n_bits >> 16) & 0xff)));
      writeByte(Nat8.fromIntWrap(Nat64.toNat((n_bits >> 8) & 0xff)));
      writeByte(Nat8.fromIntWrap(Nat64.toNat(n_bits & 0xff)));

      // retrieve sum
      word := state_[0];
      digest[0] := Nat8.fromIntWrap(Nat32.toNat((word >> 24) & 0xff));
      digest[1] := Nat8.fromIntWrap(Nat32.toNat((word >> 16) & 0xff));
      digest[2] := Nat8.fromIntWrap(Nat32.toNat((word >> 8) & 0xff));
      digest[3] := Nat8.fromIntWrap(Nat32.toNat(word & 0xff));
      word := state_[1];
      digest[4] := Nat8.fromIntWrap(Nat32.toNat((word >> 24) & 0xff));
      digest[5] := Nat8.fromIntWrap(Nat32.toNat((word >> 16) & 0xff));
      digest[6] := Nat8.fromIntWrap(Nat32.toNat((word >> 8) & 0xff));
      digest[7] := Nat8.fromIntWrap(Nat32.toNat(word & 0xff));
      word := state_[2];
      digest[8] := Nat8.fromIntWrap(Nat32.toNat((word >> 24) & 0xff));
      digest[9] := Nat8.fromIntWrap(Nat32.toNat((word >> 16) & 0xff));
      digest[10] := Nat8.fromIntWrap(Nat32.toNat((word >> 8) & 0xff));
      digest[11] := Nat8.fromIntWrap(Nat32.toNat(word & 0xff));
      word := state_[3];
      digest[12] := Nat8.fromIntWrap(Nat32.toNat((word >> 24) & 0xff));
      digest[13] := Nat8.fromIntWrap(Nat32.toNat((word >> 16) & 0xff));
      digest[14] := Nat8.fromIntWrap(Nat32.toNat((word >> 8) & 0xff));
      digest[15] := Nat8.fromIntWrap(Nat32.toNat(word & 0xff));
      word := state_[4];
      digest[16] := Nat8.fromIntWrap(Nat32.toNat((word >> 24) & 0xff));
      digest[17] := Nat8.fromIntWrap(Nat32.toNat((word >> 16) & 0xff));
      digest[18] := Nat8.fromIntWrap(Nat32.toNat((word >> 8) & 0xff));
      digest[19] := Nat8.fromIntWrap(Nat32.toNat(word & 0xff));
      word := state_[5];
      digest[20] := Nat8.fromIntWrap(Nat32.toNat((word >> 24) & 0xff));
      digest[21] := Nat8.fromIntWrap(Nat32.toNat((word >> 16) & 0xff));
      digest[22] := Nat8.fromIntWrap(Nat32.toNat((word >> 8) & 0xff));
      digest[23] := Nat8.fromIntWrap(Nat32.toNat(word & 0xff));
      word := state_[6];
      digest[24] := Nat8.fromIntWrap(Nat32.toNat((word >> 24) & 0xff));
      digest[25] := Nat8.fromIntWrap(Nat32.toNat((word >> 16) & 0xff));
      digest[26] := Nat8.fromIntWrap(Nat32.toNat((word >> 8) & 0xff));
      digest[27] := Nat8.fromIntWrap(Nat32.toNat(word & 0xff));

      if (algo_ == #sha224) return Blob.fromArrayMut(digest);

      word := state_[7];
      digest[28] := Nat8.fromIntWrap(Nat32.toNat((word >> 24) & 0xff));
      digest[29] := Nat8.fromIntWrap(Nat32.toNat((word >> 16) & 0xff));
      digest[30] := Nat8.fromIntWrap(Nat32.toNat((word >> 8) & 0xff));
      digest[31] := Nat8.fromIntWrap(Nat32.toNat(word & 0xff));

      return Blob.fromArrayMut(digest);
    };
  }; // class Digest

  // Calculate SHA256 hash digest from [Nat8].
  public func fromArray(algo : Algorithm, arr : [Nat8]) : Blob {
    let digest = Digest(algo);
    digest.writeIter(arr.vals());
    return digest.sum();
  };

  // Calculate SHA2 hash digest from Iter.
  public func fromIter(algo : Algorithm, iter : { next() : ?Nat8 }) : Blob {
    let digest = Digest(algo);
    digest.writeIter(iter);
    return digest.sum();
  };

  // Calculate SHA2 hash digest from Blob.
  public func fromBlob(algo : Algorithm, b : Blob) : Blob {
    let digest = Digest(algo);
    digest.writeIter(b.vals());
    return digest.sum();
  };
};
