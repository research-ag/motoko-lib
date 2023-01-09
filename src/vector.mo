import Prim "mo:⛔";
import Buffer "mo:base/Buffer";
import Nat32 "mo:base/Nat32";
import Nat "mo:base/Nat";
import Debug "mo:base/Debug";
import Array "mo:base/Array";
import Option "mo:base/Option";
import Iter "mo:base/Iter";
import Int "mo:base/Int";
import Prelude "mo:base/Prelude";

module {
    let INTERNAL_ERROR = "Internal error in Vector";

    let precalc : [(Nat32, Nat32, Nat32, Nat32)] = [(0x7FFF0000, 0xFFFF, 0x10, 0x17FFE), 
        (0x3FFF8000, 0x7FFF, 0xF, 0xFFFE), 
        (0x1FFF8000, 0x7FFF, 0xF, 0xBFFE), 
        (0xFFFC000, 0x3FFF, 0xE, 0x7FFE), 
        (0x7FFC000, 0x3FFF, 0xE, 0x5FFE), 
        (0x3FFE000, 0x1FFF, 0xD, 0x3FFE), 
        (0x1FFE000, 0x1FFF, 0xD, 0x2FFE), 
        (0xFFF000, 0xFFF, 0xC, 0x1FFE), 
        (0x7FF000, 0xFFF, 0xC, 0x17FE), 
        (0x3FF800, 0x7FF, 0xB, 0xFFE), 
        (0x1FF800, 0x7FF, 0xB, 0xBFE), 
        (0xFFC00, 0x3FF, 0xA, 0x7FE), 
        (0x7FC00, 0x3FF, 0xA, 0x5FE), 
        (0x3FE00, 0x1FF, 0x9, 0x3FE), 
        (0x1FE00, 0x1FF, 0x9, 0x2FE), 
        (0xFF00, 0xFF, 0x8, 0x1FE), 
        (0x7F00, 0xFF, 0x8, 0x17E), 
        (0x3F80, 0x7F, 0x7, 0xFE), 
        (0x1F80, 0x7F, 0x7, 0xBE), 
        (0xFC0, 0x3F, 0x6, 0x7E), 
        (0x7C0, 0x3F, 0x6, 0x5E), 
        (0x3E0, 0x1F, 0x5, 0x3E), 
        (0x1E0, 0x1F, 0x5, 0x2E), 
        (0xF0, 0xF, 0x4, 0x1E), 
        (0x70, 0xF, 0x4, 0x16), 
        (0x38, 0x7, 0x3, 0xE), 
        (0x18, 0x7, 0x3, 0xA), 
        (0xC, 0x3, 0x2, 0x6), 
        (0x4, 0x3, 0x2, 0x4), 
        (0x2, 0x1, 0x1, 0x2), 
        (0x0, 0x1, 0x1, 0x1), 
        (0x0, 0x0, 0x0, 0x0)
    ];

    func unwrap<X>(x : ?X) : X {
        switch (x) {
            case (null) Prim.trap(INTERNAL_ERROR);
            case (?value) value;
        };
    };

    public type Vector<X> = {
        var data_blocks : [var ?[var ?X]]; // the index block
        // new element should be assigned to exaclty data_blocks[i_block][i_element]
        // i_block is in range [0; data_blocks.size()]
        var i_block : Nat;
        // i_element is in range [0; data_blocks[i_block].size())
        var i_element : Nat;
    };

    public func new<X>() : Vector<X> = {
        var data_blocks = [var]; 
        var i_block = 0;
        var i_element = 0;
    };

    public func clear<X>(vec : Vector<X>) {
        vec.data_blocks := [var];
        vec.i_block := 0;
        vec.i_element := 0;
    };

    public func clone<X>(vec : Vector<X>) : Vector<X> = {
        var data_blocks = Array.tabulateVar<?[var ?X]>(
            vec.data_blocks.size(),
            func (i) = Option.map(
                vec.data_blocks[i],
                func(block : [var ?X]) : [var ?X] = Array.tabulateVar<?X>(block.size(), func(j) = block[j])
            )
        );
        var i_block = vec.i_block;
        var i_element = vec.i_element;
    };

    public func size<X>(vec : Vector<X>) : Nat {
        if (vec.i_block == 0) { return vec.i_element }; 

        let d : Nat = vec.i_block; // index of the last block

        // We call all data blocks of the same capacity an "epoch". We number the epochs 0,1,2,...
        // A data block is in epoch e iff the data block has capacity 2^e.
        // Each epoch starting with epoch 1 spans exactly two super blocks.
        // Super block s falls in epoch ceil(s/2).

        // epoch of last data block
        let e : Nat = 32 - Nat32.toNat(Nat32.bitcountLeadingZero(Nat32.fromNat((d + 2) / 3))); 

        // capacity of all prior epochs combined 
        let cap_before_e : Nat = 2 * 4 ** (e - 1) - 1; 

        // data blocks in all prior epochs combined
        let blocks_before_e : Nat = 3 * 2 ** (e - 1) - 2;

        // prior blocks in the same epoch
        let prior_blocks_in_e : Nat = d - blocks_before_e;

        return cap_before_e + prior_blocks_in_e * 2 ** e + vec.i_element
    };

    func grow_index_block_if_needed<X>(vec : Vector<X>) {
        if (vec.data_blocks.size() == vec.i_block) {
            let new_length = if (vec.i_block == 0) 1 else vec.i_block * 2;
            vec.data_blocks := Array.tabulateVar<?[var ?X]>(new_length, func(i) {
                if (i < vec.i_block) {
                    vec.data_blocks[i];
                } else {
                    null
                }
            });
        }
    };

    public func add<X>(vec : Vector<X>, element : X) {
        if (vec.i_element == 0) {
            grow_index_block_if_needed(vec);
            let i_block = vec.i_block;

            // When removing last we keep one more data block, so can be not null
            if (Option.isNull(vec.data_blocks[i_block])) {
                let data_block_capacity = if (i_block == 0) {
                    1;
                }
                // The data block size doubles whenever i_block is of the form 3 * (2 ** i) - 2 for some i
                else if (i_block % 3 == 1 and Nat32.bitcountNonZero(Nat32.fromNat((i_block + 2) / 3)) == 1) {
                    unwrap(vec.data_blocks[i_block - 1]).size() * 2;
                }
                else {
                    unwrap(vec.data_blocks[i_block - 1]).size();
                };
                vec.data_blocks[i_block] := ?Array.init<?X>(data_block_capacity, null);
            };
        };

        let last_data_block = unwrap(vec.data_blocks[vec.i_block]);

        last_data_block[vec.i_element] := ?element;
        
        vec.i_element += 1;
        if (vec.i_element == last_data_block.size()) {
            vec.i_element := 0;
            vec.i_block += 1;
        };
    };

    func shrink_index_block_if_needed<X>(vec : Vector<X>) {
        let quarter = vec.data_blocks.size() / 4;
        if (vec.i_block < quarter) {
            vec.data_blocks := Array.tabulateVar<?[var ?X]>(quarter, func(i) {
                vec.data_blocks[i];
            });
        };
    };

    public func removeLast<X>(vec : Vector<X>) : ?X {
        if (vec.i_element == 0) {
            if (vec.i_block == 0) {
                return null;
            };
            vec.i_block -= 1;
            vec.i_element := unwrap(vec.data_blocks[vec.i_block]).size();

            shrink_index_block_if_needed(vec);

            // Keep one totally empty block when removing
            if (vec.i_block + 2 < vec.data_blocks.size()) {
                if (Option.isNull(vec.data_blocks[vec.i_block + 2])) {
                    vec.data_blocks[vec.i_block + 2] := null;
                }
            };
        };
        vec.i_element -= 1;

        var last_data_block = unwrap(vec.data_blocks[vec.i_block]);
        
        let element = last_data_block[vec.i_element];
        last_data_block[vec.i_element] := null;

        element;
    };  

    public func locate<X>(index : Nat) : (Nat, Nat) {
        // 32 super blocks have total capacity of 2^32-1 elements
        if (index >= 0xFFFFFFFF) {
            Prim.trap("Vector index in locate exceeds 32 super blocks")
        };
        let _index = Nat32.fromNat(index) + 1;
        let leadingZeros = Nat32.bitcountLeadingZero(_index);
        let (data_block_mask, element_mask, data_blocks_capacity_log, data_blocks_before) = precalc[Nat32.toNat(leadingZeros)];
        
        let data_block = (_index & data_block_mask) >> data_blocks_capacity_log;
        let index_in_data_block = _index & element_mask;

        (Nat32.toNat(data_blocks_before + data_block), Nat32.toNat(index_in_data_block));
    };

    public func get<X>(vec : Vector<X>, index : Nat) : X {
        let (a, b) = locate(index);
        if (a > vec.i_block or (a == vec.i_block and b >= vec.i_element)) {
            Prim.trap("Vector index out of bounds in get");
        };
        unwrap(unwrap(vec.data_blocks[a])[b]);
    };

    public func getOpt<X>(vec : Vector<X>, index : Nat) : ?X {
        let (a, b) = locate(index);
        if (a > vec.i_block or (a == vec.i_block and b >= vec.i_element))
            null
        else 
            unwrap(vec.data_blocks[a])[b];
    };

    public func put<X>(vec : Vector<X>, index : Nat, value : X) {
        let (a, b) = locate(index);
        if (a > vec.i_block or (a == vec.i_block and b >= vec.i_element)) {
            Prim.trap("Vector index out of bounds in put");
        };
        unwrap(vec.data_blocks[a])[b] := ?value;
    };

    public func vals<X>(vec : Vector<X>) : { next : () -> ?X } = object {
        var index = 0;
        var data_block = 0;
        var in_data_block = 0;

        public func next() : ?X {
            if (index == size(vec)) {
                return null;
            };
            let element = unwrap(vec.data_blocks[data_block])[in_data_block];
            index += 1;
            in_data_block += 1;
            if (in_data_block == unwrap(vec.data_blocks[data_block]).size()) {
                data_block += 1;
                in_data_block := 0;
            };
            element;
        };
    };

    public func toArray<X>(vec : Vector<X>) : [X] = Array.tabulate<X>(size(vec), func(i) = get(vec, i));

    public func toVarArray<X>(vec : Vector<X>) : [var X] = Array.tabulateVar<X>(size(vec), func(i) = get(vec, i));
};
