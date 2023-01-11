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
        let d = Nat32.fromNat(vec.i_block);
        let i = Nat32.fromNat(vec.i_element);

        // We call all data blocks of the same capacity an "epoch". We number the epochs 0,1,2,...
        // A data block is in epoch e iff the data block has capacity 2 ** e.
        // Each epoch starting with epoch 1 spans exactly two super blocks.
        // Super block s falls in epoch ceil(s/2).

        // epoch of last data block
        let e = 32 - Nat32.bitcountLeadingZero((d + 2) / 3);

        // capacity of all prior epochs combined 
        // capacity_before_e = 2 * 4 ** (e - 1) - 1

        // data blocks in all prior epochs combined
        // blocks_before_e = 3 * 2 ** (e - 1) - 2

        // then size = d * 2 ** e + i - c
        // where c = blocks_before_e * 2 ** e - capacity_before_e

        //there can be overflows, but the result is without overflows, so use addWrap and subWrap

        let c = 1 << (e << 1) -% 1 << (e + 1) +% 1;

        Nat32.toNat(d << e +% i -% c);
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
        var i_element = vec.i_element;
        if (i_element == 0) {
            grow_index_block_if_needed(vec);
            let i_block = vec.i_block;

            // When removing last we keep one more data block, so can be not null
            if (Option.isNull(vec.data_blocks[i_block])) {
                let epoch = 32 - Nat32.bitcountLeadingZero((Nat32.fromNat(i_block) + 2) / 3);
                let data_block_capacity = Nat32.toNat(1 << epoch);

                vec.data_blocks[i_block] := ?Array.init<?X>(data_block_capacity, null);
            };
        };

        let last_data_block = unwrap(vec.data_blocks[vec.i_block]);

        last_data_block[i_element] := ?element;
        
        i_element += 1;
        if (i_element == last_data_block.size()) {
            i_element := 0;
            vec.i_block += 1;
        };
        vec.i_element := i_element;
    };

    func shrink_index_block_if_needed<X>(vec : Vector<X>) {
        if (vec.i_block <= vec.data_blocks.size() / 4) {
            vec.data_blocks := Array.tabulateVar<?[var ?X]>(vec.data_blocks.size() / 2, func(i) {
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

    func locate<X>(index : Nat) : (Nat, Nat) {
        let i = Nat32.fromNat(index) +% 1;
        if (i == 0) {
            Prim.trap("Vector index out of bounds in locate");
        };
        let lz = Nat32.bitcountLeadingZero(i);
        if (lz & 1 == 0) {
            let up = (32 -% lz) >> 1;
            
            let e_mask = 1 << up -% 1;
            let b_mask = e_mask >> 1;

            (Nat32.toNat(e_mask +% b_mask +% (i >> up) & b_mask), Nat32.toNat(i & e_mask));
        } else {
            let half = (31 -% lz) >> 1;
            let mask = (1 << half) -% 1;

            (Nat32.toNat(mask << 1 +% (i >> half) & mask), Nat32.toNat(i & mask));
        };
    };

    let GET_ERROR = "Vector index out of bounds in get";

    public func get<X>(vec : Vector<X>, index : Nat) : X {
        let (a, b) = locate(index);
        if (a > vec.i_block) {
            Prim.trap(GET_ERROR);
        } else {
            switch(vec.data_blocks[a]) {
                case (null) Prim.trap(GET_ERROR);
                case (?block) {
                    switch (block[b]) {
                        case (null) Prim.trap(GET_ERROR);
                        case (?element) return element;
                    };
                };
            };
        };
    };

    public func getOpt<X>(vec : Vector<X>, index : Nat) : ?X {
        let (a, b) = locate(index);
        if (a > vec.i_block) {
            return null;
        } else {
            switch(vec.data_blocks[a]) {
                case (null) return null;
                case (?block) {
                    return block[b];
                };
            };
        };
    };

    let PUT_ERROR = "Vector index out of bounds in put";

    public func put<X>(vec : Vector<X>, index : Nat, value : X) {
        let (a, b) = locate(index);
        if (a > vec.i_block) {
            Prim.trap(PUT_ERROR);
        } else {
            switch(vec.data_blocks[a]) {
                case (null) Prim.trap(PUT_ERROR);
                case (?block) {
                    switch (block[b]) {
                        case (null) Prim.trap(PUT_ERROR);
                        case _ block[b] := ?value;
                    };
                };
            };
        };
    };

    public func vals<X>(vec : Vector<X>) : Iter.Iter<X> = object {
        var i_block = 0;
        var i_element = 0;

        public func next() : ?X {
            if (i_block >= vec.data_blocks.size()) {
                return null;
            };
            switch (vec.data_blocks[i_block]) {
                case (null) return null;
                case (?block) {
                    switch (block[i_element]) {
                        case (null) return null;
                        case (?element) {
                            i_element += 1;
                            if (i_element == block.size()) {
                                i_block += 1;
                                i_element := 0;
                            };
                            return ?element;
                        };
                    };
                };
            };
        };
    };

    public func toArray<X>(vec : Vector<X>) : [X] = Array.tabulate<X>(size(vec), func(i) = get(vec, i));

    public func toVarArray<X>(vec : Vector<X>) : [var X] = Array.tabulateVar<X>(size(vec), func(i) = get(vec, i));
};
