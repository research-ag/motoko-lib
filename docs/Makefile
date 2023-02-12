all: modoc/Sha256.md modoc/Sha512.md modoc/Vector.md 

modoc/Sha256.md: Sha256.md
	sed -e 's/no-repl//' <Sha256.md >modoc/Sha256.md

modoc/Sha512.md: Sha512.md
	sed -e 's/no-repl//' <Sha512.md >modoc/Sha512.md

modoc/Vector.md: Vector.md
	sed -e 's/no-repl//' <Vector.md >modoc/Vector.md

Sha256.md Sha512.md Vector.md:
	cd ..; mo-doc --format plain

clean:
	rm Sha256.md Sha512.md Vector.md index.md 