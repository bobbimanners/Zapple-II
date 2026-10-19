***************************************************
* 6502 code to invoke Z80 routine on Softcard and
* handle calls from Z80 back to 6502
* Assumes Softcard in slot 4
* Bobbi 2019, 2026
***************************************************

 ORG $2000  ; System program
 TYP $FF  ; .SYS

SFTCRD EQU $C400 ; Softcard in slot 4
CMD EQU $06 ; ZP address for command code (0=quit,1=6502,2=MLI,3=key status)
AREG EQU $07 ; Pass 6502 A reg to/from Z80
XREG EQU $08 ; Pass 6502 X reg to/from Z80
YREG EQU $09 ; Pass 6502 Y reg to/from Z80
ADDR EQU $EB ; Pass address of 6502 routine to call from Z80
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

 JSR RWAUTODETECT ; One-time test; loader code is disposable
 JMP STADDR ; Jump to reloc'd code

* Probe up to 128 distinct RamWorks banks using physical AUX $07FE.
* Executed only before the Z80 starts; this loader code can be discarded.
* Save every original byte, write distinct markers, verify all prior banks
* remain independent, then restore the bytes even on an aliased bank.
RWAUTODETECT
 LDA #0
 STA $C000       ; 80STORE off
 STA $C002       ; RAMRD MAIN
 STA $C004       ; RAMWRT MAIN
 STA $C073
 BIT $C056      ; HIRES off, so loader code at $2000 remains MAIN
 STA $C001       ; 80STORE on
 BIT $C055      ; PAGE2 maps AUX text to $0400..$07FF
 LDY #0
:RWTRY
 TYA
 STA $C073
 LDA $07FE
 STA RWORIGINAL,Y
 TYA
 EOR #$5A
 STA $07FE
 LDX #0
:RWVERIFY
 TXA
 STA $C073
 TXA
 EOR #$5A
 CMP $07FE
 BNE :RWFINISH
 INX
 ; X <= Y means candidate and all established banks need checking.
 STX RWTESTX
 TYA
 CMP RWTESTX
 BCS :RWVERIFY
 INY
 CPY #128
 BCC :RWTRY
:RWFINISH
 STY RWCOUNT    ; Number of distinct banks, at least one.
:RWRESTORE
 DEY
 TYA
 STA $C073
 LDA RWORIGINAL,Y
 STA $07FE
 TYA
 BNE :RWRESTORE
 BIT $C054      ; PAGE1
 LDA #0
 STA $C000       ; 80STORE off
 STA $C073       ; normal system bank
 RTS
RWTESTX DB 0
RWORIGINAL DS 128

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
 JMP VCLS     ; B812: CLS reset terminal, clear and home
 JMP RWPROBE  ; B815: cached physical bank count (cold probe)
 JMP RWSELECT ; B818: bank selection, A=0/1 (private Z80 caller)
 JMP VGETMODE ; B81B: return terminal personality in A (private Z80)
 JMP VSTATEPTR ; B81E: pointer to contiguous VCOL..VATTR state
 JMP VSELECT   ; B821: A=bank, X=physical flag, Y=slot offset

ENTRY CLD             ; ProDOS/loader entry always uses binary arithmetic
 LDA #0
 STA RWACTIVE
 STA $C073       ; Start all CP/M sessions from system/video bank 0
 JSR VINIT ; Initialize video hardware and clear screen
* Diagnostic build: omit redundant loader greeting to make room for trace.
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
:S2 JSR CL ; Close file
 JSR CROUT ; load succeeded

MAINLOOP
 STA SFTCRD ; Pause Z80, resume 6502
 JSR HANDLR ; Handle calls made by Z80 code
 JMP MAINLOOP ; Keep on keeping on
* Exit to the ProDOS program selector. CMD=0 in HANDLR reaches here;
* loader errors use the same exit. QUIT normally never returns.
DONE
 LDA #0
 STA RWACTIVE ; Leave ProDOS selector with default AUX bank
 STA $C073
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

* Successful load: proceed directly to Z80 after newline.

* File to load
PATH STR "SOFTCARD80.BIN"

* Messages
OPERR STR ": Open "
RDERR STR ": Read"
* No loader success string

* ProDOS Parameter List for OPEN
OP JSR $BF00 ; ProDOS call
 DB $C8 ; OPEN
 DW OP_PL ; Pointer to parm list
 RTS  ;
OP_PL DB 3 ; Start of param list; 3 parameters
OP_FP DW PATH ; Pointer to file path
OP_FBL DW IOBUF ; Pointer to I/O buffer
OP_N DB 0 ; File reference number

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

* ProDOS Parameter List for CLOSE
CL JSR $BF00 ; ProDOS call
 DB $CC ; CLOSE
 DW CL_PL ; Pointer to parm list
 RTS
CL_PL DB 1 ; Start of param list; 1 parameter
CL_N DB 0 ; File ref num (0 close all)

* Handle calls made by Z80 code
HANDLR CLD           ; Don't inherit decimal mode from preceding calls
 LDA #0
 STA $C073   ; MLI/video/keyboard always use physical AUX bank 0
 LDA CMD
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
* Bit 3 of the incoming status byte can SET the 6502 decimal flag.
* That makes ADC $1C to $04 produce $26 instead of $20, putting
* background characters into row 4 of the saved AUX screen.  Clear
* decimal mode AFTER PLP, preserving incoming carry/other flags.
 CLD
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
 JMP RWRETURN ; Restore selected transient bank before Z80 resumes
:CMD2 CMP #2 ; CMD=2 means call ProDOS MLI then return to Z80
 BNE :CMD3 ;
 JSR :DOJMP ; ProDOS MLI call
 STA AREG ; Store return code
 JMP RWRETURN
:CMD3 CMP #3 ; CMD=3 means peek at the keyboard then ret to Z80
 BNE :CMD4 ;
 BIT $C000 ; Peek at the keyboard status
 BMI :C3YES ; Branch if keystroke available
 LDA #0 ; If no chars, return 0 in AREG
 JMP :C3DONE ; ...
:C3YES LDA $C000 ; Expose keycode without consuming the key
 STA YREG
 LDA $C061  ; Open Apple pushbutton (bit 7 = pressed)
 STA XREG   ; modifier accompanying the peeked character
 LDA #1
:C3DONE STA AREG ; Store the value for the Z80
 JMP RWRETURN ; Restore transient bank
:CMD4 JSR VBELL ; Beep for error
 BRK  ; And drop into monitor
:DOJMP JMP (ADDR) ;

* Bank selection lives in MAIN memory, not in a banked AUX program.
* RWSELECT is called via $B818, with the selected bank in AREG.
* MLI, keyboard and video use bank 0; restore RWACTIVE on return.
RWSELECT STA RWACTIVE
 RTS
RWRETURN LDA RWACTIVE
 STA $C073
 RTS
RWACTIVE DB 0
RWCOUNT DB 1  ; Filled by disposable loader probe before ENTRY


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
* VMODE 0=Videx, 1=Soroc (default); set using B80C vector.
* Cursor address parameters are consumed even when malformed.
* Cooked CR implies newline (existing CCP convention); cooked CR+LF
* advances once. Raw BIOS CR only returns to column 0; LF goes down.
* Soroc ESC '(' / ESC ')' select inverse/normal video (SoftCard).
* Soroc protected fields, graphics and auxiliary port are not emulated.
***************************************************

* CLS restores a known text-screen state but preserves Soroc/Videx mode.
* Called from the MAIN-memory CCP via the public B812 vector.
VCLS
 LDA #0
 STA VSTATE   ; abandon incomplete escape/coordinate sequence
 STA VCRP     ; clear pending cooked CR/LF state
 STA VATTR    ; normal video regardless of selected personality
 STA $C000   ; 80STORE off
 STA $C002   ; MAIN reads
 STA $C004   ; MAIN writes
 BIT $C054   ; PAGE1
 BIT $C051   ; TEXT on
 BIT $C052   ; full-screen
 STA $C00D   ; 80COL on
 STA $C00F   ; alternate/lowercase character set
 JMP VCLEAR  ; clears both banks and puts cursor at 0,0

VINIT
 LDA #1
 STA VMODE ; Default to Soroc
 LDA #0
 STA VVRDY
 LDA RWCOUNT
 CMP #3
 BCC :VNORW
 INC VVRDY
:VNORW
 LDA #2
 LDX #1
 LDY #$1C
 JSR VSELECT ; bank 2, foreground, slot 0
 LDA #0
 STA VSTATE ; Parser idle
 STA VCRP ; No pending CR/LF pair
 STA VATTR ; Reset inverse video
 STA $C000 ; 80STORE off
 STA $C002 ; RAMRD main
 STA $C004 ; RAMWRT main
 BIT $C054 ; PAGE1
 BIT $C051 ; TEXT on
 BIT $C052 ; full screen
 STA $C00D ; 80COL on
 STA $C00F ; alternate charset (lowercase)
* VSELECT initialized the BASIC control bytes above
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
 STA VATTR ; Reset inverse video on terminal change
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
 BNE :E1A
 JMP VRIGHT
:E1A CMP #'B'
 BNE :E1B
 JMP VBACK
:E1B CMP #'C'
 BNE :LONG13
 JMP VDOWN
:LONG13
 CMP #'D'
 BEQ VUP
 CMP #'E'
 BNE :E2
 JMP VEOL
:E2 CMP #'F'
 BEQ :E2F
 JMP VDONE
:E2F JMP VEOP
:SORE CMP #'(' ; Microsoft SoftCard Soroc: inverse ON
 BNE :SINV1
 LDA #1
 STA VATTR
 RTS
:SINV1 CMP #')' ; Inverse OFF
 BNE :SINV2
 LDA #0
 STA VATTR
 RTS
:SINV2 CMP #'='
 BNE :SINV3
 JMP VPOS
:SINV3 CMP #'*'
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

* Apple IIe ALTCHARSET inverse uses $00-$3F and $60-$7F.
* $40-$5F is MouseText, so fold uppercase into $00-$1F.
VPRINT LDX VATTR
 BEQ :VNORM
 CMP #$60
 BCS :VSHOW
 AND #$3F
 JMP :VSHOW
:VNORM ORA #$80
:VSHOW JSR VDRAW
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
 STA VBSTORE+1
 LDA VROWHI,X
 STA VSTORE+2
 STA VLOAD+2
 CLC
 ADC VVOFF
 STA VBSTORE+2
 LDA VCOL
 LSR
 TAY
 STA $C001 ; 80STORE on (writes only)
 LDA VCOL
 AND #1
 BNE :VA1
 ; Even column is physical AUX, second 1K of our snapshot.
 LDA VBSTORE+2
 CLC
 ADC #4
 STA VBSTORE+2
 BIT $C055 ; even column: auxiliary text page 1
 RTS
:VA1 BIT $C054 ; odd column: main text page 1
 RTS

* Foreground output uses physical video only (saved at manual tab switch).
* Background output updates only that session's virtual screen snapshot.
; The $2000-$3FFF HGR aperture maps into the selected snapshot bank.
VDRAW PHA
 JSR VADDR
 PLA
 LDX VPHY
 BEQ :VBG
VSTORE STA $0400,Y ; physical foreground text half
 ; Foreground image is captured by VSSAVE on a manual tab switch.
 ; Avoid touching the virtual bank while this tab owns the screen.
 BIT $C054
 STA $C000       ; 80STORE off
 RTS
:VBG PHA
* The row table / physical operand are correct, but trace showed
* a stale VBSTORE high byte ($26 vs expected $20 for row 0, col 1).
* Rebuild the backing operand immediately before the banked STORE,
* using the PHYSICAL operand already computed by VADDR.  Avoid
* relying on a persistent self-modifying virtual operand across calls.
* Preserve A (character) on stack and Y (screen byte index) unchanged.
 LDA VSTORE+1
 STA VBSTORE+1
 LDA VSTORE+2
 CLC
 ADC VVOFF
 STA VBSTORE+2
 LDA VCOL
 AND #1
 BNE :VBADDRDONE
 LDA VBSTORE+2
 CLC
 ADC #4         ; even column: AUX half of saved 80-col screen
 STA VBSTORE+2
:VBADDRDONE
 BIT $C054
 STA $C000       ; leave 80STORE off before snapshot window
 LDA VVRDY
 BEQ :VEND
 LDA VVBANK
 STA $C073
 STA $C001       ; 80STORE on
 BIT $C057       ; HIRES on
 BIT $C055       ; PAGE2: AUX HGR snapshot window
 PLA
VBSTORE STA $2000,Y ; patched snapshot row/half/slot
 PHA
 BIT $C054       ; PAGE1
 BIT $C056       ; HIRES off
 STA $C000       ; 80STORE off
 LDA #0
 STA $C073       ; ALWAYS return physical bank 0
:VEND PLA
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
* Toggle the underlying screen character's inverse/normal video.
* Keep existing attributes intact when the key is returned.
 BMI :VGNORM ; Normal byte ($80-$FF): make inverse
 CMP #$20
 BCC :VGUP ; Inverse uppercase -> normal uppercase
 ORA #$80 ; Inverse punctuation/lowercase -> normal
 BNE :VGSHOW
:VGUP ORA #$C0
 BNE :VGSHOW
:VGNORM AND #$7F
 CMP #$60
 BCS :VGSHOW
 AND #$3F ; Avoid MouseText when inverting uppercase
:VGSHOW JSR VDRAW
:VGWAIT LDA $C000 ; keyboard latch; bit 7 means key ready
 BPL :VGWAIT
 PHA
 LDA $C061 ; sample Open Apple BEFORE strobe is cleared
 STA VKMOD
 BIT $C010 ; clear keyboard strobe
 LDA VUNDER
 JSR VDRAW ; restore original character
 PLA
 LDX VKMOD ; HANDLR returns X in XREG alongside AREG keycode
 RTS

VBELL BIT $C030 ; click speaker
 RTS

* Foreground clears physical text; background clears its snapshot only.
VCLEAR LDA #0
 STA VCOL
 STA VROW
 LDX VPHY
 BNE :VCPHY
 LDA VVRDY
 BEQ :VCDONE
 JSR VBCLR
 JMP :VCDONE
:VCPHY LDA #0
 STA $C001 ; 80STORE on
 BIT $C054 ; main
 JSR VCLRBANK
 BIT $C055 ; auxiliary
 JSR VCLRBANK
 BIT $C054 ; main again
 STA $C000 ; 80STORE off
:VCDONE RTS

* Clear the whole 2KB of the selected session's snapshot: main+aux.
* Both halves occupy [VVOFF .. VVOFF+7]; old +4 overwrote NEXT tab.
* Clear 2KB via a zero-page pointer, no unrolled writes.
* $EB/$EC is the 6502 ADDR dispatch pointer. It is scratch after
* the indirect JMP into VPUT/VCLS; Z80 resets it before its next call.
VBCLR LDA VVBANK
 STA $C073
 STA $C001
 BIT $C057
 BIT $C055
 LDA #0
 STA $EB
 LDA VVOFF       ; high-byte OFFSET from $0400, not absolute address
 CLC
 ADC #4           ; $0400 + VVOFF*256 = backing screen base
 STA $EC
 LDX #8
 LDY #0
:VBPAGE
 LDA #$A0
:VBLOOP
 STA ($EB),Y
 INY
 BNE :VBLOOP
 INC $EC
 DEX
 BNE :VBPAGE
 BIT $C054
 BIT $C056
 STA $C000
 LDA #0
 STA $C073
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

* Scroll only the active destination: physical if fg, snapshot if bg.
* VSHIFT is the high-byte delta from the physical $0400 text page.
VSCROLL LDX VPHY
 BNE :VSPHY
 LDA VVRDY
 BEQ :VSEND
 LDA VVBANK
 STA $C073
 STA $C001
 BIT $C057
 BIT $C055
 LDA VVOFF
 STA VSHIFT
 JSR VSCBANK ; first stored 1K: main
 LDA VVOFF
 CLC
 ADC #4
 STA VSHIFT
 JSR VSCBANK ; second stored 1K: auxiliary
 BIT $C054
 BIT $C056
 LDA #0
 STA $C000
 STA $C073
 RTS             ; background scroll MUST NOT fall into physical path
:VSPHY
 LDA #0
 STA VSHIFT
 STA $C001 ; 80STORE on
 BIT $C054
 JSR VSCBANK
 BIT $C055
 JSR VSCBANK
 BIT $C054
 STA $C000 ; 80STORE off
:VSEND RTS

VSCBANK LDX #0
VSR1 LDA VROWLO+1,X ; row below, source
 STA VSRC+1
 LDA VROWHI+1,X
 CLC
 ADC VSHIFT
 STA VSRC+2
 LDA VROWLO,X ; current row, destination
 STA VDST+1
 LDA VROWHI,X
 CLC
 ADC VSHIFT
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
 LDA VSHIFT
 CLC
 ADC #7
 STA VSBOT+2
 LDA #$A0
 LDY #39
:VSR3
VSBOT STA $07D0,Y ; bottom text row (row 23)
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
VMODE DB 1 ; 0 Videx, 1 Soroc (default)
VSTATE DB 0 ; 0 idle, 1 ESC, 2 coord1, 3 coord2
VCOORD DB 0
VCRP DB 0 ; Suppress second half of CR/LF pair
VATTR DB 0 ; Soroc ESC '(' inverse on, ESC ')' normal
VKMOD DB 0 ; last blocking key's Open Apple state (outside saved video)
VPHY DB 1 ; running session owns physical screen
VVBANK DB 2 ; reserved RamWorks snapshot bank
VVOFF DB $1C ; high-byte delta for first snapshot half
VSHIFT DB 0 ; scroll destination high-byte delta
VVRDY DB 0 ; nonzero when physical bank 2 exists

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
* Return the bank count saved by the one-time pre-relocation loader probe.
* Do not test banks again here: sessions may now contain live programs.
RWPROBE LDA RWCOUNT
 RTS

* Query terminal mode without resetting it. Used by TAB session state.
VGETMODE LDA VMODE
 RTS

* Return physical address of the 9-byte contiguous terminal state.
* Z80 main code converts Apple Bxxx to Z80 Axxx (minus $1000).
VSTATEPTR LDA #<VCOL
 LDX #>VCOL
 RTS

* B821: A=snapshot bank, X=foreground flag, Y=slot high delta.
* No screen copy; caller computes addressing from its TABMODE.
VSELECT STA VVBANK
 STX VPHY
 STY VVOFF
 JMP VMBASIC      ; refresh per-task MBASIC control bytes

RELOC_EN
