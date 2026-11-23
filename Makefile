FPC   = fpc
FLAGS = -Mobjfpc -Sh -O2 -Fusrc -FEbuild -FUbuild
SRCS  = $(wildcard src/*.pas)

all: build/mkspread

build/mkspread: $(SRCS)
	$(FPC) $(FLAGS) src/mkspread.pas

build/test_core: $(SRCS) tests/test_core.pas
	$(FPC) $(FLAGS) tests/test_core.pas

build/test_samples: $(SRCS) tests/test_samples.pas
	$(FPC) $(FLAGS) tests/test_samples.pas

build/make_testsheet: $(SRCS) tests/make_testsheet.pas
	$(FPC) $(FLAGS) tests/make_testsheet.pas

testsheet: build/make_testsheet
	mkdir -p private-samples
	./build/make_testsheet private-samples/MKTEST.WK1
	for n in 1 2 3 4 5 6 7 8 9; do ./build/make_testsheet private-samples/MKT$$n.WK1 $$n > /dev/null; done

build/make_macrosheet: $(SRCS) tests/make_macrosheet.pas
	$(FPC) $(FLAGS) tests/make_macrosheet.pas

build/make_datasheet: $(SRCS) tests/make_datasheet.pas
	$(FPC) $(FLAGS) tests/make_datasheet.pas

datasheet: build/make_datasheet
	mkdir -p private-samples
	./build/make_datasheet private-samples/DATA.WK1

macrosheet: build/make_macrosheet
	mkdir -p private-samples
	./build/make_macrosheet private-samples/MACROS.WK1

run: all
	./build/mkspread

demo: all
	./build/mkspread --demo

test: build/test_core build/test_samples all
	./build/test_core
	./build/test_samples
	python3 tests/ui_test.py

clean:
	rm -f build/*
	touch build/.gitkeep

.PHONY: all run demo test testsheet macrosheet datasheet clean
