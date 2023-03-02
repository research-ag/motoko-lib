.PHONY: all clean modoc

modules := $(shell ls ../src/*.mo)

targets := $(modules:../src/%.mo=modoc/%.md)
temps := $(modules:../src/%.mo=modoc-tmp/%.md)

all: $(targets)

$(targets): modoc/%.md: modoc-tmp/%.md
	sed -e 's/ no-repl//' <$^ >$@

$(temps): modoc-tmp/%.md: ../src/%.mo
	mo-doc --source ../src --output modoc-tmp --format plain

clean:
	rm -r modoc-tmp 
