***************************************************
* 6502 code to invoke Z80 routine on Softcard and
* handle calls from Z80 back to 6502
* Assumes Softcard in slot 4
* Bobbi 2019
***************************************************

 ORG $2000  ; System program
 TYP $FF  ; .SYS

SFTCRD EQU $C400 ; Softcard in slot 4
CMD EQU $06 ; ZP address for command code (0,1,2)
AREG EQU $07 ; Pass 6502 A reg to/from Z80
XREG EQU $08 ; Pass 6502 X reg to/from Z80
YREG EQU $09 ; Pass 6502 Y reg to/from Z80
ADDR EQU $EB ; Pass address of 6502 routine to call from Z80
ADDRH EQU $EC ; High byte of address ADDR
FLAGS EQU $ED ; Pass 6502 flags to/from Z80

* 80-column text page 1, direct main/aux video access.
* No Apple II monitor or 80-column firmware routines are called.
* Public entry vectors are fixed at B803, B806, B809.

IOBUF EQU $0800 ; 1K ProDOS OPEN buffer in unused text page 2.
                 ; The extended video driver now uses B800-BEFF.
                 ; This does not overlap Z80's A800-B7FF I/O buffers.
LDADDR EQU $0FFD ; Load to $1000 hex
   ; (Accounting for 3 byte prefix)
LDLEN  EQU  $FFFF ; Load it all

STADDR EQU  $B800  ; Code will be relocated to this addr

* Code to relocate everything from RELOC_ST to RELOC_EN
* To begin at STADDR
* ZP $06-07 is source pointer
* ZP $08-09 is dest pointer
 LDA #<RELOC_ST ;
 STA $06 ; source LSB
 LDA #>RELOC_ST ;
 STA $07 ; source MSB
 LDA #<STADDR ;
 STA $08 ; dest LSB
 LDA #>STADDR ;
 STA $09 ; dest MSB
 LDY #0 ;
:LDRL1 LDA ($06),Y ; Copy a byte
 STA ($08),Y ;
 INC $06 ; source LSB
 BNE :LDRS1 ; If no rollover
 INC $07 ; inc source MSB
:LDRS1 INC $08 ; dest LSB
 BNE :LDRS2 ; If no rollover
 INC $09 ; inc dest MSB
:LDRS2 LDA $09 ; dest MSB
 CMP #>RELOC_EN ; at end?
 BNE :LDRL1 ; Nope. Loop
 LDA $08 ; dest LSB
 CMP #<RELOC_EN ; at end?
 BNE :LDRL1 ; Nope. Loop

 JMP STADDR ; Jump to reloc'd code


RELOC_ST
 ORG STADDR ; Assemble for this origin

* Fixed entry vectors for Z80 calls via CMD=1 / ADDR.
* B800 is the loader's entry, B803 output, B806 input, B809 bell.
 JMP ENTRY
 JMP VPUT
 JMP VGET
 JMP VBELL

ENTRY JSR VINIT ; Initialize video hardware and clear screen
 JSR PRWELC ; Print welcome message
 LDA #$00 ; Clear ProDOS system bitmap
 LDX #$00 ;
:L1 STA $BF58,X ;
 INX  ;
 CPX #21 ;
 BNE :L1 ;
 JSR OP ; Open file
 BEQ :S1 ; If zero, no error
 JSR PRBYTE ; Print error code
 JSR PROPERR ; Print "open error"
 JMP DONE ; Quit
:S1 LDA OP_N ; Get file ref num
 STA RD_N ; Store it for READ
 JSR RD ; Read file
 BEQ :S2 ; If zero, no error
 JSR PRBYTE ; Print error code
 JSR PRRDERR ; Print "read error"
 JMP DONE ; Quit
:S2 LDA RD_TC+1 ; MSB
 JSR PRBYTE ; Print it
 LDA RD_TC ; LSB
 JSR PRBYTE ; Print it
 JSR CROUT ; ...
 JSR CL ; Close file
 JSR PRSUCC ; Print success message

MAINLOOP
 STA SFTCRD ; Pause Z80, resume 6502
 JSR HANDLR ; Handle calls made by Z80 code
 JMP MAINLOOP ; Keep on keeping on
DONE
 BRK  ; Drop to monitor

* Pointer to message is in ZP $06-$07
* Uses ZP $08 as temporary
PRMSG LDY #0 ; Initialize index
 LDA ($06),Y ; Length of string
 STA $08 ; Store length in temp
:L1 INY  ; Advance char pointer
 LDA ($06),Y ; Get char
 TYA ; VPUT uses Y for video column
 PHA ; Save PRMSG string index
 JSR VPUT ; Print it
 PLA ; Restore string index
 TAY
 DEC $08 ; Decrement bytes remaining
 BNE :L1 ; Loop
 RTS  ;

* Print welcome message
PRWELC LDA #<WELCOME ;
 STA $06 ;
 LDA #>WELCOME ;
 STA $07 ;
 JSR PRMSG ;
 JSR CROUT ;
 RTS  ;

* Print "open error"
PROPERR LDA #<OPERR ;
 STA $06 ;
 LDA #>OPERR ;
 STA $07 ;
 JSR PRMSG ;
 LDA #<PATH ;
 STA $06 ;
 LDA #>PATH ;
 STA $07 ;
 JSR PRMSG ;
 JSR CROUT ;
 RTS  ;

* Print "can't read"
PRRDERR LDA #<RDERR ;
 STA $06 ;
 LDA #>RDERR ;
 STA $07 ;
 JSR PRMSG ;
 JSR CROUT ;
 RTS  ;

* Print "Loaded"
PRSUCC LDA #<PATH ;
 STA $06 ;
 LDA #>PATH ;
 STA $07 ;
 JSR PRMSG ;
 LDA #<SUCCMSG ;
 STA $06 ;
 LDA #>SUCCMSG ;
 STA $07 ;
 JSR PRMSG ;
 JSR CROUT ;
 RTS

* File to load
PATH STR "SOFTCARD80.BIN"
;PAYLOAD STR "MBASIC.COM"
PAYLOAD STR "NSWEEP.COM"

* Messages
WELCOME STR "Zapple-II Loader"
OPERR STR ": Can't open "
RDERR STR ": Read error"
SUCCMSG STR " loaded"

* ProDOS Parameter List for OPEN
OP JSR $BF00 ; ProDOS call
 DB $C8 ; OPEN
 DW OP_PL ; Pointer to parm list
 RTS  ;
OP_PL DB 3 ; Start of param list; 3 parameters
OP_FP DW PATH ; Pointer to file path
OP_FBL DW IOBUF ; Pointer to I/O buffer
OP_N DB 0 ; File reference number

* ProDOS Parameter List for OPEN (for the payload)
OPPL JSR $BF00 ; ProDOS call
 DB $C8 ; OPEN
 DW OPPL_PL ; Pointer to parm list
 RTS
OPPL_PL DB 3 ; Start of param list; 3 parameters
OPPL_FP DW PAYLOAD ; Pointer to payload path
OPPL_FBL DW IOBUF ; Pointer to I/O buffer
OPPL_N DB 0 ; File reference number

* ProDOS Parameter List for READ
RD JSR $BF00 ; ProDOS call
 DB $CA ; READ
 DW RD_PL ; Pointer to parm list
 RTS  ;
RD_PL DB 4 ; Start of param list; 4 parameters
RD_N DB 0 ; File reference number
RD_DB DW LDADDR ; Data buffer LSB
RD_RC DW LDLEN ; Request count LSB
RD_TC DW $0000 ; Trans count LSB

* ProDOS Parameter List for READ
RDPL JSR $BF00 ; ProDOS call
 DB $CA ; READ
 DW RDPL_PL ; Pointer to parm list
 RTS
RDPL_PL DB 4 ; Start of param list; 4 parameters
RDPL_N DB 0 ; File reference number
RDPL_DB DW $1100 ; Data buffer LSB
RDPL_RC DW LDLEN ; Request count LSB
RDPL_TC DW $0000 ; Trans count LSB

* ProDOS Parameter List for CLOSE
CL JSR $BF00 ; ProDOS call
 DB $CC ; CLOSE
 DW CL_PL ; Pointer to parm list
 RTS
CL_PL DB 1 ; Start of param list; 1 parameter
CL_N DB 0 ; File ref num (0 close all)

* Handle calls made by Z80 code
HANDLR LDA CMD
 CMP #0 ; CMD=0 means continue running 6502 code
 BNE :CMD1 ;
 PLA  ; Clean up stack
 PLA  ; ...
 JMP DONE ; Continue main 6502 routine
:CMD1 CMP #1 ; CMD=1 means call 6502 routine then return to Z80
 BNE :CMD2 ;
 LDA FLAGS ; Load the flags
 PHA  ; Use stack to move A to status
 PLP  ; ...
 LDA AREG ; Load the registers
 LDX XREG ; ...
 LDY YREG ; ...
 JSR :DOJMP ; Hack to achieve an indirect JSR
 STA AREG ; Store the registers
 STX XREG ; ...
 STY YREG ; ...
 PHP  ; Move status to A via the stack
 PLA  ;
 STA FLAGS ; Store the flags
 RTS  ; Will go back to Z80
:CMD2 CMP #2 ; CMD=2 means call ProDOS MLI then return to Z80
 BNE :CMD3 ;
 JSR :DOJMP ; ProDOS MLI call
 STA AREG ; Store return code
 RTS  ; Will go back to Z80
:CMD3 CMP #3 ; CMD=3 means peek at the keyboard then ret to Z80
 BNE :CMD4 ;
 BIT $C000 ; Peek at the keyboard status
 BMI :C3YES ; Branch if keystroke available
 LDA #0 ; If no chars, return 0 in AREG
 JMP :C3DONE ; ...
:C3YES LDA #1 ; Otherwise return 1 in AREG
:C3DONE STA AREG ; Store the value for the Z80
 RTS  ; Go back to Z80
:CMD4 JSR VBELL ; Beep for error
 BRK  ; And drop into monitor
:DOJMP JMP (ADDR) ;


***************************************************
* Minimal direct 80-column console for enhanced Apple //e
*
* Video page 1: 0400-07FF in both main and auxiliary RAM.
* Physical column 0,2,... = auxiliary, 1,3,... = main.
* Every row has 40 bytes in each bank, with Apple II row interleave.
* We temporarily enable 80STORE and use PAGE2 to choose bank,
* then restore PAGE1 and 80STORE OFF for ProDOS and SoftCard.
* NEVER leave an auxiliary bank selected across a handoff.
*
* VPUT:  A = 7-bit ASCII or high-bit-set Apple character
* VGET:  waits for a key, returns high-bit-set ASCII in A;
*        cursor is a temporary inverse of the character underneath.
* VBELL: speaker click
*
* The initial terminal dialect is deliberately minimal:
* printables, CR (new line), LF ignored (CR already moves down),
* BS, TAB (8-col stops), ^L clear screen, ^Y cursor home.
* Add full Videx cursor positioning later if required.
***************************************************

VINIT
 LDA #0
 STA $C000 ; 80STORE off (write-only switch)
 STA $C002 ; RAMRD off: main RAM reads
 STA $C004 ; RAMWRT off: main RAM writes
 BIT $C054 ; PAGE1 (read/write switch)
 BIT $C051 ; TEXT on
 BIT $C052 ; full screen, MIXED off
 STA $C00D ; 80COL on (write-only switch)
 STA $C00F ; alternate character set, lowercase support
 JMP VCLEAR ; Clear screen, row=0 and column=0

* Character output. Ignores 7th-bit Apple video encoding on input.
VPUT AND #$7F
 CMP #$20
 BCS VPRINT
 CMP #$0D
 BEQ VCR
 CMP #$0A
 BEQ VDONE ; LF ignored; CR already advances a row
 CMP #$08
 BEQ VBACK
 CMP #$09
 BEQ VTAB
 CMP #$0C
 BNE :VCTL1
 JMP VCLEAR
:VCTL1 CMP #$19
 BEQ VHOME
VDONE RTS

VHOME LDA #0
 STA VCOL
 STA VROW
 RTS

VCR LDA #0
 STA VCOL
 JMP VDOWN

VBACK LDA VCOL
 BEQ VDONE
 DEC VCOL
 RTS

VTAB LDA VCOL
 AND #7
 EOR #7
 CLC
 ADC #1
 STA VTCNT
:VT1 LDA #' '
 JSR VPRINT
 DEC VTCNT
 BNE :VT1
 RTS

VPRINT ORA #$80 ; normal (non-inverse) video byte
 JSR VDRAW
 INC VCOL
 LDA VCOL
 CMP #80
 BCC VDONE
 LDA #0
 STA VCOL
VDOWN INC VROW
 LDA VROW
 CMP #24
 BCC VDONE
 DEC VROW ; stay on bottom row after scroll
 JMP VSCROLL

* Set up self-modifying absolute-indexed access to one text row.
* Returns Y = column/2 and 80STORE on, PAGE2 selecting bank.
VADDR LDX VROW
 LDA VROWLO,X
 STA VSTORE+1
 STA VLOAD+1
 LDA VROWHI,X
 STA VSTORE+2
 STA VLOAD+2
 LDA VCOL
 LSR
 TAY
 STA $C001 ; 80STORE on (writes only)
 LDA VCOL
 AND #1
 BNE :VA1
 BIT $C055 ; even column: auxiliary text page 1
 RTS
:VA1 BIT $C054 ; odd column: main text page 1
 RTS

VDRAW PHA
 JSR VADDR
 PLA
VSTORE STA $0400,Y ; operand updated by VADDR
 STA $C054 ; PAGE1/main selected
 STA $C000 ; 80STORE off - ProDOS-safe on return
 RTS

VPEEK JSR VADDR
VLOAD LDA $0400,Y ; operand updated by VADDR
 PHA
 BIT $C054 ; PAGE1/main selected
 STA $C000 ; 80STORE off (write-only switch)
 PLA
 RTS

* Direct keyboard access; don't call RDKEY or the 80-column ROM.
* Keep the original byte under the cursor, including its attributes.
VGET JSR VPEEK
 STA VUNDER
 AND #$3F ; inverse form of screen character
 JSR VDRAW
:VGWAIT LDA $C000 ; keyboard latch; bit 7 means key ready
 BPL :VGWAIT
 PHA
 BIT $C010 ; clear keyboard strobe
 LDA VUNDER
 JSR VDRAW ; restore original character
 PLA
 RTS

VBELL BIT $C030 ; click speaker
 RTS

* Clear BOTH physical halves of 80-column text page 1.
VCLEAR LDA #0
 STA VCOL
 STA VROW
 STA $C001 ; 80STORE on
 BIT $C054 ; main
 JSR VCLRBANK
 BIT $C055 ; auxiliary
 JSR VCLRBANK
 BIT $C054 ; main again
 STA $C000 ; 80STORE off
 RTS

VCLRBANK LDA #$A0 ; normal video space
 LDX #0
:VCL1 STA $0400,X
 STA $0500,X
 STA $0600,X
 STA $0700,X
 INX
 BNE :VCL1
 RTS

* Scroll main and auxiliary halves, 23 rows up, clear row 23.
VSCROLL LDA #0
 STA $C001 ; 80STORE on
 BIT $C054
 JSR VSCBANK
 BIT $C055
 JSR VSCBANK
 BIT $C054
 STA $C000 ; 80STORE off
 RTS

VSCBANK LDX #0
VSR1 LDA VROWLO+1,X ; row below, source
 STA VSRC+1
 LDA VROWHI+1,X
 STA VSRC+2
 LDA VROWLO,X ; current row, destination
 STA VDST+1
 LDA VROWHI,X
 STA VDST+2
 LDY #39
VSR2
VSRC LDA $0480,Y ; patched source
VDST STA $0400,Y ; patched destination
 DEY
 BPL VSR2
 INX
 CPX #23
 BNE VSR1
 LDA #$A0
 LDY #39
:VSR3 STA $07D0,Y ; bottom text row (row 23)
 DEY
 BPL :VSR3
 RTS

* Interleaved Apple II text row addresses (main AND auxiliary).
VROWLO DB $00,$80,$00,$80,$00,$80,$00,$80
 DB $28,$A8,$28,$A8,$28,$A8,$28,$A8
 DB $50,$D0,$50,$D0,$50,$D0,$50,$D0
VROWHI DB $04,$04,$05,$05,$06,$06,$07,$07
 DB $04,$04,$05,$05,$06,$06,$07,$07
 DB $04,$04,$05,$05,$06,$06,$07,$07

VCOL DB 0
VROW DB 0
VTCNT DB 0
VUNDER DB 0

* Loader diagnostics without ROM I/O.
CROUT LDA #$0D
 JMP VPUT

PRBYTE PHA
 LSR
 LSR
 LSR
 LSR
 JSR PRHEX
 PLA
 AND #$0F
PRHEX CMP #10
 BCC :PH1
 CLC
 ADC #7
:PH1 CLC
 ADC #'0'
 JMP VPUT

RELOC_EN
