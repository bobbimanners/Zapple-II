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
* Public entry vectors at B803, B806, B809 remain fixed.
* B80C sets mode; B80F handles raw BIOS console output.

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
* B800 loader, B803 cooked output, B806 input, B809 bell.
* B80C set terminal mode, B80F raw BIOS output.
 JMP ENTRY
 JMP VPUT
 JMP VGET
 JMP VBELL
 JMP VSETMODE ; B80C: A=0 Videx, A=1 Soroc (does not clear)
 JMP VRAWPUT  ; B80F: raw BIOS/BDOS function 6 output

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
* Exit to the ProDOS program selector. CMD=0 in HANDLR reaches here;
* loader errors use the same exit. QUIT normally never returns.
DONE
 LDA #0
 STA $C000 ; 80STORE off
 STA $C002 ; RAMRD main
 STA $C004 ; RAMWRT main
 STA $C00C ; 80COL off (ProDOS selector controls display)
 JSR CL    ; Close all remaining open ProDOS files
 INC $03F4 ; Invalidate the monitor power-up byte for safe reboot
 JSR $BF00 ; ProDOS MLI
 DB $65    ; QUIT
 DW QUIT_PL
 BRK       ; Unexpected: QUIT returned
QUIT_PL DB 4 ; ProDOS QUIT: 4 parameters
 DB 0      ; Standard quit type
 DW 0      ; Reserved
 DB 0      ; Reserved
 DW 0      ; Reserved

* Pointer to message is in ZP $06-$07
* Uses ZP $08 as temporary
PRMSG LDY #0 ; Initialize index
 LDA ($06),Y ; Length of string
 STA $08 ; Store length in temp
:L1 INY  ; Advance char pointer
 TYA ; Save the message index BEFORE loading the character
 PHA ; VPUT modifies Y, so preserve it
 LDA ($06),Y ; Character must still be in A for VPUT
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
* Two output personalities share the same screen primitives:
*   Videx VideoTerm: $1E, column+$20, row+$20
*   Soroc IQ-120:    ESC '=', row+$20, column+$20
* VMODE 0=Videx (default), 1=Soroc; set using B80C vector.
* Cursor address parameters are consumed even when malformed.
* Cooked CR implies newline (existing CCP convention); cooked CR+LF
* advances once. Raw BIOS CR only returns to column 0; LF goes down.
* Soroc protected fields, graphics and auxiliary port are not emulated.
***************************************************

VINIT
 LDA #0
 STA VMODE ; Default to Videx
 STA VSTATE ; Parser idle
 STA VCRP ; No pending CR/LF pair
 STA $C000 ; 80STORE off
 STA $C002 ; RAMRD main
 STA $C004 ; RAMWRT main
 BIT $C054 ; PAGE1
 BIT $C051 ; TEXT on
 BIT $C052 ; full screen
 STA $C00D ; 80COL on
 STA $C00F ; alternate charset (lowercase)
 JSR VMBASIC ; Configure Apple CP/M BASIC console control bytes
 JMP VCLEAR

* A=0 selects Videx, A=1 selects Soroc. Ignore all other values.
* Public vector at B80C. Mode change retains screen and cursor.
VSETMODE CMP #2
 BCC :LONG5
 RTS
:LONG5
 STA VMODE
 LDA #0
 STA VSTATE
 STA VCRP
 JMP VMBASIC ; Keep MBASIC's terminal control table in sync

* Apple CP/M Microsoft BASIC-80 5.2 expects BIOS video control bytes
* at Z80 $F396-$F39E = 6502 $0396-$039E (SoftCard memory map).
* $0396 = coordinate bias; bit 7 reverses XY ordering.
* $0397 = prefix for high-bit-set commands.
* $0398 = HOME (table entry 1).
* $039E = position cursor (table entry 7).
* The other five commands are unsupported: set to 0 (do nothing).
* This is 6502 page-3 RAM, outside the Z80 TPA. No MBASIC patch.
VMBASIC LDX #5
 LDA #0
:BLANK STA $0399,X ; Clear $0399..$039E; set $039E below
 DEX
 BPL :BLANK
 LDA #$1B
 STA $0397 ; ESC prefix
 LDX VMODE
 LDA VBASTAB,X
 STA $0396
 LDA VBASHOME,X
 STA $0398
 LDA VBASPOS,X
 STA $039E
 RTS

* Mode indexed: 0 Videx, 1 Soroc.
* For Soroc, an encoded $AA means ESC '*' (clear screen),
* and $BD means ESC '=' (cursor address introducer).
* Videx uses ^L (clear) and CTRL-^ (position introducer).
VBASTAB DB $A0,$20  ; coordinate bias (Videx swaps order)
VBASHOME DB $0C,$AA  ; HOME: ^L or ESC '*'
VBASPOS DB $1E,$BD  ; position: $1E or ESC '='

* Raw output from BIOS CONOUT / BDOS function 6. Real terminals
* interpret CR and LF independently; avoid cooked CCP newline policy.
VRAWPUT AND #$7F
 CMP #$0D
 BNE :RC1
 LDA #0
 STA VCRP
 STA VCOL
 RTS
:RC1 CMP #$0A
 BNE :RC2
 LDA #0
 STA VCRP
 JMP VDOWN
:RC2 JMP VPUT

* Cooked output used by BDOS function 2, CCP, loader, etc.
* Other than CR/LF, only the parser is mode-dependent.
VPUT AND #$7F
 CMP #$0A
 BEQ :KEEPC
 PHA
 LDA #0
 STA VCRP
 PLA
:KEEPC LDX VSTATE
 BEQ :LONG11
 JMP VSEQ
:LONG11
 CMP #$1B
 BEQ VESC
 CMP #$20
 BCC :LONG0
 JMP VPRINT
:LONG0
 CMP #$0A
 BNE :LONG1
 JMP VLF
:LONG1
 CMP #$0D
 BNE :LONG2
 JMP VCR
:LONG2
 CMP #$08
 BNE :LONG3
 JMP VBACK
:LONG3
 CMP #$09
 BNE :LONG4
 JMP VTAB
:LONG4
 CMP #$07
 BNE :VCTL
 JMP VBELL
:VCTL LDX VMODE
 BNE VSOROC
* Videx VideoTerm (including Apple escape editor handled below).
 CMP #$0C
 BNE :VD1
 JMP VCLEAR
:VD1 CMP #$19
 BNE :LONG6
 JMP VHOME
:LONG6
 CMP #$1E
 BEQ VPOS
 CMP #$1C
 BNE :LONG7
 JMP VRIGHT
:LONG7
 CMP #$1F
 BNE :LONG8
 JMP VUP
:LONG8
 CMP #$1D
 BNE :VD2
 JMP VEOL
:VD2 CMP #$0B
 BNE VDONE
 JMP VEOP

* Soroc IQ-120: ^K up, ^L forward, ^^ home.
VSOROC CMP #$0B
 BNE :LONG9
 JMP VUP
:LONG9
 CMP #$0C
 BNE :LONG10
 JMP VRIGHT
:LONG10
 CMP #$1E
 BNE :LONG12
 JMP VHOME
:LONG12
VDONE RTS

VESC LDA #1
 STA VSTATE
 RTS
VPOS LDA #2
 STA VSTATE
 RTS

* Parser states 1=ESC, 2=first coordinate, 3=second coordinate.
VSEQ CPX #1
 BEQ VESCCMD
 SEC
 SBC #$20
 CPX #2
 BNE :VP2
 STA VCOORD
 INC VSTATE
 RTS
:VP2 LDY #0
 STY VSTATE
 LDX VMODE
 BNE :SPOS
* Videx: first X/column, then Y/row.
 CMP #24
 BCS VDONE
 LDY VCOORD
 CPY #80
 BCS VDONE
 STA VROW
 STY VCOL
 RTS
* Soroc: first Y/row, then X/column.
:SPOS CMP #80
 BCS VDONE
 LDY VCOORD
 CPY #24
 BCS VDONE
 STA VCOL
 STY VROW
 RTS

* ESC sequences. Unrecognised commands are silently consumed.
VESCCMD LDY #0
 STY VSTATE
 LDY VMODE
 BNE :SORE
* VideoTerm accepts the Apple editing ESC sequences.
 CMP #'@'
 BNE :E1
 JMP VCLEAR
:E1 CMP #'A'
 BEQ VRIGHT
 CMP #'B'
 BEQ VBACK
 CMP #'C'
 BNE :LONG13
 JMP VDOWN
:LONG13
 CMP #'D'
 BEQ VUP
 CMP #'E'
 BNE :E2
 JMP VEOL
:E2 CMP #'F'
 BNE VDONE
 JMP VEOP
:SORE CMP #'='
 BEQ VPOS
 CMP #'*'
 BNE :S1
 JMP VCLEAR
:S1 CMP #'+'
 BNE :S2
 JMP VCLEAR
:S2 CMP #'T'
 BNE :S3
 JMP VEOL
:S3 CMP #'Y'
 BEQ :EP
 CMP #'V' ; Some IQ-120 documentation calls this Erase Page.
 BEQ :LONG14
 RTS
:LONG14
:EP JMP VEOP

VHOME LDA #0
 STA VCOL
 STA VROW
 RTS

* Preserve the loader/BDOS convention of CR as a newline.
* Unlike the old driver, a lone LF now moves down; CR+LF moves once.
VCR LDA #1
 STA VCRP
 LDA #0
 STA VCOL
 JMP VDOWN
VLF LDA VCRP
 BEQ VDOWN
 LDA #0
 STA VCRP
 RTS

VUP LDA VROW
 BNE :LONG15
 RTS
:LONG15
 DEC VROW
 RTS
VRIGHT LDA VCOL
 CMP #79
 BCC :LONG16
 RTS
:LONG16
 INC VCOL
 RTS
VBACK LDA VCOL
 BNE :LONG17
 RTS
:LONG17
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

VPRINT ORA #$80
 JSR VDRAW
 INC VCOL
 LDA VCOL
 CMP #80
 BCS :LONG18
 RTS
:LONG18
 LDA #0
 STA VCOL
VDOWN INC VROW
 LDA VROW
 CMP #24
 BCS :LONG19
 RTS
:LONG19
 DEC VROW
 JMP VSCROLL

* Erase operations leave the original cursor position unchanged.
* Reuse VDRAW for both physical halves rather than duplicate bank logic.
VEOL LDA VCOL
 PHA
:EL1 LDA #$A0
 JSR VDRAW
 INC VCOL
 LDA VCOL
 CMP #80
 BCC :EL1
 PLA
 STA VCOL
 RTS

VEOP LDA VROW
 PHA
 LDA VCOL
 PHA
 JSR VEOL
:EP1 INC VROW
 LDA VROW
 CMP #24
 BCS :EP2
 LDA #0
 STA VCOL
 JSR VEOL
 JMP :EP1
:EP2 PLA
 STA VCOL
 PLA
 STA VROW
 RTS

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
VMODE DB 0 ; 0 Videx, 1 Soroc
VSTATE DB 0 ; 0 idle, 1 ESC, 2 coord1, 3 coord2
VCOORD DB 0
VCRP DB 0 ; Suppress second half of CR/LF pair

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
