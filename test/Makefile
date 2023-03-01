MOC=$(shell vessel bin)/moc
VESSEL_PKGS=$(shell vessel sources)

all: vector sha2 enumeration queue

vector:
	$(MOC) $(VESSEL_PKGS) -wasi-system-api vectorTest.mo && wasmtime vectorTest.wasm

sha2:
	$(MOC) $(VESSEL_PKGS) -wasi-system-api sha2Test.mo && wasmtime sha2Test.wasm

enumeration:
	$(MOC) $(VESSEL_PKGS) -wasi-system-api EnumerationTest.mo && wasmtime EnumerationTest.wasm

queue:
	$(MOC) $(VESSEL_PKGS) -wasi-system-api queueTest.mo && wasmtime queueTest.wasm
