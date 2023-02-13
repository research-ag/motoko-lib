.PHONY: all clean modoc

modules := $(shell ls ../src/*.mo)

targets := $(modules:../src/%.mo=modoc/%.md)
temps := $(modules:../src/%.mo=%.md)

all: $(targets)

$(targets): modoc/%.md: %.md
	sed -e 's/no-repl//' <$^ >$@

$(temps): %.md: ../src/%.mo
	cd ..; mo-doc --format plain

clean:
	rm Sha256.md Sha512.md Vector.md index.md 