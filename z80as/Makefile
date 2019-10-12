CC = cc
CFLAGS = -O2 -Wall

all: z80as hex2bin

z80as:	as0.o as1.o as2.o as3.o as4.o as5.o as6.o
	$(CC) -o z80as.x86 as0.o as1.o as2.o as3.o as4.o as5.o as6.o

hex2bin: hex2bin.c
	$(CC) -o hex2bin hex2bin.c

install:
	su root cp z80as.x86 /usr/local/bin/z80as

clean:
	rm -f z80as.x86 hex2bin *.o
