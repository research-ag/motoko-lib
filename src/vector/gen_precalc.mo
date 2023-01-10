import Array "mo:base/Array";
import Buffer "mo:base/Buffer";
import Nat32 "mo:base/Nat32";
import Debug "mo:base/Debug";
import Prelude "mo:base/Prelude";

type FourTuple = (Nat32, Nat32, Nat32, Nat32);

func toHexText(value : Nat32) : Text {
    var text = ""; 
    var x = value;
    while (x > 0) {
        let rem = x % 16;
        x /= 16;

        text := 
            (switch (rem) {
                case 0 { "0" };
                case 1 { "1" };
                case 2 { "2" };
                case 3 { "3" };
                case 4 { "4" };
                case 5 { "5" };
                case 6 { "6" };
                case 7 { "7" };
                case 8 { "8" };
                case 9 { "9" };
                case 10 { "A" };
                case 11 { "B" };
                case 12 { "C" };
                case 13 { "D" };
                case 14 { "E" };
                case 15 { "F" };
                case _ { Prelude.unreachable() }
            }) # text;
    };
    if (text == "") text := "0";
    "0x" # text;
};

let precalc = Array.tabulate<FourTuple>(32, func (leadingZeros) {
    let super_block_index = 31 - Nat32.fromNat(leadingZeros);
    let data_blocks_count_log = super_block_index >> 1;
    let data_blocks_capacity_log = super_block_index - data_blocks_count_log;

    let data_blocks_count = 1 << data_blocks_count_log;

    let data_blocks_before = if ((super_block_index & 1) == 0) {
        (data_blocks_count - 1) << 1;
    } else {
        ((data_blocks_count - 1) << 1) + data_blocks_count;
    };
    let element_mask = (1 << data_blocks_capacity_log) - 1;

    let data_block_mask = (1 << super_block_index) - 1 - element_mask;

    (data_block_mask, element_mask, data_blocks_capacity_log, data_blocks_before)
});

let text = Buffer.toText<FourTuple>(Buffer.fromArray<FourTuple>(precalc), func (tuple) {
    let (a, b, c, d) = tuple;
    "\n(" # toHexText(a) # ", " # toHexText(b) # ", " # toHexText(c) # ", " # toHexText(d) # ")"
});

Debug.print(text);
