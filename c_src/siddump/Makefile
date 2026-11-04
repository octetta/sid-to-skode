CC ?= gcc
CFLAGS ?= -O2 -Wall

all: siddump

siddump: siddump.c cpu.c cpu.h
	$(CC) $(CFLAGS) siddump.c cpu.c -o siddump -lm

clean:
	rm -f siddump *.o
