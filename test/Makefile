MOC=$(shell dfx cache show)
VESSEL_PKGS=$(shell vessel sources)

all:
	$(MOC)/moc $(VESSEL_PKGS) -wasi-system-api vectorTest.mo && wasmtime vectorTest.wasm
