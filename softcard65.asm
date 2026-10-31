***************************************************
* 6502 code to invoke Z80 routine on Softcard and
* handle calls from Z80 back to 6502
* Assumes Softcard in slot 4
* Bobbi 2019, 2026
***************************************************

              ORG       $2000                          ; System program
              TYP       $FF                            ; .SYS

SFTCRD        EQU       $C400                          ; Softcard in slot 4
CMD           EQU       $06                            ; ZP address for command code (0=quit,1=6502,2=MLI,3=key status)
AREG          EQU       $07                            ; Pass 6502 A reg to/from Z80
XREG          EQU       $08                            ; Pass 6502 X reg to/from Z80
YREG          EQU       $09                            ; Pass 6502 Y reg to/from Z80
ADDR          EQU       $EB                            ; Pass address of 6502 routine to call from Z80
FLAGS         EQU       $ED                            ; Pass 6502 flags to/from Z80

* 80-column text page 1, direct main/aux video access.
* No Apple II monitor or 80-column firmware routines are called.
* Public entry vectors at B803, B806, B809 remain fixed.
* B80C sets mode; B80F handles raw BIOS console output.

IOBUF         EQU       $0800                          ; 1K ProDOS OPEN buffer in unused text page 2.
    ; The extended video driver now uses B800-BEFF.
    ; This does not overlap Z80's A800-B7FF I/O buffers.
LDADDR        EQU       $0FFD                          ; Load to $1000 hex
    ; (Accounting for 3 byte prefix)
LDLEN         EQU       $FFFF                          ; Load it all

STADDR        EQU       $B800                          ; Code will be relocated to this addr

* Code to relocate everything from RELOC_ST to RELOC_EN
* To begin at STADDR
* ZP $06-07 is source pointer
* ZP $08-09 is dest pointer
              LDA       #<RELOC_ST                     ;
              STA       $06                            ; source LSB
              LDA       #>RELOC_ST                     ;
              STA       $07                            ; source MSB
              LDA       #<STADDR                       ;
              STA       $08                            ; dest LSB
              LDA       #>STADDR                       ;
              STA       $09                            ; dest MSB
              LDY       #0                             ;
:LDRL1        LDA       ($06),Y                        ; Copy a byte
              STA       ($08),Y                        ;
              INC       $06                            ; source LSB
              BNE       :LDRS1                         ; If no rollover
              INC       $07                            ; inc source MSB
:LDRS1        INC       $08                            ; dest LSB
              BNE       :LDRS2                         ; If no rollover
              INC       $09                            ; inc dest MSB
:LDRS2        LDA       $09                            ; dest MSB
              CMP       #>RELOC_EN                     ; at end?
              BNE       :LDRL1                         ; Nope. Loop
              LDA       $08                            ; dest LSB
              CMP       #<RELOC_EN                     ; at end?
              BNE       :LDRL1                         ; Nope. Loop

              JSR       RWAUTODETECT                   ; One-time test; loader code is disposable
              JSR       NCFGLOAD                       ; read system config in ProDOS boot environment
              JSR       NCFGCOPY                       ; preserve disposable post-load helper below $0FFD
              JMP       STADDR                         ; Jump to reloc'd code

* Probe up to 128 distinct RamWorks banks using physical AUX $07FE.
* Executed only before the Z80 starts; this loader code can be discarded.
* Save every original byte, write distinct markers, verify all prior banks
* remain independent, then restore the bytes even on an aliased bank.
RWAUTODETECT
              LDA       #0
              STA       $C000                          ; 80STORE off
              STA       $C002                          ; RAMRD MAIN
              STA       $C004                          ; RAMWRT MAIN
              STA       $C073
              BIT       $C056                          ; HIRES off, so loader code at $2000 remains MAIN
              STA       $C001                          ; 80STORE on
              BIT       $C055                          ; PAGE2 maps AUX text to $0400..$07FF
              LDY       #0
:RWTRY
              TYA
              STA       $C073
              LDA       $07FE
              STA       RWORIGINAL,Y
              TYA
              EOR       #$5A
              STA       $07FE
              LDX       #0
:RWVERIFY
              TXA
              STA       $C073
              TXA
              EOR       #$5A
              CMP       $07FE
              BNE       :RWFINISH
              INX
    ; X <= Y means candidate and all established banks need checking.
              STX       RWTESTX
              TYA
              CMP       RWTESTX
              BCS       :RWVERIFY
              INY
              CPY       #128
              BCC       :RWTRY
:RWFINISH
              STY       RWCOUNT                        ; Number of distinct banks, at least one.
:RWRESTORE
              DEY
              TYA
              STA       $C073
              LDA       RWORIGINAL,Y
              STA       $07FE
              TYA
              BNE       :RWRESTORE
              BIT       $C054                          ; PAGE1
              LDA       #0
              STA       $C000                          ; 80STORE off
              STA       $C073                          ; normal system bank
              RTS
RWTESTX       DB        0
RWORIGINAL    DS        128

* Phase 2B: initialize network from optional ProDOS configuration.
* CONFIGURATION SAFETY:
*   RESET=0 : NO W5100 writes, preserving VEDRIVE and open TCP sockets.
*   RESET=1 : reset entire chip, configure IP/NM/GW/MAC, default 2K sockets.
*   SLOT must equal 5 (this kernel's W5100 6502 bridge is fixed to slot 5).
* Invalid, absent or incomplete configuration leaves hardware untouched.
* IMPORTANT: RESET=1 destroys ALL existing VEDRIVE/TCP sessions.
* Loader and parser run before relocated 6502 driver and Z80 startup.
* Tagged mounts stage at $0C00-$0CDB, outside ProDOS's $0800 open buffer.
* Network/DNS stage at $0E00-$0E5C survives the load at $0FFD.
* After loading, ENTRY copies mounts to MAIN $0103, DNS to $01DF.
* SOFTCARD is separate from Uthernet's SLOT=5 configuration key.
NCFGINIT      LDA       #0
              LDX       #0
:CFMZERO      STA       $0C00,X                ; clear all 5 x 44 mount bytes
              INX
              CPX       #220                    ; don't use BPL for counts >127!
              BNE       :CFMZERO
              LDY       #91
              LDA       #0
:CFZERO       STA       $0E00,Y
              DEY
              BPL       :CFZERO
              LDA       #1
              STA       $0E58
              STA       $0E59
              STA       $0E5A
              STA       $0E5B
              LDA       #4
              STA       $0E5C
              RTS
NCFGLOAD      JSR       NCFGINIT
              LDA       #0
              STA       NCFOK
              STA       NCFRST
              STA       NCFENA
              STA       NCFSEEN
              STA       NCFSLOT
* Boot-only diagnostic state: operation O/R/K, last ProDOS status.
* $0E5F-$0E60 are below the transient helper and outside the mount table.
              LDA       #'O'
              STA       $0E60
              LDA       #0
              STA       $0E5F
              JSR       $BF00
              DB        $C8                         ; OPEN
              DW        NCFOP
              STA       $0E5F                     ; STA preserves MLI carry
              BCS       NCFDONE
              LDA       NCFREF
              STA       NCFRN
              STA       NCFCLREF
              LDA       #'R'
              STA       $0E60
              JSR       $BF00
              DB        $CA                         ; READ
              DW        NCFRD
              STA       $0E5F                     ; before CLOSE overwrites A
              PHP
              JSR       $BF00
              DB        $CC                         ; CLOSE
              DW        NCFCL
              PLP
              BCS       NCFDONE
              LDA       #'K'
              STA       $0E60
              JSR       NCFPARSE
              LDA       NCFOK
              BEQ       :CFPARSED
              STA       $0E5F
              LDA       #'P'                        ; parser rejected a setting
              STA       $0E60
:CFPARSED     LDA       NCFENA
              BEQ       NCFDONE
              LDA       NCFRST
              BEQ       NCFDONE                 ; RESET=0 means no chip writes
              LDA       NCFSLOT
              CMP       #5
              BNE       NCFDONE
              LDA       NCFSEEN
              CMP       #$1F                     ; all required keys seen
              BNE       NCFDONE
              LDA       NCFOK
              BNE       NCFDONE                 ; nonzero = invalid setting
              JSR       NCFAPPLY
NCFDONE       RTS
NCFPATH       STR       "ZAPPLE2.CNF"               ; resolved under the ProDOS current prefix
NCFOP         DB        3
              DW        NCFPATH
              DW        IOBUF
NCFREF        DB        0
NCFRD         DB        4
NCFRN         DB        0
              DW        $4000                  ; config input is disposable before Z80 load
              DW        $0400                  ; 1024-byte configuration limit
NCFCOUNT      DW        0
NCFCL         DB        1
NCFCLREF      DB        0
NCFENA        DB        0
NCFRST        DB        0
NCFSLOT       DB        0
NCFSEEN       DB        0
NCFOK         DB        0
NCFIDX        DW        0
NCFLEN        DB        0
NCFLINE       DS        80
NCFNUM        DB        0
NCFDEST       EQU       $FA
NCFVALSAVE    DB        0
NCFBITS       DB        0
NCFGW         DS        4
NCFNM         DS        4
NCFMAC        DS        6
NCFIP         DS        4

* Read up to 1024 bytes from temporary $4000-$43FF into 80-byte scratch.
* 5 mapped-drive records staged at $0C00-$0CDB, outside ProDOS IOBUF.
NCFPARSE      LDA       #0
              STA       NCFIDX
              STA       NCFIDX+1
              STA       NCFBITS              ; 0 means outside [NETWORK]
:NCFLINE      LDA       #0
              STA       NCFLEN
:NCFCHAR      LDA       NCFIDX+1
              CMP       NCFCOUNT+1
              BCC       :NCFGET
              BNE       :NCFEND
              LDA       NCFIDX
              CMP       NCFCOUNT
              BCS       :NCFEND
:NCFGET       LDY       NCFIDX
              LDA       NCFIDX+1
              BEQ       :NCFPAGE0
              CMP       #1
              BEQ       :NCFPAGE1
              CMP       #2
              BEQ       :NCFPAGE2
              LDA       $4300,Y
              JMP       :NCFHAVE
:NCFPAGE2     LDA       $4200,Y
              JMP       :NCFHAVE
:NCFPAGE1     LDA       $4100,Y
              JMP       :NCFHAVE
:NCFPAGE0     LDA       $4000,Y
:NCFHAVE      INC       NCFIDX
              BNE       :NCFINC
              INC       NCFIDX+1
:NCFINC       CMP       #$1A
              BEQ       :NCFEND
              CMP       #13
              BEQ       :NCFPROCESS
              CMP       #10
              BEQ       :NCFPROCESS
              LDX       NCFLEN
              CPX       #79
              BCS       :NCFCHAR
              STA       NCFLINE,X
              INC       NCFLEN
              JMP       :NCFCHAR
:NCFPROCESS   LDX       NCFLEN
              LDA       #0
              STA       NCFLINE,X
              JSR       NCFENTRY
              JMP       :NCFLINE
:NCFEND       LDX       NCFLEN
              LDA       #0
              STA       NCFLINE,X
              JMP       NCFENTRY

* Simple uppercase, no-whitespace INI parser. Empty lines and comments OK.
NCFENTRY      LDA       NCFLINE
              BEQ       :NCFRET
              CMP       #';'
              BEQ       :NCFRET
              CMP       #'#'
              BEQ       :NCFRET
              CMP       #'['
              BNE       :NCFKEY
              LDA       #0
              STA       NCFBITS
              LDX       #0
:NCFSECTION   LDA       NCFLINE,X
              CMP       NCFSEC,X
              BNE       :NCFDRVSEC
              CMP       #0
              BEQ       :NCFSELECT
              INX
              BNE       :NCFSECTION
:NCFSELECT    LDA       #1
              STA       NCFBITS
:NCFRET       RTS
:NCFDRVSEC    LDX       #0
:CFDRVS       LDA       NCFLINE,X
              CMP       NCFDSEC,X
              BNE       :NCFSYSSEC
              CMP       #0
              BEQ       :CFDRVOK
              INX
              BNE       :CFDRVS
:CFDRVOK      LDA       #2
              STA       NCFBITS
              RTS
:NCFSYSSEC    LDX       #0
:CFSYSS       LDA       NCFLINE,X
              CMP       NCFSSEC,X
              BNE       :NCFRET
              CMP       #0
              BEQ       :CFSYSOK
              INX
              BNE       :CFSYSS
:CFSYSOK      LDA       #3
              STA       NCFBITS
              RTS
:NCFKEY       LDA       NCFBITS
              CMP       #2
              BNE       :NCFNOTDR
              JSR       NCFDRVPAR
              RTS
:NCFNOTDR     CMP       #3
              BNE       :NCFNOTSY
              JSR       NCFSYSPAR
              RTS
:NCFNOTSY     CMP       #1
              BNE       :NCFRET
              LDX       #0
:NCFTRY       TXA
              ASL
              TAY
              LDA       NCFKPTR,Y
              STA       NCFKP
              INY
              LDA       NCFKPTR,Y
              STA       NCFKP+1
              LDY       #0
:NCFCMP       LDA       (NCFKP),Y
              BEQ       :NCFMATCH
              CMP       NCFLINE,Y
              BNE       :NCFNEXT
              INY
              BNE       :NCFCMP
:NCFMATCH     LDA       NCFLINE,Y
              CMP       #'='
              BNE       :NCFNEXT
              INY
              STY       NCFVALOFF
              TXA
              CMP       #0
              BEQ       :NCFENABLED
              CMP       #1
              BEQ       :NCFRESET
              CMP       #2
              BEQ       :NCFSLOTCFG
              CMP       #3
              BEQ       :NCFIPCFG
              CMP       #4
              BEQ       :NCFNMCFG
              CMP       #5
              BEQ       :NCFGWCFG
              CMP       #6
              BEQ       :NCFMACCFG
              JMP       :NCFDNSCFG
:NCFNEXT      INX
              CPX       #8
              BNE       :NCFTRY
              RTS
:NCFENABLED   JSR       NCFBOOL
              STA       NCFENA
              RTS
:NCFRESET     JSR       NCFBOOL
              STA       NCFRST
              RTS
:NCFSLOTCFG   LDA       NCFLINE,Y
              CMP       #'5'
              BNE       :NCFBAD
              INY
              LDA       NCFLINE,Y
              BNE       :NCFBAD
              LDA       #5
              STA       NCFSLOT
              LDA       #1
              JMP       NCFMARK
:NCFIPCFG     LDA       #<NCFIP
              STA       NCFDEST
              LDA       #>NCFIP
              STA       NCFDEST+1
              LDA       #2
              JMP       NCFIPV
:NCFNMCFG     LDA       #<NCFNM
              STA       NCFDEST
              LDA       #>NCFNM
              STA       NCFDEST+1
              LDA       #4
              JMP       NCFIPV
:NCFGWCFG     LDA       #<NCFGW
              STA       NCFDEST
              LDA       #>NCFGW
              STA       NCFDEST+1
              LDA       #8
              JMP       NCFIPV
:NCFMACCFG    LDA       #<NCFMAC
              STA       NCFDEST
              LDA       #>NCFMAC
              STA       NCFDEST+1
              LDA       #16
              JMP       NCFMACV
:NCFDNSCFG    LDA       #<$0E58
              STA       NCFDEST
              LDA       #>$0E58
              STA       NCFDEST+1
              LDA       #0                      ; optional DNS, not RESET-required
              JMP       NCFIPV
:NCFBAD       LDA       #1
              STA       NCFOK
              RTS
NCFSEC        ASC       '[NETWORK]'
              DB        0
NCFDSEC       ASC       '[DRIVES]'
              DB        0
NCFSSEC       ASC       '[SYSTEM]'
              DB        0
NCFKPTR       DW        NCFKEN,NCFKRE,NCFKSL,NCFKIP,NCFKNM,NCFKGW,NCFKMC,NCFKDNS
NCFKEN        ASC       'ENABLED'
              DB        0
NCFKRE        ASC       'RESET'
              DB        0
NCFKSL        ASC       'SLOT'
              DB        0
NCFKIP        ASC       'IP'
              DB        0
NCFKNM        ASC       'NM'
              DB        0
NCFKGW        ASC       'GW'
              DB        0
NCFKMC        ASC       'MAC'
              DB        0
NCFKDNS       ASC       'DNS'
              DB        0
NCFKP         EQU       $F8
NCFVALOFF     DB        0

* Parse strict single-character boolean and mark invalid input.
NCFBOOL       LDA       NCFLINE,Y
              CMP       #'0'
              BEQ       :NCFZERO
              CMP       #'1'
              BNE       :NCFBADBOOL
              INY
              LDA       NCFLINE,Y
              BNE       :NCFBADBOOL
              LDA       #1
              RTS
:NCFZERO      INY
              LDA       NCFLINE,Y
              BNE       :NCFBADBOOL
              LDA       #0
              RTS
:NCFBADBOOL   LDA       #1
              STA       NCFOK
              LDA       #0
              RTS

* [SYSTEM] SOFTCARD=n; the Uthernet-II card remains in physical slot 5.
* Do not select slot 5 for the Z80 card while the W5100 bridge uses slot 5.
NCFSYSPAR     LDX       #0
:SYSCMP       LDA       NCFSKEY,X
              BEQ       :SYSVAL                   ; keyword finished; line must have '='
              CMP       NCFLINE,X
              BNE       :SYSRET
              INX
              BNE       :SYSCMP
:SYSVAL       LDA       NCFLINE+8
              CMP       #'='
              BNE       :SYSRET
              LDA       NCFLINE+10
              BNE       :SYSRET
              LDA       NCFLINE+9
              CMP       #'1'
              BCC       :SYSBAD
              CMP       #'8'
              BCS       :SYSBAD
              CMP       #'5'
              BEQ       :SYSBAD
              SEC
              SBC       #'0'
              STA       $0E5C
:SYSRET       RTS
:SYSBAD       LDA       #1
              STA       NCFOK
              RTS
NCFSKEY       ASC       'SOFTCARD'
              DB        0

* Tagged mounts: any B:..P: drive, up to 5 simultaneous mappings.
* 44 bytes/entry in $0C00-$0CDB: drive-letter, len, 42 path chars.
* A is fixed for CCP recovery. Paths are absolute, with no trailing slash.
NCFDRVPAR     LDA       NCFLINE+1
              CMP       #'='
              BEQ       :DRVEQ
              RTS
:DRVEQ        LDA       NCFLINE
              CMP       #'A'
              BNE       :DRVB
              JMP       :DRVBAD                 ; forbid remapping A:
:DRVB         CMP       #'B'
              BCS       :DRVP
              RTS
:DRVP         CMP       #'P'+1
              BCC       :DRVVALID
              RTS
:DRVVALID     STA       NCFTAG
              LDX       #0
:DRVSEARCH    LDA       NCFMLO,X
              STA       NCFDEST
              LDA       NCFMHI,X
              STA       NCFDEST+1
              LDY       #0
              LDA       (NCFDEST),Y
              CMP       NCFTAG
              BEQ       :DRVFOUND              ; overwrite an existing mapping
              CMP       #0
              BEQ       :DRVFOUND              ; first unassigned slot
              INX
              CPX       #5
              BCC       :DRVSEARCH
              JMP       :DRVBAD                 ; no more room, don't corrupt memory
:DRVFOUND     LDA       NCFLINE+2
              CMP       #'/'
              BNE       :DRVBAD
              LDY       #2
:DRVLEN       LDA       NCFLINE,Y
              BEQ       :DRVLEND
              CPY       #44                     ; 42 path chars max
              BCS       :DRVBAD
              CMP       #' '
              BEQ       :DRVBAD
              INY
              BNE       :DRVLEN
:DRVLEND      CPY       #3                      ; nonempty /something
              BCC       :DRVBAD
              LDA       NCFLINE-1,Y
              CMP       #'/'                     ; no trailing slash
              BEQ       :DRVBAD
              TYA
              SEC
              SBC       #2
              STA       NCFNUM
              LDY       #0
              LDA       NCFTAG
              STA       (NCFDEST),Y
              INY
              LDA       NCFNUM
              STA       (NCFDEST),Y
              INY
:DRVCOPY      LDA       NCFLINE,Y               ; Y=2 copies character at +2
              STA       (NCFDEST),Y
              INY
              TYA
              SEC
              SBC       #2
              CMP       NCFNUM
              BCC       :DRVCOPY
:DRVRET       RTS
:DRVBAD       LDA       #1
              STA       NCFOK
              RTS
NCFTAG        DB        0
NCFMLO        DB        $00,$2C,$58,$84,$B0
NCFMHI        DB        $0C,$0C,$0C,$0C,$0C

* NCFIPV accepts four strict dotted-decimal octets (0..255).
* Store into temporary per-field arrays. No hardware write until validated.
NCFIPV       STA       NCFMARKBIT
              LDX       #0
:NCFOCT      LDA       #0
              STA       NCFNUM
              STA       NCFDIG
:NCFDIGIT    LDA       NCFLINE,Y
              CMP       #'0'
              BCC       :NCFDONEOCT
              CMP       #'9'+1
              BCS       :NCFDONEOCT
              SEC
              SBC       #'0'
              STA       NCFDIGVAL
              LDA       NCFNUM
              CMP       #26
              BCS       :NCFIPBAD
              ASL
              STA       NCFWORK
              ASL
              ASL
              CLC
              ADC       NCFWORK
              CLC
              ADC       NCFDIGVAL
              BCS       :NCFIPBAD
              STA       NCFNUM
              INC       NCFDIG
              LDA       NCFDIG
              CMP       #4
              BCS       :NCFIPBAD
              INY
              JMP       :NCFDIGIT
:NCFDONEOCT   LDA       NCFDIG
              BEQ       :NCFIPBAD
              LDA       NCFNUM
              STY       NCFVALSAVE
              TXA
              TAY
              LDA       NCFNUM
              STA       (NCFDEST),Y
              LDY       NCFVALSAVE
              INX
              CPX       #4
              BEQ       :NCFIPEND
              LDA       NCFLINE,Y
              CMP       #'.'
              BNE       :NCFIPBAD
              INY
              JMP       :NCFOCT
:NCFIPEND     LDA       NCFLINE,Y
              BNE       :NCFIPBAD
              LDA       NCFMARKBIT
              JMP       NCFMARK
:NCFIPBAD     LDA       #1
              STA       NCFOK
              RTS

* Parse six colon-delimited hexadecimal MAC octets.
NCFMACV       STA       NCFMARKBIT
              LDX       #0
:NCFMACBYTE   JSR       NCFHEX
              BCS       :NCFMACBAD
              ASL
              ASL
              ASL
              ASL
              STA       NCFWORK
              JSR       NCFHEX
              BCS       :NCFMACBAD
              ORA       NCFWORK
              STY       NCFVALSAVE
              TXA
              TAY
              STA       (NCFDEST),Y
              LDY       NCFVALSAVE
              INX
              CPX       #6
              BEQ       :NCFMACEND
              LDA       NCFLINE,Y
              CMP       #':'
              BNE       :NCFMACBAD
              INY
              JMP       :NCFMACBYTE
:NCFMACEND    LDA       NCFLINE,Y
              BNE       :NCFMACBAD
              LDA       NCFMARKBIT
              JMP       NCFMARK
:NCFMACBAD    LDA       #1
              STA       NCFOK
              RTS
NCFHEX        LDA       NCFLINE,Y
              CMP       #'0'
              BCC       :NCFHEXBAD
              CMP       #'9'+1
              BCS       :NCFHEXALPHA
              SEC
              SBC       #'0'
              INY
              CLC
              RTS
:NCFHEXALPHA  CMP       #'A'
              BCC       :NCFHEXBAD
              CMP       #'F'+1
              BCS       :NCFHEXBAD
              SEC
              SBC       #'A'-10
              INY
              CLC
              RTS
:NCFHEXBAD    SEC
              RTS
NCFMARK       ORA       NCFSEEN
              STA       NCFSEEN
              RTS
NCFMARKBIT    DB        0
NCFDIG        DB        0
NCFDIGVAL     DB        0
NCFWORK       DB        0

* Write one W5100 register: A = value, X = register low address.
* Indirect mode register is set only after explicit hardware reset.
NCFWRITE      STX       $C0D6
              STA       $C0D7
              RTS
NCFAPPLY      LDA       #$80                   ; W5100 software RESET
              STA       $C0D4
              LDX       #$FF                   ; bounded reset settling delay
:NCFWAIT      DEX
              BNE       :NCFWAIT
              LDA       #$03                   ; indirect + auto increment
              STA       $C0D4
              LDA       #0
              STA       $C0D5                   ; common registers high byte
              LDX       #1
              LDY       #0
:NCFGWLOOP    LDA       NCFGW,Y
              JSR       NCFWRITE
              INX
              INY
              CPY       #4
              BNE       :NCFGWLOOP
              LDY       #0
:NCFNMLOOP    LDA       NCFNM,Y
              JSR       NCFWRITE
              INX
              INY
              CPY       #4
              BNE       :NCFNMLOOP
              LDY       #0
:NCFMACLOOP   LDA       NCFMAC,Y
              JSR       NCFWRITE
              INX
              INY
              CPY       #6
              BNE       :NCFMACLOOP
              LDY       #0
:NCFIPLOOP    LDA       NCFIP,Y
              JSR       NCFWRITE
              INX
              INY
              CPY       #4
              BNE       :NCFIPLOOP
              LDX       #$1A
              LDA       #$55                   ; RX 2KB per socket
              JSR       NCFWRITE
              INX
              LDA       #$55                   ; TX 2KB per socket
              JMP       NCFWRITE

* Configuration postprocessor is a disposable helper. It cannot live in
* B800-BEFF: the resident driver ends just below ProDOS $BF00.
* Copy it to unused low memory ($0E80) before the Z80 load overwrites
* the boot-only code at $2000. Config staging ends at $0E5C.
NCFGCOPY      LDY       #0
:COPY         LDA       NCFGPOST,Y
              STA       $0E80,Y
              INY
              CPY       #NCFGEND-NCFGPOST
              BNE       :COPY
              RTS

NCFGPOST      LDX       #0
:COPYCFG      LDA       $0C00,X                ; tagged B..P mounts
              STA       $1103,X                ; Z80 MAIN $0103..$01DE
              INX
              CPX       #220                    ; copy all 220, not just one
              BNE       :COPYCFG
              LDX       #3
:COPYDNS      LDA       $0E58,X
              STA       $11DF,X                ; Z80 CFGDNS at $01DF
              DEX
              BPL       :COPYDNS
              LDA       $0E5C
              ORA       #$C0
              STA       MAINLOOP+2
              LDA       $0E5C
              CMP       #4
              BEQ       :CFGRTS
              ORA       #$E0
              STA       $0E5D
              LDA       #0
              STA       $0E5E                 ; number of patched Z80 handoff sites
              STA       $06
              LDA       #$10
              STA       $07
:SCLOOP       LDY       #0
              LDA       ($06),Y
              CMP       #$32
              BNE       :SCNEXT
              INY
              LDA       ($06),Y
              BNE       :SCNEXT
              INY
              LDA       ($06),Y
              CMP       #$E4
              BNE       :SCNEXT
              LDA       $0E5D
              STA       ($06),Y
              INC       $0E5E
:SCNEXT       INC       $06
              BNE       :SCLIMIT
              INC       $07
:SCLIMIT      LDA       $07
              CMP       #$B7                  ; below Z80 top and relocated 6502 driver
              BNE       :SCLOOP
              LDA       $06
              CMP       #$FE
              BCC       :SCLOOP
              LDA       $0E5E
              CMP       #37                   ; exact 6L.5 LD ($E400),A sites
              BEQ       :CFGRTS
              BNE       NCFGFAIL             ; never boot a half-patched system
:CFGRTS       RTS
NCFGFAIL      LDA       #$C4
              STA       MAINLOOP+2
* Runtime address of CFBADMSG in the relocated copy at $0E80.
* Avoid Merlin32's unsupported parenthesized #<(...)/#>(...) syntax.
* CFBADMSG-NCFGPOST is an 8-bit offset inside the helper.
              CLC
              LDA       #$80
              ADC       #CFBADMSG-NCFGPOST
              STA       $06
              LDA       #$0E
              ADC       #0
              STA       $07
              JSR       PRMSG
              JSR       CROUT
              JMP       DONE
CFBADMSG      STR       "Z80 SoftCard slot patch count mismatch"
NCFGEND

RELOC_ST
              ORG       STADDR                         ; Assemble for this origin

* Fixed entry vectors for Z80 calls via CMD=1 / ADDR.
* B800 loader, B803 cooked output, B806 input, B809 bell.
* B80C set terminal mode, B80F raw BIOS output.
              JMP       ENTRY
              JMP       VPUT
              JMP       VGET
              JMP       VBELL
              JMP       VSETMODE                       ; B80C: A=0 VT100, A=1 Soroc (does not clear)
              JMP       VRAWPUT                        ; B80F: raw BIOS/BDOS function 6 output
              JMP       VCLS                           ; B812: CLS reset terminal, clear and home
              JMP       RWPROBE                        ; B815: cached physical bank count (cold probe)
              JMP       RWSELECT                       ; B818: bank selection, A=0/1 (private Z80 caller)
              JMP       VGETMODE                       ; B81B: return terminal personality in A (private Z80)
              JMP       VSTATEPTR                      ; B81E: pointer to contiguous VCOL..VATTR state
              JMP       VSELECT                        ; B821: A=bank, X=physical flag, Y=slot offset
              JMP       W5READ                         ; B824: W5100 read; A=address high, X=low
              JMP       W5WRITE                        ; B827: W5100 write; Y=value
              JMP       VCURON                         ; B82A: draw solid foreground cursor
              JMP       VCUROFF                        ; B82D: restore foreground cursor cell

ENTRY         CLD                                      ; ProDOS/loader entry always uses binary arithmetic
              LDA       #0
              STA       RWACTIVE
              STA       $C073                          ; Start all CP/M sessions from system/video bank 0
              JSR       VINIT                          ; Initialize video hardware and clear screen
* Diagnostic build: omit redundant loader greeting to make room for trace.
              LDA       #$00                           ; Clear ProDOS system bitmap
              LDX       #$00                           ;
:L1           STA       $BF58,X                        ;
              INX                                      ;
              CPX       #21                            ;
              BNE       :L1                            ;
              JSR       OP                             ; Open file
              BEQ       :S1                            ; If zero, no error
              JSR       PRBYTE                         ; Print error code
              JSR       PROPERR                        ; Print "open error"
              JMP       DONE                           ; Quit
:S1           LDA       OP_N                           ; Get file ref num
              STA       RD_N                           ; Store it for READ
              JSR       RD                             ; Read file
              BEQ       :S2                            ; If zero, no error
              JSR       PRBYTE                         ; Print error code
              JSR       PRRDERR                        ; Print "read error"
              JMP       DONE                           ; Quit
:S2           JSR       CL                             ; Close file
              JSR       $0E80                          ; transient config postprocessor (NOT resident in B800)
              JSR       CROUT                          ; load succeeded

MAINLOOP
              STA       SFTCRD                         ; Pause Z80, resume 6502
              JSR       HANDLR                         ; Handle calls made by Z80 code
              JMP       MAINLOOP                       ; Keep on keeping on

* The boot config parser itself was overwritten by the Z80 image.
* Tagged mounts survive at $0C00-$0CDB, network values at $0E00-$0E5C.
* Z80 MAIN $0103 = physical 6502 $1103: five 44-byte tagged mounts.
* DNS uses Z80 MAIN $01DF = physical 6502 $11DF.
* A non-default SoftCard slot also requires changing the Z80 handoff
* operand ($E400) throughout the just-loaded image. The 3-byte absolute
* store opcode is 32 00 E4; avoid modifying kernel after Z80 starts.
* Exit to the ProDOS program selector. CMD=0 in HANDLR reaches here;
* loader errors use the same exit. QUIT normally never returns.
DONE
              LDA       #0
              STA       RWACTIVE                       ; Leave ProDOS selector with default AUX bank
              STA       $C073
              STA       $C000                          ; 80STORE off
              STA       $C002                          ; RAMRD main
              STA       $C004                          ; RAMWRT main
              STA       $C00C                          ; 80COL off (ProDOS selector controls display)
              JSR       CL                             ; Close all remaining open ProDOS files
              INC       $03F4                          ; Invalidate the monitor power-up byte for safe reboot
              JSR       $BF00                          ; ProDOS MLI
              DB        $65                            ; QUIT
              DW        QUIT_PL
              BRK                                      ; Unexpected: QUIT returned
QUIT_PL       DB        4                              ; ProDOS QUIT: 4 parameters
              DB        0                              ; Standard quit type
              DW        0                              ; Reserved
              DB        0                              ; Reserved
              DW        0                              ; Reserved

* Pointer to message is in ZP $06-$07
* Uses ZP $08 as temporary
PRMSG         LDY       #0                             ; Initialize index
              LDA       ($06),Y                        ; Length of string
              STA       $08                            ; Store length in temp
:L1           INY                                      ; Advance char pointer
              TYA                                      ; Save the message index BEFORE loading the character
              PHA                                      ; VPUT modifies Y, so preserve it
              LDA       ($06),Y                        ; Character must still be in A for VPUT
              JSR       VPUT                           ; Print it
              PLA                                      ; Restore string index
              TAY
              DEC       $08                            ; Decrement bytes remaining
              BNE       :L1                            ; Loop
              RTS                                      ;

* Print "open error"
PROPERR       LDA       #<OPERR                        ;
              STA       $06                            ;
              LDA       #>OPERR                        ;
              STA       $07                            ;
              JSR       PRMSG                          ;
              LDA       #<PATH                         ;
              STA       $06                            ;
              LDA       #>PATH                         ;
              STA       $07                            ;
              JSR       PRMSG                          ;
              JSR       CROUT                          ;
              RTS                                      ;

* Print "can't read"
PRRDERR       LDA       #<RDERR                        ;
              STA       $06                            ;
              LDA       #>RDERR                        ;
              STA       $07                            ;
              JSR       PRMSG                          ;
              JSR       CROUT                          ;
              RTS                                      ;

* Successful load: proceed directly to Z80 after newline.

* File to load
PATH          STR       "SOFTCARD80.BIN"

* Messages
OPERR         STR       ": Open "
RDERR         STR       ": Read"
* No loader success string

* ProDOS Parameter List for OPEN
OP            JSR       $BF00                          ; ProDOS call
              DB        $C8                            ; OPEN
              DW        OP_PL                          ; Pointer to parm list
              RTS                                      ;
OP_PL         DB        3                              ; Start of param list; 3 parameters
OP_FP         DW        PATH                           ; Pointer to file path
OP_FBL        DW        IOBUF                          ; Pointer to I/O buffer
OP_N          DB        0                              ; File reference number

* ProDOS Parameter List for READ
RD            JSR       $BF00                          ; ProDOS call
              DB        $CA                            ; READ
              DW        RD_PL                          ; Pointer to parm list
              RTS                                      ;
RD_PL         DB        4                              ; Start of param list; 4 parameters
RD_N          DB        0                              ; File reference number
RD_DB         DW        LDADDR                         ; Data buffer LSB
RD_RC         DW        LDLEN                          ; Request count LSB
RD_TC         DW        $0000                          ; Trans count LSB

* ProDOS Parameter List for CLOSE
CL            JSR       $BF00                          ; ProDOS call
              DB        $CC                            ; CLOSE
              DW        CL_PL                          ; Pointer to parm list
              RTS
CL_PL         DB        1                              ; Start of param list; 1 parameter
CL_N          DB        0                              ; File ref num (0 close all)

* Handle calls made by Z80 code
HANDLR        CLD                                      ; Don't inherit decimal mode from preceding calls
              LDA       #0
              STA       $C073                          ; MLI/video/keyboard always use physical AUX bank 0
              LDA       CMD
              CMP       #0                             ; CMD=0 means continue running 6502 code
              BNE       :CMD1                          ;
              PLA                                      ; Clean up stack
              PLA                                      ; ...
              JMP       DONE                           ; Continue main 6502 routine
:CMD1         CMP       #1                             ; CMD=1 means call 6502 routine then return to Z80
              BNE       :CMD2                          ;
              LDA       FLAGS                          ; Load the flags
              PHA                                      ; Use stack to move A to status
              PLP                                      ; ...
* Bit 3 of the incoming status byte can SET the 6502 decimal flag.
* That makes ADC $1C to $04 produce $26 instead of $20, putting
* background characters into row 4 of the saved AUX screen.  Clear
* decimal mode AFTER PLP, preserving incoming carry/other flags.
              CLD
              LDA       AREG                           ; Load the registers
              LDX       XREG                           ; ...
              LDY       YREG                           ; ...
              JSR       :DOJMP                         ; Hack to achieve an indirect JSR
              STA       AREG                           ; Store the registers
              STX       XREG                           ; ...
              STY       YREG                           ; ...
              PHP                                      ; Move status to A via the stack
              PLA                                      ;
              STA       FLAGS                          ; Store the flags
              JMP       RWRETURN                       ; Restore selected transient bank before Z80 resumes
:CMD2         CMP       #2                             ; CMD=2 means call ProDOS MLI then return to Z80
              BNE       :CMD3                          ;
              JSR       :DOJMP                         ; ProDOS MLI call
              STA       AREG                           ; Store return code
              JMP       RWRETURN
:CMD3         CMP       #3                             ; CMD=3 means peek at the keyboard then ret to Z80
              BNE       :CMD4                          ;
              BIT       $C000                          ; Peek at the keyboard status
              BMI       :C3YES                         ; Branch if keystroke available
              LDA       #0                             ; If no chars, return 0 in AREG
              JMP       :C3DONE                        ; ...
:C3YES        LDA       $C000                          ; Expose keycode without consuming the key
              STA       YREG
              LDA       $C061                          ; Open Apple pushbutton (bit 7 = pressed)
              STA       XREG                           ; modifier accompanying the peeked character
              LDA       #1
:C3DONE       STA       AREG                           ; Store the value for the Z80
              JMP       RWRETURN                       ; Restore transient bank
:CMD4         JSR       VBELL                          ; Beep for error
              BRK                                      ; And drop into monitor
:DOJMP        JMP       (ADDR)                         ;

* Bank selection lives in MAIN memory, not in a banked AUX program.
* RWSELECT is called via $B818, with the selected bank in AREG.
* MLI, keyboard and video use bank 0; restore RWACTIVE on return.
RWSELECT      STA       RWACTIVE
              RTS
RWRETURN      LDA       RWACTIVE
              STA       $C073
              RTS
RWACTIVE      DB        0
RWCOUNT       DB        1                              ; Filled by disposable loader probe before ENTRY


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
*   Soroc IQ-120:    ESC '=', row+$20, column+$20
* VMODE 0=VT100 (Z80 parser), 1=Soroc (default).
* Cursor address parameters are consumed even when malformed.
* Cooked CR implies newline (existing CCP convention); cooked CR+LF
* advances once. Raw BIOS CR only returns to column 0; LF goes down.
* Soroc ESC ')' starts a protected field; ESC '(' ends it.
* Represent protected fields with inverse video (IQ-120 used dim intensity).
* Full protect-mode navigation, graphics and auxiliary port are not emulated.
***************************************************

* CLS restores a known text-screen state but preserves Soroc/VT100 mode.
* Called from the MAIN-memory CCP via the public B812 vector.
VCLS
              LDA       #0
              STA       VSTATE                         ; abandon incomplete escape/coordinate sequence
              STA       VCRP                           ; clear pending cooked CR/LF state
              STA       VATTR                          ; normal video regardless of selected personality
              STA       $C000                          ; 80STORE off
              STA       $C002                          ; MAIN reads
              STA       $C004                          ; MAIN writes
              BIT       $C054                          ; PAGE1
              BIT       $C051                          ; TEXT on
              BIT       $C052                          ; full-screen
              STA       $C00D                          ; 80COL on
              STA       $C00F                          ; alternate/lowercase character set
              JMP       VCLEAR                         ; clears both banks and puts cursor at 0,0

VINIT
              LDA       #1
              STA       VMODE                          ; Default to Soroc
              LDA       #0
              STA       VVRDY
              LDA       RWCOUNT
              CMP       #3
              BCC       :VNORW
              INC       VVRDY
:VNORW
              LDA       #2
              LDX       #1
              LDY       #$1C
              JSR       VSELECT                        ; bank 2, foreground, slot 0
              LDA       #0
              STA       VSTATE                         ; Parser idle
              STA       VCRP                           ; No pending CR/LF pair
              STA       VATTR                          ; Reset inverse video
              STA       $C000                          ; 80STORE off
              STA       $C002                          ; RAMRD main
              STA       $C004                          ; RAMWRT main
              BIT       $C054                          ; PAGE1
              BIT       $C051                          ; TEXT on
              BIT       $C052                          ; full screen
              STA       $C00D                          ; 80COL on
              STA       $C00F                          ; alternate charset (lowercase)
* VSELECT initialized the BASIC control bytes above
              JMP       VCLEAR

* A=0 selects Z80 VT100 parser, A=1 selects Soroc. Ignore others.
* Public vector at B80C. Mode change retains screen and cursor.
VSETMODE      CMP       #2
              BCC       :LONG5
              RTS
:LONG5
              STA       VMODE
              LDA       #0
              STA       VSTATE
              STA       VCRP
              STA       VATTR                          ; Reset inverse video on terminal change
              JMP       VMBASIC                        ; Keep MBASIC's terminal control table in sync

* Apple CP/M Microsoft BASIC-80 5.2 expects BIOS video control bytes
* at Z80 $F396-$F39E = 6502 $0396-$039E (SoftCard memory map).
* $0396 = coordinate bias; bit 7 reverses XY ordering.
* $0397 = prefix for high-bit-set commands.
* $0398 = HOME (table entry 1).
* $039E = position cursor (table entry 7).
* The other five commands are unsupported: set to 0 (do nothing).
* This is 6502 page-3 RAM, outside the Z80 TPA. No MBASIC patch.
VMBASIC       LDX       #5
              LDA       #0
:BLANK        STA       $0399,X                        ; Clear $0399..$039E; set $039E below
              DEX
              BPL       :BLANK
              LDA       #$1B
              STA       $0397                          ; ESC prefix
* MBASIC always receives Soroc commands, even with VT100 selected.
              LDA       #$20
              STA       $0396                          ; Soroc row/column bias
              LDA       #$AA
              STA       $0398                          ; ESC '*': clear screen
              LDA       #$BD
              STA       $039E                          ; ESC '=': cursor position
              RTS

* Raw output from BIOS CONOUT / BDOS function 6. Real terminals
* interpret CR and LF independently; avoid cooked CCP newline policy.
VRAWPUT       AND       #$7F
              CMP       #$0D
              BNE       :RC1
              LDA       #0
              STA       VCRP
              STA       VCOL
              RTS
:RC1          CMP       #$0A
              BNE       :RC2
              LDA       #0
              STA       VCRP
              JMP       VDOWN
:RC2          JMP       VPUT

* Cooked output used by BDOS function 2, CCP, loader, etc.
* The Z80 VT100 parser translates CSI to Soroc-compatible primitives.
VPUT          AND       #$7F
              CMP       #$0A
              BEQ       :KEEPC
              PHA
              LDA       #0
              STA       VCRP
              PLA
:KEEPC        LDX       VSTATE
              BEQ       :LONG11
              JMP       VSEQ
:LONG11
              CMP       #$1B
              BEQ       VESC
              CMP       #$20
              BCC       :LONG0
              JMP       VPRINT
:LONG0
              CMP       #$0A
              BNE       :LONG1
              JMP       VLF
:LONG1
              CMP       #$0D
              BNE       :LONG2
              JMP       VCR
:LONG2
              CMP       #$08
              BNE       :LONG3
              JMP       VBACK
:LONG3
              CMP       #$09
              BNE       :LONG4
              JMP       VTAB
:LONG4
              CMP       #$07
              BNE       :VCTL
              JMP       VBELL
:VCTL         CMP       #$0B                           ; Soroc ^K cursor up
              BNE       :LONG9
              JMP       VUP
:LONG9        CMP       #$0C                           ; Soroc ^L cursor right
              BNE       :LONG10
              JMP       VRIGHT
:LONG10       CMP       #$1E                           ; Soroc ^^ home
              BNE       VDONE
              JMP       VHOME
VDONE         RTS

VESC          LDA       #1
              STA       VSTATE
              RTS
VPOS          LDA       #2
              STA       VSTATE
              RTS

* Parser states 1=ESC, 2=first coordinate, 3=second coordinate.
VSEQ          CPX       #1
              BEQ       VESCCMD
              SEC
              SBC       #$20
              CPX       #2
              BNE       :VP2
              STA       VCOORD
              INC       VSTATE
              RTS
:VP2          LDY       #0
              STY       VSTATE
              CMP       #80
              BCS       VDONE
              LDY       VCOORD
              CPY       #24
              BCS       VDONE
              STA       VCOL
              STY       VROW
              RTS

* ESC sequences. Unrecognised commands are silently consumed.
VESCCMD       LDY       #0
              STY       VSTATE
              CMP       #')'                           ; IQ-120 start WRITE PROTECT (dim)
              BNE       :SINV1
              LDA       #1                             ; inverse approximates dim protected text
              STA       VATTR
              RTS
:SINV1        CMP       #'('                           ; IQ-120 end WRITE PROTECT
              BNE       :SINV2
              LDA       #0
              STA       VATTR
              RTS
:SINV2        CMP       #'='
              BNE       :SINV3
              JMP       VPOS
:SINV3        CMP       #'*'
              BNE       :S1
              LDA       #0                             ; full screen clear resets write protection
              STA       VATTR
              JMP       VCLEAR
:S1           CMP       #'+'
              BNE       :S2
              JMP       VCLEAR
:S2           CMP       #'T'
              BNE       :S3
              JMP       VEOL
:S3           CMP       #'Y'
              BEQ       :EP
              CMP       #'V'                           ; Some IQ-120 documentation calls this Erase Page.
              BEQ       :LONG14
              RTS
:LONG14
:EP           JMP       VEOP

VHOME         LDA       #0
              STA       VCOL
              STA       VROW
              RTS

* Preserve the loader/BDOS convention of CR as a newline.
* Unlike the old driver, a lone LF now moves down; CR+LF moves once.
VCR           LDA       #1
              STA       VCRP
              LDA       #0
              STA       VCOL
              JMP       VDOWN
VLF           LDA       VCRP
              BEQ       VDOWN
              LDA       #0
              STA       VCRP
              RTS

VUP           LDA       VROW
              BNE       :LONG15
              RTS
:LONG15
              DEC       VROW
              RTS
VRIGHT        LDA       VCOL
              CMP       #79
              BCC       :LONG16
              RTS
:LONG16
              INC       VCOL
              RTS
VBACK         LDA       VCOL
              BNE       :LONG17
              RTS
:LONG17
              DEC       VCOL
              RTS

VTAB          LDA       VCOL
              AND       #7
              EOR       #7
              CLC
              ADC       #1
              STA       VTCNT
:VT1          LDA       #' '
              JSR       VPRINT
              DEC       VTCNT
              BNE       :VT1
              RTS

* Apple IIe ALTCHARSET inverse uses $00-$3F and $60-$7F.
* $40-$5F is MouseText, so fold uppercase into $00-$1F.
VPRINT        LDX       VATTR
              BEQ       :VNORM
              CMP       #$60
              BCS       :VSHOW
              AND       #$3F
              JMP       :VSHOW
:VNORM        ORA       #$80
:VSHOW        JSR       VDRAW
              INC       VCOL
              LDA       VCOL
              CMP       #80
              BCS       :LONG18
              RTS
:LONG18
              LDA       #0
              STA       VCOL
VDOWN         INC       VROW
              LDA       VROW
              CMP       #24
              BCS       :LONG19
              RTS
:LONG19
              DEC       VROW
              JMP       VSCROLL

* Erase operations leave the original cursor position unchanged.
* Reuse VDRAW for both physical halves rather than duplicate bank logic.
VEOL          LDA       VCOL
              PHA
:EL1          LDA       #$A0
              JSR       VDRAW
              INC       VCOL
              LDA       VCOL
              CMP       #80
              BCC       :EL1
              PLA
              STA       VCOL
              RTS

VEOP          LDA       VROW
              PHA
              LDA       VCOL
              PHA
              JSR       VEOL
:EP1          INC       VROW
              LDA       VROW
              CMP       #24
              BCS       :EP2
              LDA       #0
              STA       VCOL
              JSR       VEOL
              JMP       :EP1
:EP2          PLA
              STA       VCOL
              PLA
              STA       VROW
              RTS

* Set up self-modifying absolute-indexed access to one text row.
* Returns Y = column/2 and 80STORE on, PAGE2 selecting bank.
VADDR         LDX       VROW
              LDA       VROWLO,X
              STA       VSTORE+1
              STA       VLOAD+1
              STA       VBSTORE+1
              LDA       VROWHI,X
              STA       VSTORE+2
              STA       VLOAD+2
              CLC
              ADC       VVOFF
              STA       VBSTORE+2
              LDA       VCOL
              LSR
              TAY
              STA       $C001                          ; 80STORE on (writes only)
              LDA       VCOL
              AND       #1
              BNE       :VA1
    ; Even column is physical AUX, second 1K of our snapshot.
              LDA       VBSTORE+2
              CLC
              ADC       #4
              STA       VBSTORE+2
              BIT       $C055                          ; even column: auxiliary text page 1
              RTS
:VA1          BIT       $C054                          ; odd column: main text page 1
              RTS

* Foreground output uses physical video only (saved at manual tab switch).
* Background output updates only that session's virtual screen snapshot.
    ; The $2000-$3FFF HGR aperture maps into the selected snapshot bank.
VDRAW         PHA
              JSR       VADDR
              PLA
              LDX       VPHY
              BEQ       :VBG
VSTORE        STA       $0400,Y                        ; physical foreground text half
    ; Foreground image is captured by VSSAVE on a manual tab switch.
    ; Avoid touching the virtual bank while this tab owns the screen.
              BIT       $C054
              STA       $C000                          ; 80STORE off
              RTS
:VBG          PHA
* The row table / physical operand are correct, but trace showed
* a stale VBSTORE high byte ($26 vs expected $20 for row 0, col 1).
* Rebuild the backing operand immediately before the banked STORE,
* using the PHYSICAL operand already computed by VADDR.  Avoid
* relying on a persistent self-modifying virtual operand across calls.
* Preserve A (character) on stack and Y (screen byte index) unchanged.
              LDA       VSTORE+1
              STA       VBSTORE+1
              LDA       VSTORE+2
              CLC
              ADC       VVOFF
              STA       VBSTORE+2
              LDA       VCOL
              AND       #1
              BNE       :VBADDRDONE
              LDA       VBSTORE+2
              CLC
              ADC       #4                             ; even column: AUX half of saved 80-col screen
              STA       VBSTORE+2
:VBADDRDONE
              BIT       $C054
              STA       $C000                          ; leave 80STORE off before snapshot window
              LDA       VVRDY
              BEQ       :VEND
              LDA       VVBANK
              STA       $C073
              STA       $C001                          ; 80STORE on
              BIT       $C057                          ; HIRES on
              BIT       $C055                          ; PAGE2: AUX HGR snapshot window
              PLA
VBSTORE       STA       $2000,Y                        ; patched snapshot row/half/slot
              PHA
              BIT       $C054                          ; PAGE1
              BIT       $C056                          ; HIRES off
              STA       $C000                          ; 80STORE off
              LDA       #0
              STA       $C073                          ; ALWAYS return physical bank 0
:VEND         PLA
              RTS

VPEEK         JSR       VADDR
VLOAD         LDA       $0400,Y                        ; operand updated by VADDR
              PHA
              BIT       $C054                          ; PAGE1/main selected
              STA       $C000                          ; 80STORE off (write-only switch)
              PLA
              RTS

* Direct keyboard access; don't call RDKEY or the 80-column ROM.
* Keep the original byte under the cursor, including its attributes.
VGET          JSR       VPEEK
              STA       VUNDER
              JSR       VCURINV                         ; same inverse-video logic as polling cursor
              JSR       VDRAW
:VGWAIT       LDA       $C000                          ; keyboard latch; bit 7 means key ready
              BPL       :VGWAIT
              PHA
              LDA       $C061                          ; sample Open Apple BEFORE strobe is cleared
              STA       VKMOD
              BIT       $C010                          ; clear keyboard strobe
              LDA       VUNDER
              JSR       VDRAW                          ; restore original character
              PLA
              LDX       VKMOD                          ; HANDLR returns X in XREG alongside AREG keycode
              RTS

* Physical nonblinking cursor for Z80's polling CCP/foreground sessions.
* Called via B82A/B82D.  Unlike the old Z80 CUON/CUOFF, these use
* VPEEK/VDRAW rather than direct Z80 banking/video soft-switch writes.
* VCOL/VROW can change between calls, so remember cursor coordinates.
* Only the foreground ever draws the physical cursor. Z80 CUACTIVE
* guards repeated ON calls; the 6502 guard is only needed for OFF.
VCURON        LDA       VPHY
              BEQ       :VCDONE                        ; never draw in a background snapshot
              LDA       VROW
              CMP       #24
              BCS       :VCDONE                        ; guard invalid physical screen row
              LDA       VCOL
              STA       VCURCOL
              LDA       VROW
              STA       VCURROW
              JSR       VPEEK
              STA       VCURUND
              JSR       VCURINV
              JSR       VDRAW
              INC       VCURVIS
:VCDONE       RTS

* Restore the original cell even if the active session's coordinates
* have since moved. Temporarily force physical output; restore VPHY.
VCUROFF       LDA       VCURVIS
              BEQ       :VCDONE
              LDA       #0
              STA       VCURVIS
              LDA       VCOL
              PHA
              LDA       VROW
              PHA
              LDA       VPHY
              PHA
              LDA       #1
              STA       VPHY
              LDA       VCURCOL
              STA       VCOL
              LDA       VCURROW
              STA       VROW
              LDA       VCURUND
              JSR       VDRAW
              PLA
              STA       VPHY
              PLA
              STA       VROW
              PLA
              STA       VCOL
:VCDONE       RTS

* Exactly the original VGET video-attribute transformation.
* A = original screen byte; returns A = same character, opposite video.
VCURINV       BMI       :VGNORM                        ; Normal byte ($80-$FF): make inverse
              CMP       #$20
              BCC       :VGUP                          ; Inverse uppercase -> normal uppercase
              ORA       #$80                           ; Inverse punctuation/lowercase -> normal
              BNE       :VGSHOW
:VGUP         ORA       #$C0
              BNE       :VGSHOW
:VGNORM       AND       #$7F
              CMP       #$60
              BCS       :VGSHOW
              AND       #$3F                           ; Avoid MouseText when inverting uppercase
:VGSHOW       RTS

VBELL         BIT       $C030                          ; click speaker
              RTS

* Foreground clears physical text; background clears its snapshot only.
VCLEAR        LDA       #0
              STA       VCOL
              STA       VROW
              LDX       VPHY
              BNE       :VCPHY
              LDA       VVRDY
              BEQ       :VCDONE
              JSR       VBCLR
              JMP       :VCDONE
:VCPHY        LDA       #0
              STA       $C001                          ; 80STORE on
              BIT       $C054                          ; main
              JSR       VCLRBANK
              BIT       $C055                          ; auxiliary
              JSR       VCLRBANK
              BIT       $C054                          ; main again
              STA       $C000                          ; 80STORE off
:VCDONE       RTS

* Clear the whole 2KB of the selected session's snapshot: main+aux.
* Both halves occupy [VVOFF .. VVOFF+7]; old +4 overwrote NEXT tab.
* Clear 2KB via a zero-page pointer, no unrolled writes.
* $EB/$EC is the 6502 ADDR dispatch pointer. It is scratch after
* the indirect JMP into VPUT/VCLS; Z80 resets it before its next call.
VBCLR         LDA       VVBANK
              STA       $C073
              STA       $C001
              BIT       $C057
              BIT       $C055
              LDA       #0
              STA       $EB
              LDA       VVOFF                          ; high-byte OFFSET from $0400, not absolute address
              CLC
              ADC       #4                             ; $0400 + VVOFF*256 = backing screen base
              STA       $EC
              LDX       #8
              LDY       #0
:VBPAGE
              LDA       #$A0
:VBLOOP
              STA       ($EB),Y
              INY
              BNE       :VBLOOP
              INC       $EC
              DEX
              BNE       :VBPAGE
              BIT       $C054
              BIT       $C056
              STA       $C000
              LDA       #0
              STA       $C073
              RTS

VCLRBANK      LDA       #$A0                           ; normal video space
              LDX       #0
:VCL1         STA       $0400,X
              STA       $0500,X
              STA       $0600,X
              STA       $0700,X
              INX
              BNE       :VCL1
              RTS

* Scroll only the active destination: physical if fg, snapshot if bg.
* VSHIFT is the high-byte delta from the physical $0400 text page.
VSCROLL       LDX       VPHY
              BNE       :VSPHY
              LDA       VVRDY
              BEQ       :VSEND
              LDA       VVBANK
              STA       $C073
              STA       $C001
              BIT       $C057
              BIT       $C055
              LDA       VVOFF
              STA       VSHIFT
              JSR       VSCBANK                        ; first stored 1K: main
              LDA       VVOFF
              CLC
              ADC       #4
              STA       VSHIFT
              JSR       VSCBANK                        ; second stored 1K: auxiliary
              BIT       $C054
              BIT       $C056
              LDA       #0
              STA       $C000
              STA       $C073
              RTS                                      ; background scroll MUST NOT fall into physical path
:VSPHY
              LDA       #0
              STA       VSHIFT
              STA       $C001                          ; 80STORE on
              BIT       $C054
              JSR       VSCBANK
              BIT       $C055
              JSR       VSCBANK
              BIT       $C054
              STA       $C000                          ; 80STORE off
:VSEND        RTS

VSCBANK       LDX       #0
VSR1          LDA       VROWLO+1,X                     ; row below, source
              STA       VSRC+1
              LDA       VROWHI+1,X
              CLC
              ADC       VSHIFT
              STA       VSRC+2
              LDA       VROWLO,X                       ; current row, destination
              STA       VDST+1
              LDA       VROWHI,X
              CLC
              ADC       VSHIFT
              STA       VDST+2
              LDY       #39
VSR2
VSRC          LDA       $0480,Y                        ; patched source
VDST          STA       $0400,Y                        ; patched destination
              DEY
              BPL       VSR2
              INX
              CPX       #23
              BNE       VSR1
              LDA       VSHIFT
              CLC
              ADC       #7
              STA       VSBOT+2
              LDA       #$A0
              LDY       #39
:VSR3
VSBOT         STA       $07D0,Y                        ; bottom text row (row 23)
              DEY
              BPL       :VSR3
              RTS

* Interleaved Apple II text row addresses (main AND auxiliary).
VROWLO        DB        $00,$80,$00,$80,$00,$80,$00,$80
              DB        $28,$A8,$28,$A8,$28,$A8,$28,$A8
              DB        $50,$D0,$50,$D0,$50,$D0,$50,$D0
VROWHI        DB        $04,$04,$05,$05,$06,$06,$07,$07
              DB        $04,$04,$05,$05,$06,$06,$07,$07
              DB        $04,$04,$05,$05,$06,$06,$07,$07

VCOL          DB        0
VROW          DB        0
VTCNT         DB        0
VUNDER        DB        0
VMODE         DB        1                              ; 0 VT100 via Z80, 1 Soroc
VSTATE        DB        0                              ; 0 idle, 1 ESC, 2 coord1, 3 coord2
VCOORD        DB        0
VCRP          DB        0                              ; Suppress second half of CR/LF pair
VATTR         DB        0                              ; IQ-120 ESC ')' protect on, ESC '(' off
VKMOD         DB        0                              ; last blocking key's Open Apple state (outside saved video)
VPHY          DB        1                              ; running session owns physical screen
VVBANK        DB        2                              ; reserved RamWorks snapshot bank
VVOFF         DB        $1C                            ; high-byte delta for first snapshot half
VSHIFT        DB        0                              ; scroll destination high-byte delta
VVRDY         DB        0                              ; nonzero when physical bank 2 exists
VCURVIS       DB        0                              ; physical polling cursor displayed
VCURCOL       DB        0                              ; saved col at draw time
VCURROW       DB        0                              ; saved row at draw time
VCURUND       DB        0                              ; screen byte beneath cursor

* Loader diagnostics without ROM I/O.
CROUT         LDA       #$0D
              JMP       VPUT

PRBYTE        PHA
              LSR
              LSR
              LSR
              LSR
              JSR       PRHEX
              PLA
              AND       #$0F
PRHEX         CMP       #10
              BCC       :PH1
              CLC
              ADC       #7
:PH1          CLC
              ADC       #'0'
              JMP       VPUT
* Return the bank count saved by the one-time pre-relocation loader probe.
* Do not test banks again here: sessions may now contain live programs.
RWPROBE       LDA       RWCOUNT
              RTS

* Query terminal mode without resetting it. Used by TAB session state.
VGETMODE      LDA       VMODE
              RTS

* Return physical address of the 9-byte contiguous terminal state.
* Z80 main code converts Apple Bxxx to Z80 Axxx (minus $1000).
VSTATEPTR     LDA       #<VCOL
              LDX       #>VCOL
              RTS

* B821: A=snapshot bank, X=foreground flag, Y=slot high delta.
* No screen copy; caller computes addressing from its TABMODE.
VSELECT       STA       VVBANK
              STX       VPHY
              STY       VVOFF
              JMP       VMBASIC                        ; refresh per-task MBASIC control bytes

* Uthernet-II socket register access, native 6502, slot 5.
* Called from Z80 through CMD=1, ADDR=$B824/$B827. In HANDLR,
* Z80-supplied registers arrive in 6502 A/X/Y. Return A via AREG.
* W5100 auto increment is harmless: the caller selects address on
* EVERY access. Do not reset W5100 or modify VEDRIVE's socket 0.
* These routines live in MAIN and touch only $C0D5-$C0D7.
W5READ        STA       $C0D5                          ; indirect address high
              STX       $C0D6                          ; indirect address low
              LDA       $C0D7                          ; selected register byte
              RTS
W5WRITE       STA       $C0D5
              STX       $C0D6
              TYA                                      ; supplied data byte
              STA       $C0D7
              RTS

RELOC_EN
