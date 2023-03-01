MOC=$(shell vessel bin)/moc
VESSEL_PKGS=$(shell vessel sources)

all: vector sha2 enumeration

vector:
	$(MOC) $(VESSEL_PKGS) -wasi-system-api vectorTest.mo
	wasmtime run vectorTest.wasm

sha2:
	$(MOC) $(VESSEL_PKGS) -wasi-system-api sha2Test.mo
	wasmtime run sha2Test.wasm

enumeration:
	$(MOC) $(VESSEL_PKGS) -wasi-system-api EnumerationTest.mo
	wasmtime run EnumerationTest.wasm
