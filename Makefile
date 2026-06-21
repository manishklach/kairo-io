CC ?= cc
CFLAGS ?= -O2 -Wall -Wextra -std=c11

.PHONY: all clean

all: kairo_bench

kairo_bench: bench/kairo_bench.c include/kairo_hints.h
	$(CC) $(CFLAGS) -Iinclude -o $@ bench/kairo_bench.c

clean:
	rm -f kairo_bench
