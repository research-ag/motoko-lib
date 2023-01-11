#!/usr/local/bin/ic-repl

let id = call ic.provisional_create_canister_with_cycles(record { settings = null; amount = null });
call ic.install_code(
    record {
        arg = encode ();
        wasm_module = file(".dfx/local/canisters/bench_canister/bench_canister.wasm");
        mode = variant { install };
        canister_id = id.canister_id;
    },
);
let canister = id.canister_id;
call canister.profile_vector();
call canister.profile_buffer();
call canister.profile_array();
