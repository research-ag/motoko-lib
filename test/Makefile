MOPS_PKGS=$(shell mops sources)

all: queue circular_buffer

queue:
	moc $(MOPS_PKGS) -wasi-system-api queue.mo && wasmtime queue.wasm

circular_buffer:
	moc $(MOPS_PKGS) -wasi-system-api circular_buffer.mo && wasmtime circular_buffer.wasm
