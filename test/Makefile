MOC=$(shell dfx cache show)
VESSEL_PKGS=$(shell vessel sources)

all: vector sha2

vector:
	$(MOC)/moc $(VESSEL_PKGS) -wasi-system-api vectorTest.mo && wasmtime vectorTest.wasm

sha2:
	$(MOC)/moc $(VESSEL_PKGS) -wasi-system-api sha2Test.mo && wasmtime sha2Test.wasm