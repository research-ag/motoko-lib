#!/usr/local/bin/ic-repl

let id = call ic.provisional_create_canister_with_cycles(record { settings = null; amount = null });
call ic.install_code(
    record {
        arg = encode ();
        wasm_module = file("../.dfx/local/canisters/sha2_bench/sha2_bench.wasm");
        mode = variant { install };
        canister_id = id.canister_id;
    },
);
let canister = id.canister_id;
call canister.profile32();
call canister.profile64();
call canister.profile_state();