MOC=$(shell vessel bin)/moc
VESSEL_PKGS=$(shell vessel sources)

all: vector sha2 enumeration queue prng-seiran128 prng-sfc

vector:
	$(MOC) $(VESSEL_PKGS) -wasi-system-api vector.mo && wasmtime vector.wasm

sha2:
	$(MOC) $(VESSEL_PKGS) -wasi-system-api sha2.mo && wasmtime sha2.wasm

enumeration:
	$(MOC) $(VESSEL_PKGS) -wasi-system-api enumeration.mo && wasmtime enumeration.wasm

queue:
	$(MOC) $(VESSEL_PKGS) -wasi-system-api queue.mo && wasmtime queue.wasm

prng-seiran128:
	$(MOC) $(VESSEL_PKGS) -wasi-system-api prng-seiran128.mo && wasmtime prng-seiran128.wasm

prng-sfc:
	$(MOC) $(VESSEL_PKGS) -wasi-system-api -r prng-sfc.mo #&& wasmtime prng-sfc.wasm
