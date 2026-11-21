FPC   = fpc
FLAGS = -Mobjfpc -Sh -O2

all: build/mkspread

build/mkspread: src/mkspread.pas
	$(FPC) $(FLAGS) -FEbuild -FUbuild $<

run: all
	./build/mkspread

demo: all
	./build/mkspread demo

clean:
	rm -f build/*

.PHONY: all run demo clean
