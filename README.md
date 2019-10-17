# Zapple-II
Tools for building and running Z80 code under ProDOS on an Apple II with a
Z80 Softcard (or clone)

- Z80 cross assemblers running under ProDOS on the Apple II
- CP/M BDOS emulation to allow CP/M programs to run under ProDOS
- Sample program: Processor Technology's SOL-20 BASIC/5

Aztec C v3.2 can be found [on this website](http://aztecmuseum.ca).

# Z80 Cross Assemblers & Tools
I didn't fancy writing a Z80 assembler from scratch, and I wasn't able to
find any existing Z80 cross-assemblers for 6502. In order to get something
up-and-running quickly, I searched for small Z80 assemblers written in C.

## Z80Asm

The first suitable candidate I found was `Z80Asm`, which was developed by Udo
Munk back in the 1988 to 1990 timeframe.  (Hr. Munk is still active and has
repositories here on GitHub.)  I am using an older version of Z80Asm (v1.1)
which is written in K&R (pre-ANSI) C, so it was easy to get it to compile on
Aztec C for the Apple II.

The program is rather large for Aztec C's compiler, and the resulting binary
was also too large to run in the available memory.  I made a few minor
modifications:

- I split the largest source file `z80arfun.c` into eight pieces because
  Aztec C can't handle files larger than around 500 lines.
- Slimmed down a few buffers to save some RAM.
- Reduced the number of supported files from 512 to 10.  
- I had to compile the code to Aztec C VM code using `cci` rather than to
  native 6502 code using `cc`.  The natively compiled version creates an
  executable which is too large to run.

The resulting assembler runs but it is quite slow due to the use of the Aztec
VM and can't assemble large programs with lots of symbols without running out
of memory.  However I have been using it successfully to develop the BDOS
emulation.

`Z80Asm` also builds and runs on Linux which allows larger files to be
assembled and is much faster than running on 6502 at 1Mhz.

## Z80as

Udo Munk pointed me towards an alternative assembler, `Z80as`, which was
originally developed by the Mark Williams Company and which ran on PDP-11
under Coherent.  This assembler has the advantage of small size, and is also
written in K&R C.

`Z80as` compiled 'out-of-the-box' under Aztec C on the Apple II, without any
modification.

This assembler generates Intel HEX files rather than BIN files, so I wrote a
simple converter called `HEX2BIN`.

`Z80as` also builds and runs on Linux which allows larger files to be
assembled and is much faster than running on 6502 at 1Mhz.

## HEX2BIN

This is a quick-and-dirty conversion program for converting the HEX files
generated by `Z80as` into BIN files that can be loaded on the Apple II using
`BLOAD`.

HEX files can have 'holes' in them, and `HEX2BIN` takes care of zero-filling
the holes.

# CP/M BDOS Emulation

I have started work on a CP/M BDOS emulation layer.  The plan is to add
support for all the CP/M 2.2 system calls, which should allow a CP/M program
to run on the Softcard Z80 CPU and have all the system calls routed to the
6502 and serviced using the Apple II ROM monitor routines and the ProDOS MLI.

This is at an embryonic stage at the moment as it only provides a few system
calls.  Only console I/O has been tested and confirmed to be working so far:

- BDOS call 00h: `C_TERMCPM` - System reset
- BDOS call 01h: `C_READ` - Console input
- BDOS call 02h: `C_WRITE` - Console output
- BDOS call 06h: `C_RAWIO` - Direct console I/O
- BDOS call 07h: `GET_IOB` - Get IOBYTE
- BDOS call 08h: `SET_IOB` - Get IOBYTE
- BDOS call 09h: `C_WRITESTR` - Console write string
- BDOS call 0Ah: `C_READSTR` - Read console string
- BDOS call 0Bh: `C_STAT` - Console status
- BDOS call 0Ch: `S_BDOSVER` - Return version number
- BDOS call 0Dh: `DRV_ALLRESET` - Reset disks
- BDOS call 0Eh: `DRV_SET` - Select disk
- BDOS call 0FH: `F_OPEN` - Open file (IN PROGRESS)
- BDOS call 10H: `F_CLOSE` - Close file (IN PROGRESS)
- BDOS call 13H: `F_DELETE` - Delete file
- BDOS call 14h: `F_READ` - Read file sequentially
- BDOS call 15h: `F_WRITE` - Write file sequentially
- BDOS call 16H: `F_MAKE` - Create (and open) file (IN PROGRESS)
- BDOS call 17H: `DRV_LOGVEC`- Return bitmap of logged-in drives
- BDOS call 19H: `DRV_GET` - Return current drive
- BDOS call 1AH: `F_DMAOFF` - Set DMA address
- BDOS call 1CH: `DRV_SETRO` - Software write-protect current drive
- BDOS call 1DH: `DRV_ROVEC` - Return bitmap of read-only drives
- BDOS call 20H: `F_USERNUM` - Get/set user number
- BDOS call 22H: `F_SIZE` - Compute file size
- BDOS call 25H: `DRV_RESET` - Selectively reset disk drives

There are two parts to the BDOS emulation:

- `softcard80.asm` - This is the Z80 code to handle BDOS calls and send them
  to the 6502 to be processed.  Written in Z80 assembler.  I am currently
  assembling this using `Z80asm` under Linux (it got too large to assemble
  with `Z80asm` under ProDOS on the Apple II.
- `softcard65.asm` - This is the 6502 back end code.  Written in Merlin8 v2.58.
  Loads at $0900 in 6502 space.

# Sample Programs

## BASIC/5

This is one of the BASIC interpreters from the Processor Technologies SOL-20
system.  The source code was provided as an example with z80as.

I assembled this code under `Z80as` on Linux, since it defines too many
symbols to assemble natively on the Apple II in the available memory.  I plan
to take a look at the Aztec C build configuration to see if it is possible
to find more memory for dynamic allocation (ie: `malloc()`).

It is a 5K BASIC, so it is rather primitive.  However it does have a floating
point package and trig functions.

BASIC/5 only uses three system calls: `C_READ`, `C_WRITE` and `C_STATUS`.

There is currently no support for loading or saving BASIC programs, but I may
add this later.

The manual for BASIC/5 is included in this GitHub repo, in PDF format.

Interestingly, there was a bug in the original BASIC/5 source that caused it
to initialize one byte of memory too many, blowing away the first byte of the
BDOS implementation at the top of memory.  This has been patched by adding a
`DEC HL` instuction at line 47 (shout-out to Qkumba for finding what the
issue was!)

The EXEC file `RUNBASIC5` can be used to start BASIC/5.

## DDT 8080 Debugger (from CP/M 2.2)

We have enough BDOS calls to get this to work now!

The EXEC file `RUNDDT` can be used to start DDT.

## ZSID v1.4 Z80 Debugger (from CP/M 2.2)

We have enough BDOS calls to get this to work now!

The EXEC file `RUNZSID` can be used to start ZSID.

# How to Build the Code

You don't really need to build the code unless you want to make changes.
Pre-compiled versions of everything are included in this repository.

The 800K ProDOS disk image `zapple2.po` has all the files you should need.

## Building `Z80asm` using Aztec C

- Two scripts are provided to do the build: `compile` and `link`
- Run the script `compile`.  This takes a long time!
- Run the script `link`.  This just takes a couple of minutes.
- `z80asm` executable is created.

Note that `z80asm` can only be run from the Aztec C shell.  It should be
possible to build it as a normal ProDOS application, but I have not done this
yet.
 
## Building `Z80as` using Aztec C

I didn't provide a script for this.  Just build all the C files in Aztec C
as follows:

```
cc as0.c
cc as1.c
cc as2.c
cc as3.c
cc as4.c
cc as5.c
cc as6.c
ln -o z80as as0.o as1.o as2.o as3.0 as4.0 as5.0 as6.0 -lc
```
## Building `HEX2BIN` using Aztec C

- You can just run the script `makeh2b` in Aztec C
- This just does the following:

```
cc hex2bin.c
ln hex2bin.o -lc
```

## Building `SOFTCARD65` using Merlin8 2.58

- Start Merlin8 (v2.58)
- Hit 'D' for disk commands, enter `PREFIX /ZAPPLE2`
- Hit 'L' for load, enter `SOFTCARD65` and hit return.
- Hit 'E' for edit.
- Type `ASM` to assemble.
- Type 'Q' to go to the main menu.
- Hit 'O' to save the object file `SOFTCARD65` to disk, and hit return.
- Hit 'Q' to quit to ProDOS.

## Building `SOFTCARD80.BIN` using `Z80asm`

- In the Aztec C shell, enter the following commands:
- `cd /zapple2`
- `z80asm softcard80.asm` 

*Update:* The code has grown too large to build natively on the Apple II. I
have been using `z80asm` under Linux instead.

# How to Run The Code

The code assumes a Z80 Softcard (or clone) in slot 4.  This can be changed
by modifying the `SOFTCARD` address in `SOFTCARD65.S` and `SOFTCARD80.ASM`
if your card is in a different slot.

I provided a couple of ProDOS EXEC files to load all the pieces and run the
code:

`RUNBASIC5` performs the following operations:

```
BLOAD /ZAPPLE2/SOFTCARD80.BIN,A$FFD,Ttxt
BLOAD /ZAPPLE2/BASIC5.BIN,A$1100,T$00
BRUN /ZAPPLE2/SOFTCARD65
```

A little explanation is in order:

- The first line loads the Z80 code which provides the CP/M BDOS interface.
  It is loaded at address $0FFD because there is a three byte prefix on the
  BIN file (created by Z80asm).  The actual start address is $1000 in 6502
  address space, which is 0000H for the Z80.
- The second line loads the BASIC5 image at $1100 (0100H for the Z80).
- Finally we just run the 6502 code in `SOFTCARD65` to bootstrap the process.
  This loads at $0900.  The start address is encoded in the binary, so we
  don't need to specify it on loading/running the code.

The other EXEC file `RUNTESTSTUB` is the same, but omits the second step.
Instead of running BASIC, it runs some internal test code that is part of
`SOFTCARD80.BIN`.



