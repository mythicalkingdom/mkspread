FPC   = fpc
FLAGS = -Mobjfpc -Sh -O2 -Fusrc -FEbuild -FUbuild
SRCS  = $(wildcard src/*.pas)

all: build/mkspread

build/mkspread: $(SRCS)
	$(FPC) $(FLAGS) src/mkspread.pas

build/test_core: $(SRCS) tests/test_core.pas
	$(FPC) $(FLAGS) tests/test_core.pas

run: all
	./build/mkspread

demo: all
	./build/mkspread --demo

test: build/test_core all
	./build/test_core
	python3 tests/ui_test.py

clean:
	rm -f build/*
	touch build/.gitkeep

.PHONY: all run demo test clean
