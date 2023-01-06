import Prim "mo:⛔";
import Buffer "mo:base/Buffer";
import Nat32 "mo:base/Nat32";
import Nat "mo:base/Nat";
import Debug "mo:base/Debug";
import Array "mo:base/Array";
import Option "mo:base/Option";

module {
    let INTERNAL_ERROR = "Internal error in Vector";

    func unwrap<X>(x : ?X) : X {
        switch (x) {
            case (null) Prim.trap(INTERNAL_ERROR);
            case (?value) value;
        };
    };

    public type Vector<X> = {
        var size : Nat;
        var data_blocks : [var ?[var ?X]];
        var data_blocks_size : Nat;
        var last_block_size : Nat;
        var super_block_odd : Bool;
        var super_block_size : Nat;
        var super_block_capacity : Nat;
        var data_block_capacity : Nat;
        precalc: [(Nat32, Nat32, Nat32, Nat32)];
    };

    public func precalc() : [(Nat32, Nat32, Nat32, Nat32)] = Array.tabulate<(Nat32, Nat32, Nat32, Nat32)>(32, func (leadingZeros) {
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

    func blocks_from_capacity<X>(precalc : [(Nat32, Nat32, Nat32, Nat32)], initCapacity : Nat) : [var ?[var ?X]] {
        let (data_block, _) = locate(precalc, initCapacity - 1);
        var data_blocks = Array.init<?[var ?X]>(data_block + 1, null);
        var super_block = Nat32.fromNat(0);
        var last = 0;
        while (((1 << super_block) - 1) < Nat32.fromNat(initCapacity)) {
            let capacity = Nat32.toNat(1 << (super_block - (super_block >> 1)));
            let count = Nat32.toNat(1 << (super_block >> 1));

            var i = 0;
            while (i < count and last < data_blocks.size()) {
                data_blocks[last] := ?Array.init<?X>(capacity, null);
                i += 1;
                last += 1;
            };

            super_block += 1;
        };
        data_blocks;
    };

    public func init<X>(initCapacity : Nat, precalc : [(Nat32, Nat32, Nat32, Nat32)]) : Vector<X> = {
        var size = 0;
        var data_blocks = blocks_from_capacity(precalc, Nat.max(1, initCapacity));
        var data_blocks_size = 1;
        var last_block_size = 0;
        var super_block_odd = false;
        var super_block_size = 1;
        var super_block_capacity = 1;
        var data_block_capacity = 1;
        precalc = precalc;
    };

    public func clear<X>(vec : Vector<X>) {
        let empty = init<X>(0, vec.precalc);
        vec.size := empty.size;
        vec.data_blocks := empty.data_blocks;
        vec.data_blocks_size := empty.data_blocks_size;
        vec.last_block_size := empty.last_block_size;
        vec.super_block_odd := empty.super_block_odd;
        vec.super_block_size := empty.super_block_size;
        vec.super_block_capacity := empty.super_block_capacity;
        vec.data_block_capacity := empty.data_block_capacity;
    };

    public func clone<X>(vec : Vector<X>) : Vector<X> = {
        var size = vec.size;
        var data_blocks = Array.tabulateVar<?[var ?X]>(
            vec.data_blocks.size(),
            func (i) = Option.map(
                vec.data_blocks[i],
                func(block : [var ?X]) : [var ?X] = Array.tabulateVar<?X>(block.size(), func(j) = block[j])
            )
        );
        var data_blocks_size = vec.data_blocks_size;
        var last_block_size = vec.last_block_size;
        var super_block_odd = vec.super_block_odd;
        var super_block_size = vec.super_block_size;
        var super_block_capacity = vec.super_block_capacity;
        var data_block_capacity = vec.data_block_capacity;
        precalc = vec.precalc;
    };

    public func size<X>(vec : Vector<X>) : Nat = vec.size;

    func add_super_block_if_needed<X>(vec : Vector<X>) {
        if (vec.super_block_size == vec.super_block_capacity) {
            if (vec.super_block_odd) {
                vec.super_block_capacity *= 2;
            } else {
                vec.data_block_capacity *= 2;
            };
            vec.super_block_odd := not vec.super_block_odd;
            vec.super_block_size := 0;
        };
    };

    func grow_index_block_if_needed<X>(vec : Vector<X>) {
        if (vec.data_blocks.size() == vec.data_blocks_size) {
            vec.data_blocks := Array.tabulateVar<?[var ?X]>(vec.data_blocks_size * 2, func(i) {
                if (i < vec.data_blocks_size) {
                    vec.data_blocks[i];
                } else {
                    null
                }
            });
        }
    };

    func add_data_block_if_needed<X>(vec : Vector<X>) {
        if (vec.data_block_capacity == vec.last_block_size) {
            add_super_block_if_needed(vec);
            grow_index_block_if_needed(vec);

            if (Option.isNull(vec.data_blocks[vec.data_blocks_size])) {
                vec.data_blocks[vec.data_blocks_size] := ?Array.init<?X>(vec.data_block_capacity, null);
            };

            vec.last_block_size := 0;
            vec.data_blocks_size += 1;
            vec.super_block_size += 1;
        };
    };

    public func add<X>(vec : Vector<X>, element : X) {
        add_data_block_if_needed(vec);

        var last_data_block = unwrap(vec.data_blocks[vec.data_blocks_size - 1]);

        last_data_block[vec.last_block_size] := ?element;
        vec.last_block_size += 1;
        vec.size += 1;
    };

    func remove_super_block_if_needed<X>(vec : Vector<X>) {
        if (vec.super_block_size == 0) {
            vec.super_block_odd := not vec.super_block_odd;
            if (vec.super_block_odd) {
                vec.super_block_capacity /= 2;
            } else {
                vec.data_block_capacity /= 2;
            };
            vec.super_block_size := vec.super_block_capacity;
        };
    };

    func shrink_index_block_if_needed<X>(vec : Vector<X>) {
        let quarter = vec.data_blocks.size() / 4;
        if (vec.data_blocks_size <= quarter) {
            vec.data_blocks := Array.tabulateVar<?[var ?X]>(quarter, func(i) {
                vec.data_blocks[i];
            });
        };
    };

    public func remove_data_block_if_needed<X>(vec : Vector<X>) {
        if (vec.last_block_size == 0) {
            if (vec.data_blocks_size < vec.data_blocks.size() and not Option.isNull(vec.data_blocks[vec.data_blocks_size])) {
                vec.data_blocks[vec.data_blocks_size] := null;
            };

            shrink_index_block_if_needed(vec);
            if (vec.data_blocks_size > 1) {
                vec.super_block_size -= 1;
                remove_super_block_if_needed(vec);
                
                vec.data_blocks_size -= 1;
                vec.last_block_size := vec.data_block_capacity;
            }
        };
    };

    public func removeLast<X>(vec : Vector<X>) : ?X {
        if (vec.size == 0) { 
            return null;
        };

        var last_data_block = unwrap(vec.data_blocks[vec.data_blocks_size - 1]);
        vec.size -= 1;
        vec.last_block_size -= 1;
        let element = last_data_block[vec.last_block_size];
        last_data_block[vec.last_block_size] := null;

        remove_data_block_if_needed(vec);

        element;
    };

    public func locate<X>(precalc : [(Nat32, Nat32, Nat32, Nat32)], index : Nat) : (Nat, Nat) {
        let _index = Nat32.fromNat(index) + 1;
        let leadingZeros = Nat32.bitcountLeadingZero(_index);
        let (data_block_mask, element_mask, data_blocks_capacity_log, data_blocks_before) = precalc[Nat32.toNat(leadingZeros)];
        
        let data_block = (_index & data_block_mask) >> data_blocks_capacity_log;
        let index_in_data_block = _index & element_mask;

        (Nat32.toNat(data_blocks_before + data_block), Nat32.toNat(index_in_data_block));
    };

    public func get<X>(vec : Vector<X>, index : Nat) : X {
        if (index >= vec.size) {
            Prim.trap("Vector index out of bounds in get");
        };
        let (a, b) = locate(vec.precalc, index);
        unwrap(unwrap(vec.data_blocks[a])[b]);
    };

    public func getOpt<X>(vec : Vector<X>, index : Nat) : ?X {
        if (index < vec.size) {
            let (a, b) = locate(vec.precalc, index);
            unwrap(vec.data_blocks[a])[b];
        } else {
            null;
        };
    };

    public func put<X>(vec : Vector<X>, index : Nat, value : X) {
        if (index >= vec.size) {
            Prim.trap("Vector index out of bounds in get");
        };
        let (a, b) = locate(vec.precalc, index);
        unwrap(vec.data_blocks[a])[b] := ?value;
    };

    public func vals<X>(vec : Vector<X>) : { next : () -> ?X } = object {
        var index = 0;
        var data_block = 0;
        var in_data_block = 0;

        public func next() : ?X {
            if (index == vec.size) {
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

    public func toArray<X>(vec : Vector<X>) : [X] = Array.tabulate<X>(vec.size, func(i) = get(vec, i));

    public func toVarArray<X>(vec : Vector<X>) : [var X] = Array.tabulateVar<X>(vec.size, func(i) = get(vec, i));
};
