MOC=moc
VESSEL_PKGS=$(shell vessel sources)

all: vector sha2 rbtree enumeration

vector:
	$(MOC) $(VESSEL_PKGS) -wasi-system-api vectorTest.mo && wasmtime vectorTest.wasm

sha2:
	$(MOC) $(VESSEL_PKGS) -wasi-system-api sha2Test.mo && wasmtime sha2Test.wasm

rbtree:
	$(MOC) $(VESSEL_PKGS) -wasi-system-api RBTreeTest.mo && wasmtime RBTreeTest.wasm

enumeration:
	$(MOC) $(VESSEL_PKGS) -wasi-system-api EnumerationTest.mo && wasmtime EnumerationTest.wasm
