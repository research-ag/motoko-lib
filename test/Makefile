MOC=$(shell vessel bin)/moc
VESSEL_PKGS=$(shell vessel sources)

all: vector sha2 enumeration queue

vector:
	$(MOC) $(VESSEL_PKGS) -wasi-system-api vector.mo && wasmtime vector.wasm

sha2:
	$(MOC) $(VESSEL_PKGS) -wasi-system-api sha2.mo && wasmtime sha2.wasm

enumeration:
	$(MOC) $(VESSEL_PKGS) -wasi-system-api enumeration.mo && wasmtime enumeration.wasm

queue:
	$(MOC) $(VESSEL_PKGS) -wasi-system-api queue.mo && wasmtime queue.wasm
