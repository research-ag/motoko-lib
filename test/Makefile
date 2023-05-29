MOPS_PKGS=$(shell mops sources)

all: sha2 enumeration queue circular_buffer

sha2:
	moc $(MOPS_PKGS) -wasi-system-api sha2.test.mo && wasmtime sha2.test.wasm

enumeration:
	moc $(MOPS_PKGS) -wasi-system-api enumeration.test.mo && wasmtime enumeration.test.wasm

queue:
	moc $(MOPS_PKGS) -wasi-system-api queue.test.mo && wasmtime queue.test.wasm

circular_buffer:
	moc $(MOPS_PKGS) -wasi-system-api circular_buffer.test.mo && wasmtime circular_buffer.test.wasm
