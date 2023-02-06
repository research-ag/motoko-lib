import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Nat8 "mo:base/Nat8";
import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";

module {
  public type Algorithm = {
    #sha384;
    #sha512;
    #sha512_224;
    #sha512_256;
  };
  let K : [Nat64] = [
    0x428a2f98d728ae22,
    0x7137449123ef65cd,
    0xb5c0fbcfec4d3b2f,
    0xe9b5dba58189dbbc,
    0x3956c25bf348b538,
    0x59f111f1b605d019,
    0x923f82a4af194f9b,
    0xab1c5ed5da6d8118,
    0xd807aa98a3030242,
    0x12835b0145706fbe,
    0x243185be4ee4b28c,
    0x550c7dc3d5ffb4e2,
    0x72be5d74f27b896f,
    0x80deb1fe3b1696b1,
    0x9bdc06a725c71235,
    0xc19bf174cf692694,
    0xe49b69c19ef14ad2,
    0xefbe4786384f25e3,
    0x0fc19dc68b8cd5b5,
    0x240ca1cc77ac9c65,
    0x2de92c6f592b0275,
    0x4a7484aa6ea6e483,
    0x5cb0a9dcbd41fbd4,
    0x76f988da831153b5,
    0x983e5152ee66dfab,
    0xa831c66d2db43210,
    0xb00327c898fb213f,
    0xbf597fc7beef0ee4,
    0xc6e00bf33da88fc2,
    0xd5a79147930aa725,
    0x06ca6351e003826f,
    0x142929670a0e6e70,
    0x27b70a8546d22ffc,
    0x2e1b21385c26c926,
    0x4d2c6dfc5ac42aed,
    0x53380d139d95b3df,
    0x650a73548baf63de,
    0x766a0abb3c77b2a8,
    0x81c2c92e47edaee6,
    0x92722c851482353b,
    0xa2bfe8a14cf10364,
    0xa81a664bbc423001,
    0xc24b8b70d0f89791,
    0xc76c51a30654be30,
    0xd192e819d6ef5218,
    0xd69906245565a910,
    0xf40e35855771202a,
    0x106aa07032bbd1b8,
    0x19a4c116b8d2d0c8,
    0x1e376c085141ab53,
    0x2748774cdf8eeb99,
    0x34b0bcb5e19b48a8,
    0x391c0cb3c5c95a63,
    0x4ed8aa4ae3418acb,
    0x5b9cca4f7763e373,
    0x682e6ff3d6b2b8a3,
    0x748f82ee5defb2fc,
    0x78a5636f43172f60,
    0x84c87814a1f0ab72,
    0x8cc702081a6439ec,
    0x90befffa23631e28,
    0xa4506cebde82bde9,
    0xbef9a3f7b2c67915,
    0xc67178f2e372532b,
    0xca273eceea26619c,
    0xd186b8c721c0c207,
    0xeada7dd6cde0eb1e,
    0xf57d4f7fee6ed178,
    0x06f067aa72176fba,
    0x0a637dc5a2c898a6,
    0x113f9804bef90dae,
    0x1b710b35131c471b,
    0x28db77f523047d84,
    0x32caab7b40c72493,
    0x3c9ebe0a15c9bebc,
    0x431d67c49c100d4c,
    0x4cc5d4becb3e42b6,
    0x597f299cfc657e2a,
    0x5fcb6fab3ad6faec,
    0x6c44198c4a475817,
  ];

  let ivs : [[Nat64]] = [
    [
      // 512-224
      0x8c3d37c819544da2,
      0x73e1996689dcd4d6,
      0x1dfab7ae32ff9c82,
      0x679dd514582f9fcf,
      0x0f6d2b697bd44da8,
      0x77e36f7304c48942,
      0x3f9d85a86a1d36c8,
      0x1112e6ad91d692a1,
    ],
    [
      // 512-256
      0x22312194fc2bf72c,
      0x9f555fa3c84c64c2,
      0x2393b86b6f53b151,
      0x963877195940eabd,
      0x96283ee2a88effe3,
      0xbe5e1e2553863992,
      0x2b0199fc2c85b8aa,
      0x0eb72ddc81c52ca2,
    ],
    [
      // 384
      0xcbbb9d5dc1059ed8,
      0x629a292a367cd507,
      0x9159015a3070dd17,
      0x152fecd8f70e5939,
      0x67332667ffc00b31,
      0x8eb44a8768581511,
      0xdb0c2e0d64f98fa7,
      0x47b5481dbefa4fa4,
    ],
    [
      // 512
      0x6a09e667f3bcc908,
      0xbb67ae8584caa73b,
      0x3c6ef372fe94f82b,
      0xa54ff53a5f1d36f1,
      0x510e527fade682d1,
      0x9b05688c2b3e6c1f,
      0x1f83d9abfb41bd6b,
      0x5be0cd19137e2179,
    ],
  ];

  // indices used in the 64 expansion rounds
  let expansion_rounds = [(0, 1, 9, 14, 16), (1, 2, 10, 15, 17), (2, 3, 11, 16, 18), (3, 4, 12, 17, 19), (4, 5, 13, 18, 20), (5, 6, 14, 19, 21), (6, 7, 15, 20, 22), (7, 8, 16, 21, 23), (8, 9, 17, 22, 24), (9, 10, 18, 23, 25), (10, 11, 19, 24, 26), (11, 12, 20, 25, 27), (12, 13, 21, 26, 28), (13, 14, 22, 27, 29), (14, 15, 23, 28, 30), (15, 16, 24, 29, 31), (16, 17, 25, 30, 32), (17, 18, 26, 31, 33), (18, 19, 27, 32, 34), (19, 20, 28, 33, 35), (20, 21, 29, 34, 36), (21, 22, 30, 35, 37), (22, 23, 31, 36, 38), (23, 24, 32, 37, 39), (24, 25, 33, 38, 40), (25, 26, 34, 39, 41), (26, 27, 35, 40, 42), (27, 28, 36, 41, 43), (28, 29, 37, 42, 44), (29, 30, 38, 43, 45), (30, 31, 39, 44, 46), (31, 32, 40, 45, 47), (32, 33, 41, 46, 48), (33, 34, 42, 47, 49), (34, 35, 43, 48, 50), (35, 36, 44, 49, 51), (36, 37, 45, 50, 52), (37, 38, 46, 51, 53), (38, 39, 47, 52, 54), (39, 40, 48, 53, 55), (40, 41, 49, 54, 56), (41, 42, 50, 55, 57), (42, 43, 51, 56, 58), (43, 44, 52, 57, 59), (44, 45, 53, 58, 60), (45, 46, 54, 59, 61), (46, 47, 55, 60, 62), (47, 48, 56, 61, 63), (48, 49, 57, 62, 64), (49, 50, 58, 63, 65), (50, 51, 59, 64, 66), (51, 52, 60, 65, 67), (52, 53, 61, 66, 68), (53, 54, 62, 67, 69), (54, 55, 63, 68, 70), (55, 56, 64, 69, 71), (56, 57, 65, 70, 72), (57, 58, 66, 71, 73), (58, 59, 67, 72, 74), (59, 60, 68, 73, 75), (60, 61, 69, 74, 76), (61, 62, 70, 75, 77), (62, 63, 71, 76, 78), (63, 64, 72, 77, 79)];

  // indices used in the 80 compression rounds
  let compression_rounds = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79];

  let rot = Nat64.bitrotRight;

  public class Digest(algo_ : Algorithm) {
    let (sum_bytes, iv) = switch (algo_) {
      case (#sha512_224) { (28, 0) };
      case (#sha512_256) { (32, 1) };
      case (#sha384) { (48, 2) };
      case (#sha512) { (64, 3) };
    };

    public func algo() : Algorithm = algo_;

    let state : [var Nat64] = Array.init<Nat64>(8, 0);
    let msg : [var Nat64] = Array.init<Nat64>(80, 0);
    let digest = Array.init<Nat8>(sum_bytes, 0);
    var word : Nat64 = 0;

    var i_msg : Nat8 = 0;
    var i_byte : Nat8 = 8;
    var i_block : Nat64 = 0;

    public func reset() {
      i_msg := 0;
      i_byte := 8;
      i_block := 0;
      for (i in [0, 1, 2, 3, 4, 5, 6, 7].vals()) {
        state[i] := ivs[iv][i];
      };
    };

    reset();

    private func writeByte(val : Nat8) : () {
      word := (word << 8) ^ Nat64.fromIntWrap(Nat8.toNat(val));
      i_byte -%= 1;
      if (i_byte == 0) {
        msg[Nat8.toNat(i_msg)] := word;
        i_byte := 8;
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
        msg[m] := msg[i] +% rot(v0, 01) ^ rot(v0, 08) ^ (v0 >> 07) +% msg[k] +% rot(v1, 19) ^ rot(v1, 61) ^ (v1 >> 06);
      };
      // compress
      var a = state[0];
      var b = state[1];
      var c = state[2];
      var d = state[3];
      var e = state[4];
      var f = state[5];
      var g = state[6];
      var h = state[7];
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
        let maj = (a & b) ^ (a & c) ^ (b & c);
        let t = h +% K[i] +% msg[i] +% (e & f) ^ (^ e & g) +% rot(e, 14) ^ rot(e, 18) ^ rot(e, 41);
        h := g;
        g := f;
        f := e;
        e := d +% t;
        d := c;
        c := b;
        b := a;
        a := t +% maj +% rot(a, 28) ^ rot(a, 34) ^ rot(a, 39);
      };
      // final addition
      state[0] +%= a;
      state[1] +%= b;
      state[2] +%= c;
      state[3] +%= d;
      state[4] +%= e;
      state[5] +%= f;
      state[6] +%= g;
      state[7] +%= h;
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
      // t = bytes in the last incomplete block (0-127)
      let t : Nat8 = (i_msg << 3) +% 8 -% i_byte;
      // p = length of padding (1-128)
      var p : Nat8 = if (t < 112) (112 -% t) else (240 -% t);
      // n_bits = length of message in bits
      // Note: This implementation only handles messages < 2^64 bits
      let n_bits : Nat64 = ((i_block << 7) +% Nat64.fromIntWrap(Nat8.toNat(t))) << 3;

      // write padding
      writeByte(0x80);
      p -%= 1;
      while (p != 0) {
        writeByte(0x00);
        p -%= 1;
      };

      // write length (16 bytes)
      // Note: this exactly fills the block buffer, hence process_block will get
      // triggered by the last writeByte
      writeByte(0x00);
      writeByte(0x00);
      writeByte(0x00);
      writeByte(0x00);
      writeByte(0x00);
      writeByte(0x00);
      writeByte(0x00);
      writeByte(0x00);
      writeByte(Nat8.fromIntWrap(Nat64.toNat((n_bits >> 56) & 0xff)));
      writeByte(Nat8.fromIntWrap(Nat64.toNat((n_bits >> 48) & 0xff)));
      writeByte(Nat8.fromIntWrap(Nat64.toNat((n_bits >> 40) & 0xff)));
      writeByte(Nat8.fromIntWrap(Nat64.toNat((n_bits >> 32) & 0xff)));
      writeByte(Nat8.fromIntWrap(Nat64.toNat((n_bits >> 24) & 0xff)));
      writeByte(Nat8.fromIntWrap(Nat64.toNat((n_bits >> 16) & 0xff)));
      writeByte(Nat8.fromIntWrap(Nat64.toNat((n_bits >> 8) & 0xff)));
      writeByte(Nat8.fromIntWrap(Nat64.toNat(n_bits & 0xff)));

      // retrieve sum
      word := state[0];
      digest[0] := Nat8.fromIntWrap(Nat64.toNat((word >> 56) & 0xff));
      digest[1] := Nat8.fromIntWrap(Nat64.toNat((word >> 48) & 0xff));
      digest[2] := Nat8.fromIntWrap(Nat64.toNat((word >> 40) & 0xff));
      digest[3] := Nat8.fromIntWrap(Nat64.toNat((word >> 32) & 0xff));
      digest[4] := Nat8.fromIntWrap(Nat64.toNat((word >> 24) & 0xff));
      digest[5] := Nat8.fromIntWrap(Nat64.toNat((word >> 16) & 0xff));
      digest[6] := Nat8.fromIntWrap(Nat64.toNat((word >> 8) & 0xff));
      digest[7] := Nat8.fromIntWrap(Nat64.toNat(word & 0xff));
      word := state[1];
      digest[8] := Nat8.fromIntWrap(Nat64.toNat((word >> 56) & 0xff));
      digest[9] := Nat8.fromIntWrap(Nat64.toNat((word >> 48) & 0xff));
      digest[10] := Nat8.fromIntWrap(Nat64.toNat((word >> 40) & 0xff));
      digest[11] := Nat8.fromIntWrap(Nat64.toNat((word >> 32) & 0xff));
      digest[12] := Nat8.fromIntWrap(Nat64.toNat((word >> 24) & 0xff));
      digest[13] := Nat8.fromIntWrap(Nat64.toNat((word >> 16) & 0xff));
      digest[14] := Nat8.fromIntWrap(Nat64.toNat((word >> 8) & 0xff));
      digest[15] := Nat8.fromIntWrap(Nat64.toNat(word & 0xff));
      word := state[2];
      digest[16] := Nat8.fromIntWrap(Nat64.toNat((word >> 56) & 0xff));
      digest[17] := Nat8.fromIntWrap(Nat64.toNat((word >> 48) & 0xff));
      digest[18] := Nat8.fromIntWrap(Nat64.toNat((word >> 40) & 0xff));
      digest[19] := Nat8.fromIntWrap(Nat64.toNat((word >> 32) & 0xff));
      digest[20] := Nat8.fromIntWrap(Nat64.toNat((word >> 24) & 0xff));
      digest[21] := Nat8.fromIntWrap(Nat64.toNat((word >> 16) & 0xff));
      digest[22] := Nat8.fromIntWrap(Nat64.toNat((word >> 8) & 0xff));
      digest[23] := Nat8.fromIntWrap(Nat64.toNat(word & 0xff));
      word := state[3];
      digest[24] := Nat8.fromIntWrap(Nat64.toNat((word >> 56) & 0xff));
      digest[25] := Nat8.fromIntWrap(Nat64.toNat((word >> 48) & 0xff));
      digest[26] := Nat8.fromIntWrap(Nat64.toNat((word >> 40) & 0xff));
      digest[27] := Nat8.fromIntWrap(Nat64.toNat((word >> 32) & 0xff));

      if (algo_ == #sha512_224) return Blob.fromArrayMut(digest);

      digest[28] := Nat8.fromIntWrap(Nat64.toNat((word >> 24) & 0xff));
      digest[29] := Nat8.fromIntWrap(Nat64.toNat((word >> 16) & 0xff));
      digest[30] := Nat8.fromIntWrap(Nat64.toNat((word >> 8) & 0xff));
      digest[31] := Nat8.fromIntWrap(Nat64.toNat(word & 0xff));

      if (algo_ == #sha512_256) return Blob.fromArrayMut(digest);

      word := state[4];
      digest[32] := Nat8.fromIntWrap(Nat64.toNat((word >> 56) & 0xff));
      digest[33] := Nat8.fromIntWrap(Nat64.toNat((word >> 48) & 0xff));
      digest[34] := Nat8.fromIntWrap(Nat64.toNat((word >> 40) & 0xff));
      digest[35] := Nat8.fromIntWrap(Nat64.toNat((word >> 32) & 0xff));
      digest[36] := Nat8.fromIntWrap(Nat64.toNat((word >> 24) & 0xff));
      digest[37] := Nat8.fromIntWrap(Nat64.toNat((word >> 16) & 0xff));
      digest[38] := Nat8.fromIntWrap(Nat64.toNat((word >> 8) & 0xff));
      digest[39] := Nat8.fromIntWrap(Nat64.toNat(word & 0xff));
      word := state[5];
      digest[40] := Nat8.fromIntWrap(Nat64.toNat((word >> 56) & 0xff));
      digest[41] := Nat8.fromIntWrap(Nat64.toNat((word >> 48) & 0xff));
      digest[42] := Nat8.fromIntWrap(Nat64.toNat((word >> 40) & 0xff));
      digest[43] := Nat8.fromIntWrap(Nat64.toNat((word >> 32) & 0xff));
      digest[44] := Nat8.fromIntWrap(Nat64.toNat((word >> 24) & 0xff));
      digest[45] := Nat8.fromIntWrap(Nat64.toNat((word >> 16) & 0xff));
      digest[46] := Nat8.fromIntWrap(Nat64.toNat((word >> 8) & 0xff));
      digest[47] := Nat8.fromIntWrap(Nat64.toNat(word & 0xff));

      if (algo_ == #sha384) return Blob.fromArrayMut(digest);

      word := state[6];
      digest[48] := Nat8.fromIntWrap(Nat64.toNat((word >> 56) & 0xff));
      digest[49] := Nat8.fromIntWrap(Nat64.toNat((word >> 48) & 0xff));
      digest[50] := Nat8.fromIntWrap(Nat64.toNat((word >> 40) & 0xff));
      digest[51] := Nat8.fromIntWrap(Nat64.toNat((word >> 32) & 0xff));
      digest[52] := Nat8.fromIntWrap(Nat64.toNat((word >> 24) & 0xff));
      digest[53] := Nat8.fromIntWrap(Nat64.toNat((word >> 16) & 0xff));
      digest[54] := Nat8.fromIntWrap(Nat64.toNat((word >> 8) & 0xff));
      digest[55] := Nat8.fromIntWrap(Nat64.toNat(word & 0xff));
      word := state[7];
      digest[56] := Nat8.fromIntWrap(Nat64.toNat((word >> 56) & 0xff));
      digest[57] := Nat8.fromIntWrap(Nat64.toNat((word >> 48) & 0xff));
      digest[58] := Nat8.fromIntWrap(Nat64.toNat((word >> 40) & 0xff));
      digest[59] := Nat8.fromIntWrap(Nat64.toNat((word >> 32) & 0xff));
      digest[60] := Nat8.fromIntWrap(Nat64.toNat((word >> 24) & 0xff));
      digest[61] := Nat8.fromIntWrap(Nat64.toNat((word >> 16) & 0xff));
      digest[62] := Nat8.fromIntWrap(Nat64.toNat((word >> 8) & 0xff));
      digest[63] := Nat8.fromIntWrap(Nat64.toNat(word & 0xff));

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
