MOC=moc
VESSEL_PKGS=$(shell vessel sources)

all: vector sha2

vector:
	$(MOC) $(VESSEL_PKGS) -wasi-system-api vectorTest.mo && wasmtime vectorTest.wasm

sha2:
	$(MOC) $(VESSEL_PKGS) -wasi-system-api sha2Test.mo && wasmtime sha2Test.wasm