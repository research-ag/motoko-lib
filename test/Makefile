MOPS_PKGS=$(shell mops sources)

all: vector sha2 enumeration queue prng

vector:
	moc $(MOPS_PKGS) -wasi-system-api vector.mo && wasmtime vector.wasm

sha2:
	moc $(MOPS_PKGS) -wasi-system-api sha2.mo && wasmtime sha2.wasm

enumeration:
	moc $(MOPS_PKGS) -wasi-system-api enumeration.mo && wasmtime enumeration.wasm

queue:
	moc $(MOPS_PKGS) -wasi-system-api queue.mo && wasmtime queue.wasm

prng:
	moc $(MOPS_PKGS) -wasi-system-api prng.mo && wasmtime prng.wasm

circular_buffer:
	moc $(MOPS_PKGS) -wasi-system-api circular_buffer.mo && wasmtime circular_buffer.wasm
