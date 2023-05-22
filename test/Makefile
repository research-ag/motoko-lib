MOPS_PKGS=$(shell mops sources)

all: sha2 enumeration queue circular_buffer

sha2:
	moc $(MOPS_PKGS) -wasi-system-api sha2.mo && wasmtime sha2.wasm

enumeration:
	moc $(MOPS_PKGS) -wasi-system-api enumeration.mo && wasmtime enumeration.wasm

queue:
	moc $(MOPS_PKGS) -wasi-system-api queue.mo && wasmtime queue.wasm

circular_buffer:
	moc $(MOPS_PKGS) -wasi-system-api circular_buffer.mo && wasmtime circular_buffer.wasm
