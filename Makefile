CC ?= cc
CFLAGS ?= -O2 -Wall -Wextra -std=c11

.PHONY: all clean test

all: kairo_bench

kairo_bench: bench/kairo_bench.c include/kairo_hints.h
	$(CC) $(CFLAGS) -Iinclude -o $@ bench/kairo_bench.c

test_kairo_bench: tests/test_kairo_bench.c bench/kairo_bench.c include/kairo_hints.h
	$(CC) $(CFLAGS) -pthread -Iinclude -o $@ tests/test_kairo_bench.c

test: test_kairo_bench
	./test_kairo_bench

clean:
	rm -f kairo_bench test_kairo_bench
