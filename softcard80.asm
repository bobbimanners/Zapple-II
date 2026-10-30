;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Z80 code running on Softcard
; Implements CP/M style BDOS interface
; Requires the companion SOFTCARD65 6502 code
; Assemble using Udo Munk's Z80asm.
; Tabstops every 4 chars.
; Bobbi 2019, 2026
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; References:
; 1) BDOS System Calls
;    https://www.seasip.info/Cpm/bdos.html
; 2) Programmer's CP/M Handbook - Johnson-Laird
; 3) ProDOS 8 Technical Reference Manual
;    http://www.easy68k.com/paulrsm/6502/PDOS8TRM.HTM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; BDOS TODOs
; ----------
; ProDOS handles: two-slot, pathname-keyed cache (see CACHE_* near $A200).
; Logical CP/M open state is S1=$A0|USER; S2 stays application-owned.
; TODO: Implement missing BDOS system calls:
;        - RS232 (A_READ, A_WRITE)
;        - Printer (LWRITE)
; IOBYTE routes console, reader, punch and list to Apple firmware.
; User areas are mapped to per-user ProDOS directories.
;

BDOSADDR      EQU       08100H                         ;
STCKTOP       EQU       0A800H                         ; Stack still ends at $A800; base-69 uses its low region

SOFTCARD      EQU       0E400H                         ; Softcard in slot 4 ($C400)


OFFSET        EQU       01000H                         ; Offset to add to Z80 addr to get 6502
                                                       ; address. Correct for Z80 addr <= 0AFFFH

; 6502 zero page, in Z80 address space
CMD           EQU       0F006H                         ; 6502 $06
AREG          EQU       0F007H                         ; 6502 $07
XREG          EQU       0F008H                         ; 6502 $08
YREG          EQU       0F009H                         ; 6502 $09
ADDR          EQU       0F0EBH                         ; 6502 $EB (LSB)
ADDRH         EQU       0F0ECH                         ; 6502 $EC (MSB)

; Addresses of 6502 routines, in 6502 address space
COUT          EQU       0B803H                         ; Direct video output entry (B803)
RDKEY         EQU       0B806H                         ; Direct keyboard/cursor entry (B806)
BELL          EQU       0B809H                         ; Direct speaker click entry (B809)
RAWOUT        EQU       0B80FH                         ; Raw BIOS console entry (B80F)
VTASK         EQU       0B821H                         ; 6502 select running/foreground display
; B80C selects Soroc (1) or the resident Z80 VT100 translator (0).
; The VT parser lives in reclaimed MAIN RAM, not the 6502 video bank.

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Entry point when Z80 cold starts is 0000H
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

              ORG       0000H
              JP        BDOSINIT                       ; Initialize BDOS

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; See obsolescence.wix.com/obsolescence/cpm-internals for info
; on low storage usage ...
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

IOBYTE        DEFB      0                              ; Maps virtual to real devices

CURDRV        DEFB      0                              ; LS 4 bits; Current drive 0=A: etc
                                                       ; MS 4 bits: Current user number

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; BDOS entry point must be at address 0005H for CP/M compatibility
; Function to invoke is passed in C
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

BDOS          JP        BDOSENTRY                      ; Keep page-zero BDOS vector within $81xx

RVEC1         DEFW      0000H                          ; Restart vector 1
RVEC2         DEFW      0000H                          ; Restart vector 2
RVEC3         DEFW      0000H                          ; Restart vector 3
RVEC4         DEFW      0000H                          ; Restart vector 4
RVEC5         DEFW      0000H                          ; Restart vector 5
RVEC6         DEFW      0000H                          ; Restart vector 6
RVEC7         DEFW      0000H                          ; Restart vector 7

; Space for private BDOS data (implementation dependent) up to 005BH
DMAADDR       DEFW      0080H                          ; DMA address defaults to FILEBUF (0080H)
LOGVEC        DEFW      0000H                          ; Vector of logged in drives
ROVEC         DEFW      0000H                          ; Vector of read-only drives
TEMPWORD      DEFW      0000H                          ; Used by routines as a scratch space
TEMPBYTE      DEFB      0                              ; Used by routines as a scratch space
; End of private, implementation dependent space

              ORG       005CH                          ; Standard addr of 32 byte FCB1
FCB1                        ; File control block #1
FCB1DRV       DEFB      00H                            ; FCB Drive (0 current, 1 A:, 2 B: etc)
FCB1NAM       DEFM      'FILENAMEEXT'                  ; FCB filename and extension
FCB1EX        DEFB      00H                            ; FCB extent field
FCB1S1        DEFB      00H                            ; FCB S1 field
FCB1S2        DEFB      00H                            ; FCB S2 field
FCB1RC        DEFB      00H                            ; FCB RC field (# recs used this extent)
FCB1MAP                     ; Map of blocks in file (overlaps FCB2)

              ORG       006CH                          ; Standard addr of 32 byte FCB2
FCB2                        ; File control block #2
FCB2DRV       DEFB      00H                            ; FCB Drive (0 current, 1 A:, 2 B: etc)
FCB2NAM       DEFM      'FILENAMEEXT'                  ; FCB filename and extension
FCB2EX        DEFB      00H                            ; FCB extent field
FCB2S1        DEFB      00H                            ; FCB S1 field
FCB2S2        DEFB      00H                            ; FCB S2 field
FCB2RC        DEFB      00H                            ; FCB RC field (# recs used this extent)
FCB2MAP                     ; Map of blocks in file (overlaps buffer)

              ORG       0080H                          ; Standard addr of 128 byte File Buffer
FILEBUF       DEFS      128                            ; Command args go here too (Pascal string)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; The application program proper starts at 0100H
; in order to be compatible with CP/M .COM programs
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

              ORG       0100H

PROGSTRT      JP        BDOSINIT                       ; direct entry must cold-initialize system before CCP startup

; Phase 2: small MAIN-only bank-control helper and shell command.
; MAIN $0200..$02FF is unused by AUX transients and by SAVE's
; temporary $1000..$3FFF staging. No program ever runs here in AUX.
              ORG       00200H
; A = AUX bank number. 6502 vector $B818 selects it and records it.
AXBANK        LD        (AREG),A
              LD        HL,0B818H
              LD        (ADDR),HL
              LD        A,1
              LD        (CMD),A
              LD        (SOFTCARD),A
              RET

; Logical sessions 0..F use physical banks 0,1,3,4,6..9,11..14,16..19.
; Each group of four shares one otherwise reserved screen-snapshot bank.
TABPHYS       LD        HL,TABPHY
              LD        E,A
              LD        D,0
              ADD       HL,DE
              LD        A,(HL)
              RET
TABPHY        DEFB      0,1,3,4,6,7,8,9,11,12,13,14,16,17,18,19
; Find the first bank that does not physically exist, capped at 16 tabs.
RWDETECT      LD        HL,0B815H
              LD        (ADDR),HL
              LD        A,1
              LD        (CMD),A
              LD        (SOFTCARD),A
              LD        A,(AREG)
              OR        A
              JR        NZ,RWD_OK
              INC       A                              ; no card still has ordinary AUX bank 0
RWD_OK        LD        (RWTOTAL),A
              CP        3
              JR        NC,RWD_MULTI
              LD        A,1                            ; no snapshot bank: single console only
              LD        (TABCOUNT),A
              RET
RWD_MULTI     LD        A,(RWTOTAL)
              LD        C,A
              LD        HL,TABPHY
              LD        B,0
RWD_NEXT      LD        A,(HL)
              CP        C
              JR        NC,RWD_DONE
              INC       B
              INC       HL
              LD        A,B
              CP        16
              JR        C,RWD_NEXT
RWD_DONE      LD        A,B
              LD        (TABCOUNT),A
              RET
RWTOTAL       DEFB      1
TABCOUNT      DEFB      1
TABREQ        DEFB      0FFH                           ; Open Apple + 0..9/A..F/arrows; FF = none
RWREPORT      LD        DE,RWMSG1
              CALL      C_WRITESTR
              LD        A,(RWTOTAL)
              CALL      RWDECIMAL
              LD        DE,RWMSG2
              CALL      C_WRITESTR
              LD        A,(TABCOUNT)
              CALL      RWDECIMAL
              LD        DE,RWMSG3
              CALL      C_WRITESTR
              LD        A,'A'                          ; MouseText Open Apple, physical $41
              CALL      MTCHAR
              LD        DE,RWMSG4
              CALL      C_WRITESTR
              LD        A,'H'                          ; MouseText left arrow, physical $48
              CALL      MTCHAR
              LD        A,'U'                          ; MouseText right arrow, physical $55
              CALL      MTCHAR
              LD        DE,RWMSG5
              JP        C_WRITESTR
RWMSG1        DEFM      'RamWorks: '
              DEFB      '$'
RWMSG2        DEFM      ' banks '
              DEFB      '$'
; Print unsigned 0..255 without leading zeroes.
RWDECIMAL     LD        B,'0'
RWD_HUND      CP        100
              JR        C,RWD_TENS
              SUB       100
              INC       B
              JR        RWD_HUND
RWD_TENS      LD        C,0                            ; hundreds digit was printed?
              PUSH      AF
              LD        A,B
              CP        '0'
              JR        Z,RWD_T0
              LD        C,1
              LD        E,A
              PUSH      BC
              CALL      C_WRITE
              POP       BC
RWD_T0        POP       AF
              LD        B,'0'
RWD_TLOOP     CP        10
              JR        C,RWD_ONES
              SUB       10
              INC       B
              JR        RWD_TLOOP
RWD_ONES      PUSH      AF
              LD        A,B
              CP        '0'
              JR        NZ,RWD_TPRINT
              LD        A,C
              OR        A
              JR        Z,RWD_TEND
              LD        A,'0'                          ; display 100, not 10
RWD_TPRINT    LD        E,A
              CALL      C_WRITE
RWD_TEND      POP       AF
              ADD       A,'0'
              LD        E,A
              JP        C_WRITE

              ORG       00300H
; A queued Open Apple hotkey returns immediately, with no key passed
; to an application. CCP discards the current unfinished command line.
CR_SELCMD     XOR       A
              LD        (IX+1),A
              RET

; Fullscreen applications poll BDOS 11 or BIOS CONST before reading a
; character. CMD=3 peeks at $C000 and samples Open Apple ($C061) in XREG.
; Valid shortcuts consume the keyboard strobe directly, without drawing
; a cursor or waiting for another character. Ordinary keys are untouched.
; F3 is the private deferred-status marker on suspension.
TSKSTAT       CALL      SCHISFG
              JR        Z,TSSTFG
              XOR       A
              LD        L,A
              RET
TSSTFG        LD        A,3
              LD        (CMD),A
              LD        (SOFTCARD),A
              LD        A,(AREG)
              OR        A
              JR        Z,TSSTEMPTY
              LD        A,(YREG)
              AND       07FH
              CALL      TSKKEY
              JR        C,TSSTSWITCH
              OR        A                              ; OA-current was consumed, no input
              JR        Z,TSSTEMPTY
              JR        TSSTREADY
TSSTSWITCH    LD        A,(0E010H)                     ; Apple II $C010: clear just this key
              LD        A,0F3H                         ; resume the pending status poll
              LD        L,A
              RET
TSSTREADY     LD        A,0FFH
              LD        L,A
              RET
TSSTEMPTY     XOR       A
              LD        L,A
              RET

; Advertise the modifier and arrows as one-keystroke shortcuts.
RWMSG3        DEFM      ' sessions (0-9,A-F)'
              DEFB      13,10                         ; BANKS report CR+LF for Telnet
              DEFM      'Switch '
              DEFB      '$'
RWMSG4        DEFM      ' + 0123456789ABCDEF'
              DEFB      '$'
RWMSG5        DEFB      13,10                         ; BANKS report CR+LF for Telnet
              DEFM      'HELP for commands'
              DEFB      13,10,'$'                     ; final BANKS newline

; Session prompt is rendered by AUX CCP.COM.
; Stage 27: removed unused code/data (Legacy MAIN prompt formatter).
              ORG       003B0H
; Kill only an inactive saved context. No CPU instruction is preempted.
; FCB cache has already been flushed by the cooperative park path.
TB_KILL       CALL      NETKILL                         ; release network sockets for killed tab
              LD        A,B
              CALL      TB_HPTR
              LD        (HL),0
              LD        A,B
              CALL      TB_FPTR
              LD        (HL),0
              LD        HL,SCHWAIT
              ADD       HL,DE
              LD        (HL),0
              LD        HL,SHFLAGS                     ; a killed CCP must not auto-reload
              ADD       HL,DE
              LD        (HL),0
              LD        HL,CCPPROMS
              ADD       HL,DE
              LD        (HL),0
              LD        HL,SVVALID                     ; kill discards this tab's SAVE image
              ADD       HL,DE
              LD        (HL),0
              LD        HL,SVSFLAGS
              ADD       HL,DE
              LD        (HL),0
              ; Mark backing screen invalid, so the next selection clears it.
              LD        A,B
              CALL      TB_METAP
              LD        (HL),0
              ; KILL makes the slot unvisited again until explicitly selected.
              LD        A,B
              CALL      TB_VPTR
              LD        (HL),0
              RET
TB_FPTR       LD        E,A
              LD        D,0
              LD        HL,TSKFLAGS
              ADD       HL,DE
              RET

              ORG       00400H

; Phase 3A: two independent CCP contexts. TAB 0 / TAB 1 switches
; shell state (drive/user, IOBYTE, login/R/O vectors, terminal type).
; The transient for a context uses its corresponding RamWorks bank.
; Phase 3B: Open Apple shortcuts park a transient without reloading it.
; TAB n resumes a parked transient, rather than reloading it.
; Phase 3C: full text-screen/terminal-state snapshots in reserved bank 2.
; Still cooperative: no switching from a CPU-bound loop.
CCPTAB        JP        TBCMD                          ; extended TAB command parser

; Convert a hexadecimal ASCII tab selector to A=0..15, carry on error.
; Check the detected bank count so an unavailable tab is never touched.
TABDECODE     CP        '0'
              JR        C,TBD_BAD
              CP        '9'+1
              JR        NC,TBD_HEX
              SUB       '0'
              JR        TBD_RANGE
TBD_HEX       AND       0DFH                           ; lowercase a..f accepted
              CP        'A'
              JR        C,TBD_BAD
              CP        'F'+1
              JR        NC,TBD_BAD
              SUB       'A'-10
TBD_RANGE     LD        C,A
              LD        A,(TABCOUNT)
              CP        C
              JR        Z,TBD_BAD
              JR        C,TBD_BAD
              LD        A,C
              OR        A                              ; clear carry
              RET
TBD_BAD       SCF
              RET

; Drain queued switches before returning to the CCP prompt.
; TB_SWITCH can resume a suspended program, which can later suspend
; and queue ANOTHER switch.  A tail-JR here returned to CCPL1 after
; that suspension and printed a CCP prompt into the application's
; still-visible fullscreen display.  Loop until no request remains.
TBAUTOSW      LD        A,(TABREQ)
              CP        0FFH
              RET       Z
              LD        B,A
              LD        A,0FFH
              LD        (TABREQ),A
              CALL      TB_SWITCH
              JR        TBAUTOSW
TB_SWITCH     JP        TB_SWGATE                     ; defer if called from AUX BDOS F8
TB_SWCONT     PUSH      BC
              LD        A,B
              CALL      TBCLEARH                       ; switching always wakes a held tab
              POP       BC
              LD        A,(TABMODE)
              CP        B
              JR        Z,TB_RESUM
              PUSH      BC
              CALL      VSSTSAVE                       ; save active 6502 parser/cursor state
              ; Capture the foreground 80-column screen before leaving it.
              ; Do not capture video on background scheduler ticks.
              CALL      SCHISFG
              CALL      Z,VSSAVE
              CALL      TABSAVE
              CALL      CACHEALL
              POP       BC
              LD        A,B
              LD        (TABMODE),A
              LD        (SCHFG),A                      ; manual TAB changes visible session
              CALL      TABLOAD
              CALL      VSSTLOAD
              CALL      VSSELECT                       ; renders new tab to hardware
              CALL      VSREST                         ; copy ALWAYS-LIVE snapshot to video
              JR        TB_GO
; A direct TAB command aimed at the current tab should beep too.
; Open Apple+current is already consumed and beeped by TSKSAME.
TB_RESUM      CALL      UNIMP                          ; bell, no spurious CCP output
              CALL      TSKACTIVE
              OR        A
              CALL      NZ,VSREST
TB_GO         LD        A,(TABMODE)
              LD        (SCHFG),A
              CALL      TB_VISMARK                     ; first visit queues AUX CCP startup
              CALL      VSSELECT                       ; update 6502 foreground ownership
              CALL      SCHWAKE                        ; this tab may be waiting for CONIN
              LD        A,SCHFGQ
              LD        (SCHQLEFT),A                   ; a newly selected tab is foreground
              CALL      TB_BOOTIFNEW                   ; new tab: A:CCP.COM, else parked task
              RET
; One byte per CCP session. Saved display may already contain the
; A> prompt, so do not print it again after restoring that screen.
; Stage 27: removed unused code/data (Unused CCP prompt pointer).
TABMODE       DEFB      0

; Session descriptors are only seven bytes each, stored in MAIN memory.
; Offsets: 0 current drive/user, 1 IOBYTE, 2..3 LOGVEC,
; 4..5 ROVEC, 6 personality (0 VT100 / 1 Soroc / 2 H19).
; DMA is intentionally reset to $0080 at each switch; no BDOS search
; or pending directory enumeration is allowed across a CCP TAB command.
TABPICK       LD        IX,TABCTXS
              LD        A,(TABMODE)
              OR        A
              RET       Z
              LD        B,A
              LD        DE,7
TP_NEXT       ADD       IX,DE
              DJNZ      TP_NEXT
              RET

TABSAVE       CALL      TABPICK
              LD        A,(CURDRV)
              LD        (IX+0),A
              LD        A,(IOBYTE)
              LD        (IX+1),A
              LD        HL,(LOGVEC)
              LD        (IX+2),L
              LD        (IX+3),H
              LD        HL,(ROVEC)
              LD        (IX+4),L
              LD        (IX+5),H
              LD        HL,0B81BH
              LD        (ADDR),HL
              LD        A,1
              LD        (CMD),A
              LD        (SOFTCARD),A
              LD        A,(IX+6)
              CP        2                              ; 6502 knows only Soroc for H19
              RET       Z                              ; keep H19 personality on save
              LD        A,(AREG)
              LD        (IX+6),A
              RET

TABLOAD       CALL      TABPICK
              LD        A,(IX+0)
              LD        (CURDRV),A
              LD        A,(IX+1)
              LD        (IOBYTE),A
              LD        L,(IX+2)
              LD        H,(IX+3)
              LD        (LOGVEC),HL
              LD        L,(IX+4)
              LD        H,(IX+5)
              LD        (ROVEC),HL
              LD        HL,FILEBUF
              LD        (DMAADDR),HL
              LD        HL,0080H
              LD        (AXDMAP),HL
              LD        A,(IX+6)
              LD        (VTMODEC),A                   ; manual foreground tab switch
              CP        2                              ; H19 parser uses Soroc renderer
              JR        NZ,TABLD6502
              LD        A,1
TABLD6502     LD        (AREG),A
              LD        HL,0B80CH
              LD        (ADDR),HL
              LD        A,1
              LD        (CMD),A
              LD        (SOFTCARD),A
              RET

TABINIT       CALL      RWDETECT
              LD        HL,TABCTXS
              LD        B,16
TI_NEXT       XOR       A
              LD        (HL),A                         ; CURDRV
              INC       HL
              LD        A,095H
              LD        (HL),A                         ; default IOBYTE in every tab
              INC       HL
              LD        A,1
              LD        (HL),A                         ; LOGVEC = 0001H
              INC       HL
              XOR       A
              LD        (HL),A
              INC       HL
              LD        (HL),A
              INC       HL
              LD        (HL),A
              INC       HL
              INC       A
              LD        (HL),A                         ; Soroc default
              INC       HL
              DJNZ      TI_NEXT
              LD        HL,VTSTATES
              LD        DE,VTSTATES+1
              LD        BC,127
              XOR       A
              LD        (HL),A
              LDIR
              CALL      VSINIT
              CALL      VSSAVE                         ; seed tab 0 backing with startup text
              CALL      TB_VINIT                       ; tab 0 is visited at cold boot
              LD        HL,CCPPROMS
              LD        DE,CCPPROMS+1
              LD        BC,15
              XOR       A
              LD        (HL),A
              LDIR
              LD        A,1
              LD        (VTMODEC),A                   ; TABINIT restores Soroc default
              RET

; Map a logical tab A to its manual hold flag; preserves B.
TB_HPTR       LD        E,A
              LD        D,0
              LD        HL,TBHOLD
              ADD       HL,DE
              RET
TBCLEARH      CALL      TB_HPTR
              LD        (HL),0
              RET
TB_TFL        LD        E,A
              LD        D,0
              LD        HL,TSKFLAGS
              ADD       HL,DE
              LD        A,(HL)
              RET
; 8-byte saved executable name for tab A.
TBNPTR        LD        L,A
              LD        H,0
              ADD       HL,HL
              ADD       HL,HL
              ADD       HL,HL
              LD        DE,TBNAMES
              ADD       HL,DE
              RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Implementation of CP/M STYLE BDOS
; Function to invoke is passed in C, as follows:
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
B_C_TERMCPM   EQU       00H                            ; System reset
B_C_READ      EQU       01H                            ; Console read
B_C_WRITE     EQU       02H                            ; Console write
B_C_RAWIO     EQU       06H                            ; Direct console I/O
B_GET_IOB     EQU       07H                            ; Get IOBYTE
B_SET_IOB     EQU       08H                            ; Set IOBYTE
B_C_WRTSTR    EQU       09H                            ; Console write string
B_C_RDSTR     EQU       0AH                            ; Read console string
B_C_STAT      EQU       0BH                            ; Console status
B_S_BDOSVER   EQU       0CH                            ; Return version number
B_DRV_ALLRST  EQU       0DH                            ; Reset disks
B_DRV_SET     EQU       0EH                            ; Select disk
B_F_OPEN      EQU       0FH                            ; Open file
B_F_CLOSE     EQU       10H                            ; Close file
B_F_SFIRST    EQU       11H                            ; Search for first match in directory
B_F_SNEXT     EQU       12H                            ; Search for next match in directory
B_F_DELETE    EQU       13H                            ; Delete file
B_F_READ      EQU       14H                            ; Read file sequentially
B_F_WRITE     EQU       15H                            ; Write file sequentially
B_F_MAKE      EQU       16H                            ; Create and open file
B_F_RENAME    EQU       17H                            ; Rename file
B_DRV_LOGVEC  EQU       18H                            ; Return bitmap of logged-in drives
B_DRV_GET     EQU       19H                            ; Return current drive
B_F_DMAOFF    EQU       1AH                            ; Set DMA address
B_DRV_AVEC    EQU       1BH                            ; Return address of allocation map
B_DRV_SRO     EQU       1CH                            ; Software write-protect current drive
B_DRV_ROVEC   EQU       1DH                            ; Return bitmap of read-only drives
B_DRV_DPB     EQU       1FH                            ; Get Drive Parameter Block address
B_F_USERNUM   EQU       20H                            ; Get/set user number
B_F_RDRAND    EQU       21H                            ; Random access read record
B_F_WRTRAND   EQU       22H                            ; Random access write record
B_F_SIZE      EQU       23H                            ; Compute file size
B_F_RANDREC   EQU       24H                            ; Update random access pointer
B_DRV_RESET   EQU       25H                            ; Selectively reset disk drives
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


; ================================================================
; AUX56 PHASE 2: MAIN-bank FCB/DMA gateway in otherwise idle MAIN TPA.
; The executable TPA is in AUX $0100-$AFFF, so MAIN $7000 is free.
; All caller pointers refer to AUX unless explicitly translated.
; MAIN $7800-$7BFF holds permanent staging and ProDOS-safe scratch.
; ================================================================

; ================================================================
; RamWorks Phase 3B: two parked AUX transients, cooperative switching.
; Resident MAIN-memory code below $1000 is outside both AUX TPAs.
; Open Apple is sampled alongside each keystroke or status peek.
; It cooperatively parks applications; no interrupt preemption.
; ================================================================
; Foreground-biased scheduler.  Quanta count completed BIOS/BDOS calls,
; not CPU time.  A busy foreground gets long uninterrupted bursts;
; background work gets a short turn.  When foreground is idle/blocked,
; background uses the original 32-call quantum.
SCHFGQ        EQU       128
SCHBGQ        EQU       8
; Software cursor: foreground physical text only, never saved in a
; RamWorks backing screen. Polling input normally bypasses VGET, so
; draw the reverse-video cell while a foreground task waits for a key.
              ORG       005A8H
; Physical cursor is drawn by the 6502 video driver (B82A/B82D).
; Avoid Z80 CUMAP/VSPREP0 bank/page switching while the cursor moves.
; Preserve HL and AF for CCP, scheduler, and other input paths.
CUON          LD        A,(CUACTIVE)
              OR        A
              RET       NZ
              LD        A,(VSOK)
              OR        A
              RET       Z
              PUSH      AF
              PUSH      HL
              LD        HL,0B82AH                       ; VCURON - 6502 physical draw
              LD        (ADDR),HL
              LD        A,1
              LD        (CMD),A
              LD        (SOFTCARD),A
              LD        A,1
              LD        (CUACTIVE),A
              POP       HL
              POP       AF
              RET

SCHIDLEQ      EQU       32
              ORG       00600H
; Stage 1 scheduler. RUNTASK is TABMODE; SCHFG owns the physical screen.
; These are cooperative slices: no call is interrupted mid-operation.
; SCHMAIN is called with MAIN/CCP stack active after a transient yields.
SCHMAIN       LD        A,(SCHEN)
              OR        A
              RET       Z
SMLOOP        CALL      NC_HOT                        ; poll physical OA, even with UC1 foreground
              CP        0FFH
              RET       NZ                             ; manual tab switch has priority
              LD        A,(SCHFG)
              LD        E,A
              LD        D,0
              LD        HL,TSKFLAGS
              ADD       HL,DE
              LD        A,(HL)
              OR        A
              RET       Z                              ; foreground is at CCP, not in .COM
              CALL      SCHONE                         ; optional background quantum
              LD        A,(SCHFG)
              LD        B,A
              CALL      SCHSWAP                        ; restore foreground BDOS context
              ; Stage 3: a foreground .COM parked on CONIN must not
              ; enter the blocking 6502 VGET while other jobs are runnable.
              ; Poll the *physical* keyboard and keep running background
              ; quanta until a key appears (or a manual tab switch arrives).
              LD        A,(SCHFG)
              LD        E,A
              LD        D,0
              LD        HL,SCHWAIT
              ADD       HL,DE
              LD        A,(HL)
              OR        A
              JR        Z,SMRUN
              CALL      SCHHAVE
              OR        A
              JR        Z,SMRUN                        ; no background jobs: normal VGET cursor
              CALL      CUON
              CALL      BIOSCONST
              OR        A
              JR        Z,SMLOOP                       ; input not ready; don't enter VGET
              CALL      CUOFF
              CALL      SCHWAKE                        ; input can complete: make task runnable
SMRUN         NOP                                      ; cursor stays on
              NOP
              NOP
              LD        A,SCHFGQ
              LD        (SCHQLEFT),A                   ; foreground receives longer quantum
              CALL      TABRESUM                       ; foreground until next yield/exit
              JR        SMLOOP

; Called from foreground CCP's console line editor before CONIN.
; When background work exists, poll keyboard and run background slices.
; Preserve the editor's live IX, BC, DE and flags across task execution.
SCHIDLE       PUSH      AF
              PUSH      BC
              PUSH      DE
              PUSH      IX
              PUSH      IY
SIAGAIN       CALL      SCHHAVE
              OR        A
              JR        Z,SIDONE                       ; no background jobs: normal VGET
              LD        A,3
              LD        (CMD),A
              LD        (SOFTCARD),A
              LD        A,(AREG)
              OR        A
              JR        NZ,SIDONE                      ; physical key waiting, let VGET read
              CALL      CUON                           ; show cursor during cooperative polling
              CALL      SCHONE
              JR        SIAGAIN
SIDONE        CALL      CUOFF                          ; key or blocking VGET takes ownership
              POP       IY
              POP       IX
              POP       DE
              POP       BC
              POP       AF
              RET

; Pick a runnable background tab. Does not touch the screen or terminal
; personality. Run for one quantum; then restore foreground CCP context.
SCHONE        LD        A,(SCHEN)
              OR        A
              RET       Z
              LD        A,(SCHNEXT)
              LD        C,A
              LD        B,16
SOSCAN        LD        A,(TABCOUNT)
              CP        C
              JR        NZ,SOIDX
              LD        C,0
SOIDX         LD        A,(SCHFG)
              CP        C
              JR        Z,SOADV
              LD        E,C
              LD        D,0
              LD        HL,TSKFLAGS
              ADD       HL,DE
              LD        A,(HL)
              OR        A
              JR        Z,SOADV
              CALL      NCSOCHK                        ; preserve C/DE/HL; wake UC1 only on packet
              JR        NZ,SOADV
              NOP
              NOP
              NOP
              LD        HL,TBHOLD
              ADD       HL,DE
              LD        A,(HL)
              OR        A
              JR        NZ,SOADV
              LD        A,C
              INC       A
              LD        (SCHNEXT),A
              LD        B,C
              CALL      SCHSWAP
              ; A busy foreground needs quick redraws; give background
              ; only a few calls.  When foreground is at CCP or blocked
              ; on input, allow full-sized background quanta instead.
              LD        A,(SCHFG)
              LD        E,A
              LD        D,0
              LD        HL,TSKFLAGS
              ADD       HL,DE
              LD        A,(HL)
              OR        A
              JR        Z,SOFULL
              LD        HL,SCHWAIT
              ADD       HL,DE
              LD        A,(HL)
              OR        A
              JR        NZ,SOFULL
              LD        A,SCHBGQ
              JR        SOQUANT
SOFULL        LD        A,SCHIDLEQ
SOQUANT       LD        (SCHQLEFT),A
              CALL      TABRESUM
              LD        A,(SCHFG)
              LD        B,A
              CALL      SCHSWAP
              LD        A,1
              RET
SOADV         INC       C
              DJNZ      SOSCAN
              XOR       A
              RET

; Boolean: is there any runnable background task? Preserves BC, DE.
SCHHAVE       PUSH      BC
              PUSH      DE
              PUSH      HL
              LD        A,(SCHNEXT)
              LD        C,A
              LD        B,16
SHSCAN        LD        A,(TABCOUNT)
              CP        C
              JR        NZ,SHIDX
              LD        C,0
SHIDX         LD        A,(SCHFG)
              CP        C
              JR        Z,SHADV
              LD        E,C
              LD        D,0
              LD        HL,TSKFLAGS
              ADD       HL,DE
              LD        A,(HL)
              OR        A
              JR        Z,SHADV
              CALL      NCSHCHK                        ; UC1 wait counts as polling work
              JR        NZ,SHADV
              NOP
              NOP
              NOP
              LD        HL,TBHOLD
              ADD       HL,DE
              LD        A,(HL)
              OR        A
              JR        NZ,SHADV
              LD        A,1
              JR        SHDONE
SHADV         INC       C
              DJNZ      SHSCAN
              XOR       A
SHDONE        POP       HL
              POP       DE
              POP       BC
              RET

; No terminal snapshot and no physical terminal-mode changes on a
; background context switch; only COMMON BDOS drive state is exchanged.
SCHSWAP       LD        A,(TABMODE)
              CP        B
              RET       Z
              PUSH      BC
              CALL      VSSTSAVE                       ; flush active terminal state to descriptor
              CALL      SCHSAVE
              POP       BC
              LD        A,B
              LD        (TABMODE),A
              CALL      SCHLOAD
              CALL      VSSTLOAD                       ; restore cursor/escape parser/mode
              JP        VSSELECT                       ; 6502 maps backing screen for this task

              ORG       00770H
; 16 eight-character executable names, only valid while TSKFLAGS is set.
TBNAMES       DEFS      128
; Explicit manual pause is separate from SCHWAIT (console-read parking).
TBHOLD        DEFS      16

              ORG       00800H
; BDOS 10 may suspend only at an empty line. A successful hotkey
; parks the read itself; resume restarts it, without submitting CR.
; Stage 27: removed unused code/data (Obsolete input return marker).
TSKCIN        CALL      BIOSCONIN
              CALL      TSKKEY
              JR        C,TSKCIKEY
              OR        A
              JR        Z,TSKCIN                       ; OA-current was consumed
              CP        3
              JR        NZ,TSKECHO
              JP        TSKCCANCEL                     ; ^C: cancel shell, abort child
TSKECHO       PUSH      AF
              LD        E,A
              CALL      C_WRITE
              POP       AF
              LD        L,A
              RET
TSKCIKEY      LD        A,0F1H                         ; deferred cooked input
              LD        L,A
              RET

TSKBIRD       CALL      BIOSCONIN
              CALL      TSKKEY
              JR        C,TSKBIKEY
              OR        A
              JR        Z,TSKBIRD                      ; OA-current was consumed
              LD        L,A
              RET
TSKBIKEY      LD        A,0F2H                         ; deferred BIOS character input
              LD        L,A
              RET

TSKINIT       JP        SHINIT                       ; Stage 12 initialization out of the tight $0800 block
TSKINI2       LD        DE,SCHWAIT+1
              LD        BC,15
              XOR       A
              LD        (HL),A
              LDIR
              LD        (SCHFG),A
              LD        (SCHNEXT),A
              LD        A,SCHFGQ
              LD        (SCHQLEFT),A
              LD        A,(TABCOUNT)
              CP        2
              LD        A,0
              JR        C,SKINIT0
              INC       A
SKINIT0       LD        (SCHEN),A
              LD        HL,TSKFLAGS
              LD        DE,TSKFLAGS+1
              LD        BC,15
              XOR       A
              LD        (HL),A
              LDIR
              LD        A,0FFH
              LD        (TABREQ),A
              LD        HL,TBHOLD
              LD        DE,TBHOLD+1
              LD        BC,15
              XOR       A
              LD        (HL),A
              LDIR
              RET

TSKFLPTR      LD        A,(TABMODE)
              LD        E,A
              LD        D,0
              LD        HL,TSKFLAGS
              ADD       HL,DE
              RET
TSKACTIVE     CALL      TSKFLPTR
              LD        A,(HL)
              RET

; A=ASCII key, XREG=Open Apple state sampled by the 6502 at key read.
; Carry=1 if a DIFFERENT tab was queued. OA+current beeps and returns
; carry=0, A=0 (consumed), so callers don't suspend or pass the key.
; Arrow keys wrap around TABCOUNT; numeric/hex keys select directly.
; Preserve BC (TABDECODE uses C, and AXLINE holds its count there).
TSKKEY        PUSH      BC
              PUSH      AF
              LD        A,(XREG)
              BIT       7,A
              JR        Z,TSKIGNORE
              POP       AF
              PUSH      AF
              CP        08H                            ; Apple IIe left-arrow
              JR        Z,TSKPREV
              CP        15H                            ; Apple IIe right-arrow
              JR        Z,TSKNEXT
              CALL      TABDECODE
              JR        C,TSKIGNORE
              JR        TSKQUEUE
TSKPREV       LD        A,(TABMODE)
              OR        A
              JR        NZ,TSKPREVB
              LD        A,(TABCOUNT)
TSKPREVB      DEC       A
              JR        TSKQUEUE
TSKNEXT       LD        A,(TABMODE)
              INC       A
              LD        B,A
              LD        A,(TABCOUNT)
              CP        B
              JR        Z,TSKWRAP
              JR        C,TSKWRAP
              LD        A,B
              JR        TSKQUEUE
TSKWRAP       XOR       A
TSKQUEUE      LD        B,A                            ; B is saved by TSKKEY prologue
              LD        A,(SCHFG)
              CP        B
              JR        Z,TSKSAME
              LD        A,B
              LD        (TABREQ),A
              LD        A,3
              LD        (AXQUIT),A
              POP       BC                             ; discard the original character/flags
              POP       BC                             ; restore caller's BC
              SCF
              RET
TSKSAME       PUSH      HL                             ; UNIMP changes HL (6502 vector)
              CALL      UNIMP                          ; beep: Open Apple + current tab
              POP       HL
              LD        A,(0E010H)                     ; clear physical key strobe (status path)
              POP       BC                             ; discard saved character/flags
              POP       BC                             ; restore caller BC
              XOR       A                              ; consumed: no input, no suspension
              RET
TSKIGNORE     POP       AF                             ; ordinary key: return it unchanged
              POP       BC
              OR        A                              ; clear carry
              RET

TSKSET        PUSH      AF
              CALL      TSKFLPTR
              POP       AF
              LD        (HL),A
              RET

; DE = 27 * logical session index + TSKREGS, return HL.
TSKSLOTP      LD        A,(TABMODE)
              LD        L,A
              LD        H,0
              LD        E,L
              LD        D,H
              ADD       HL,HL
              ADD       HL,HL
              ADD       HL,HL                          ; 8n
              LD        B,H
              LD        C,L
              ADD       HL,HL                          ; 16n
              ADD       HL,BC                          ; 24n
              ADD       HL,DE                          ; 25n
              ADD       HL,DE                          ; 26n
              ADD       HL,DE                          ; 27n
              LD        DE,TSKREGS
              ADD       HL,DE
              RET

; Copy 27 bytes of preserved Z80/BDOS context to the current slot.
; TASKSAVE is called immediately after AUXBDOS, before changing tabs.
TASKSAVE      LD        (TSKBC),BC
              LD        (TSKDE),DE
              LD        (TSKIX),IX
              LD        (TSKIY),IY
              EXX
              LD        (TSKAB),BC
              LD        (TSKAD),DE
              LD        (TSKAH),HL
              EXX
              EX        AF,AF'
              PUSH      AF
              POP       HL
              LD        (TSKAA),HL
              EX        AF,AF'
              LD        HL,(AXASP)
              LD        (TSKSP),HL
              LD        HL,(AXRHL)
              LD        (TSKHL),HL
              LD        HL,(DMAADDR)
              LD        (TSKDM),HL
              LD        HL,(AXDMAP)
              LD        (TSKDP),HL
              LD        A,(AXRES)
              LD        (TSKRE),A
              LD        HL,(AXLIP)
              LD        (TSKLI),HL
              LD        A,(AXRES)
              CP        0F1H                           ; cooked CONIN deferred by Open Apple
              JR        Z,TSKWAIT
              CP        0F2H                           ; raw BIOS CONIN deferred
              JR        Z,TSKWAIT
              CP        0FAH                           ; BDOS 10 before first key
              JR        Z,TSKWAIT
              CP        0FBH                           ; BDOS 10 with partial line
              JR        NZ,TSKNOWT
TSKWAIT       CALL      SCHBLCK                        ; background must not retry VGET
TSKNOWT       LD        A,1
              CALL      TSKSET
              LD        HL,TSKBUFF
              CALL      TSKSLOTP
              EX        DE,HL
              LD        HL,TSKBUFF
              LD        BC,TSKSIZE
              LDIR
              RET

; Reconstitute the same registers and return values before the saved
; AUX stack is made active. Caller must have selected the RamWorks bank.
TASKLOAD      CALL      TSKSLOTP
              LD        DE,TSKBUFF
              LD        BC,TSKSIZE
              LDIR
              LD        HL,(TSKSP)
              LD        (AXASP),HL
              LD        HL,(TSKHL)
              LD        (AXRHL),HL
              LD        HL,(TSKDM)
              LD        (DMAADDR),HL
              LD        HL,(TSKDP)
              LD        (AXDMAP),HL
              LD        A,(TSKRE)
              LD        (AXRES),A
              LD        HL,(TSKLI)
              LD        (AXLIP),HL
              LD        BC,(TSKAB)
              LD        DE,(TSKAD)
              LD        HL,(TSKAH)
              EXX
              LD        HL,(TSKAA)
              PUSH      HL
              EX        AF,AF'
              POP       AF
              EX        AF,AF'
              LD        IX,(TSKIX)
              LD        IY,(TSKIY)
              LD        BC,(TSKBC)
              LD        DE,(TSKDE)
              RET

; TAB n resumes a parked program. All MLI and cache resources are
; shared, hence physical handles were flushed when it was parked.
TABRESUM      CALL      TSKACTIVE
              OR        A
              RET       Z
              XOR       A
              CALL      TSKSET                         ; clear active flag during execution
              LD        A,(TABMODE)
              CALL      TABPHYS
              CALL      AXBANK
              CALL      AXSNAP                         ; save ProDOS MAIN LC; do not load .COM
              CALL      TASKLOAD
              CALL      AXCONT                         ; returns after new ^] or program exit
              LD        A,(AXQUIT)
              CP        3
              JR        Z,TSKRSUS
              ; Completed program retains its own AUX LC/TPA for CCP SAVE.
              CALL      CACHEALL
              CALL      AXMAINLC
              CALL      SVFLPTR
              LD        (HL),1
              JR        TSKRFIN
TSKRSUS       CALL      CACHEALL
              CALL      AXMAINLC                       ; parked bank's LC must survive
TSKRFIN       XOR       A
              CALL      AXBANK
              LD        A,(AXQUIT)
              CP        3
              ; Backing display is live; no snapshot at suspension.
              LD        HL,FILEBUF
              LD        (DMAADDR),HL
              LD        HL,0080H
              LD        (AXDMAP),HL
              CALL      SHAFTER                      ; offload stage-12 continuation and WBOOT setup
              RET

; Stage 27: removed unused code/data (Unreferenced scheduler strings).
; Shared serialization buffer and one copy for each session.
TSKBUFF
TSKBC         DEFW      0
TSKDE         DEFW      0
TSKIX         DEFW      0
TSKIY         DEFW      0
TSKAB         DEFW      0
TSKAD         DEFW      0
TSKAH         DEFW      0
TSKAA         DEFW      0
TSKSP         DEFW      0
TSKHL         DEFW      0
TSKDM         DEFW      0
TSKDP         DEFW      0
TSKRE         DEFB      0
TSKLI         DEFW      0                              ; interrupted BDOS 10 AUX buffer pointer
TSKEND
TSKSIZE       EQU       TSKEND-TSKBUFF

; On resume, complete a parked input call *before* returning to AUX.
; AXRES carries a private marker only when suspended in keyboard I/O.
; No synthetic NUL/CR is sent to MBASIC, WordStar or the CCP.
AXRETRY       JP        AXRETRYX                      ; overflow-safe trampoline

; CCP-only MouseText print. A='A'/$41 (Open Apple), 'H'/$48 (left),
; 'U'/$55 (right). The stock VPUT path forces normal or inverse ASCII,
; so print one spacer through the 6502 parser to advance its cursor,
; then replace that physical text cell with a raw MouseText screen byte.
; All three sign-on glyphs are deliberately away from row wrap.
; Reuse the working software-cursor's bank-0 mapping helper; never
; alter video interpretation for CP/M applications.
MTCHAR        PUSH      AF
              CALL      CUOFF
              LD        E,' '
              CALL      C_WRITE
              LD        HL,(VSPTR)                     ; 6502 state: VCOL followed by VROW
              LD        A,(HL)
              DEC       A                              ; one cell back, same line (no wrap)
              LD        C,A
              INC       HL
              LD        A,(HL)
              ADD       A,A
              LD        E,A
              LD        D,0
              LD        HL,CUROWTAB
              ADD       HL,DE
              LD        E,(HL)
              INC       HL
              LD        D,(HL)
              LD        A,C
              AND       1
              LD        (CUHALF),A                     ; even=aux, odd=main
              SRL       C
              LD        B,0
              EX        DE,HL
              ADD       HL,BC
              LD        (CUADDR),HL
              CALL      CUMAP                          ; selects bank 0 physical screen
              POP       AF
              LD        (HL),A                         ; low screen code $41/$48/$55 = MouseText
              JP        VSPREP                         ; restore normal main/video switches

; ================================================================
; RamWorks Stage 2: 6502 renderer maintains live screen backing.
; VSSAVE seeds session 0 once; VSREST redraws a selected snapshot.
; Physical 6502 $2000-$2FFF in bank 2 (Z80 $1000-$1FFF) holds
; 1KB MAIN + 1KB AUX video page for each session.
;
; $C001/HIRES/PAGE2 maps ONLY the Apple II HGR page ($2000-$3FFF)
; to RamWorks AUX, so this MAIN resident code ($0B00) can copy directly
; via Z80 $1000-$1FFF. Z80 $3000-$33FF (physical MAIN $4000) is
; temporary copy scratch during TAB/suspend; SAVE cannot run then.
; $C073 banks and $C0xx switches are always restored before returning.
; The two live CP/M AUX banks 0/1 are never used for screen storage.
; ================================================================
              ORG       00B00H
VS80ON        EQU       0E001H
VSPAGE1       EQU       0E054H
VSPAGE2       EQU       0E055H
VSHIRES0      EQU       0E056H
VSHIRES1      EQU       0E057H
VSTEXT        EQU       0F400H
VSSCRATCH     EQU       03000H
VSMINSIZE     EQU       0400H
VSTLEN        EQU       9                              ; contiguous VCOL..VATTR in 6502

; 6502 $B81E returns VCOL address as A=low, X=high. Convert to
; SoftCard Z80 address by subtracting $1000 from its high byte.
VSINIT        LD        HL,VSMETAS
              LD        DE,VSMETAS+1
              LD        BC,159
              XOR       A
              LD        (HL),A
              LDIR
              LD        A,(RWTOTAL)
              CP        3
              LD        A,0
              JR        C,VSNOTRW
              INC       A
VSNOTRW       LD        (VSOK),A
              LD        HL,0B81EH
              LD        (ADDR),HL
              LD        A,1
              LD        (CMD),A
              LD        (SOFTCARD),A
              LD        A,(AREG)
              LD        L,A
              LD        A,(XREG)
              SUB       010H
              LD        H,A
              LD        (VSPTR),HL
              RET

; Every snapshot bank provides an 8KB HGR window: 4 x 2KB screens.
; session 0..3 -> bank 2; 4..7 -> bank 5; 8..11 -> bank 10;
; 12..15 -> bank 15. Data lives at Z80 $1000..$2FFF.
VSSLOT        LD        B,A                            ; 0 main half, 1 auxiliary half
              LD        A,(TABMODE)
              AND       3
              ADD       A,A
              ADD       A,A
              ADD       A,A                            ; logical slot within group * $0800
              ADD       A,010H
              LD        D,A
              LD        E,0
              LD        A,B
              OR        A
              RET       Z
              LD        A,D
              ADD       A,4
              LD        D,A
              RET

VSMETA        LD        A,(TABMODE)
              LD        L,A
              LD        H,0
              LD        E,L
              LD        D,H
              ADD       HL,HL                          ; 2n
              ADD       HL,HL                          ; 4n
              ADD       HL,HL                          ; 8n
              ADD       HL,DE                          ; 9n
              ADD       HL,DE                          ; 10n
              LD        DE,VSMETAS
              ADD       HL,DE
              RET

VSSBANK       LD        A,(TABMODE)
              CP        4
              JR        C,VSB_FIRST
              SRL       A
              SRL       A                              ; group 1..3
              LD        B,A
              ADD       A,A
              ADD       A,A
              ADD       A,B                            ; group * 5
              RET
VSB_FIRST     LD        A,2
              RET

; Explicitly normalise main/aux CPU access before copying video.
; The scheduler and virtual-terminal code remain untouched.
VSPREP        XOR       A
              LD        (SW80OFF),A
              LD        (RDMAIN),A
              LD        (WRMAIN),A
              LD        A,(VSHIRES0)
              LD        A,(VSPAGE1)
              RET

; The live physical screen is always in RamWorks bank 0.
VSPREP0       XOR       A
              CALL      AXBANK
              JP        VSPREP

; Open AUX HGR window for the current session's backing screen.
VSWINDOW      CALL      VSPREP
              CALL      VSSBANK
              CALL      AXBANK
              XOR       A
              LD        (VS80ON),A
              LD        A,(VSHIRES1)
              LD        A,(VSPAGE2)
              RET

; Close AUX HGR window and return to bank 0 with MAIN reads/writes.
VSUNWIN       CALL      VSPREP
              XOR       A
              CALL      AXBANK
              RET

; Read physical MAIN text page from bank 0, not inherited mapping.
VSFROMMAIN    CALL      VSPREP0
              LD        HL,VSTEXT
              LD        DE,VSSCRATCH
              LD        BC,VSMINSIZE
              LDIR
              RET
; Only TEXT1 is AUX; the copy scratch stays MAIN.
VSFROMAUX     CALL      VSPREP0
              XOR       A
              LD        (VS80ON),A
              LD        A,(VSPAGE2)
              LD        HL,VSTEXT
              LD        DE,VSSCRATCH
              LD        BC,VSMINSIZE
              LDIR
              JP        VSPREP

; A=half (0 main, 1 aux): copy staged 1K to bank2 snapshot.
VSWRITE       CALL      VSSLOT
              PUSH      DE
              CALL      VSWINDOW
              POP       DE
              LD        HL,VSSCRATCH
              LD        BC,VSMINSIZE
              LDIR
              JP        VSUNWIN

; A=half: copy saved 1K to staging scratch, then restore bank0.
VSREAD        CALL      VSSLOT
              PUSH      DE
              CALL      VSWINDOW
              POP       HL
              LD        DE,VSSCRATCH
              LD        BC,VSMINSIZE
              LDIR
              JP        VSUNWIN

VSSAVE        LD        A,(VSOK)
              OR        A
              RET       Z
              CALL      VSMETA
              LD        A,1
              LD        (HL),A
              INC       HL
              EX        DE,HL
              LD        HL,(VSPTR)
              LD        BC,VSTLEN
              LDIR
              CALL      VSFROMMAIN
              XOR       A
              CALL      VSWRITE
              CALL      VSFROMAUX
              LD        A,1
              JP        VSWRITE

; Restore byte-identical MAIN and AUX text pages, cursor/parser data,
; then return to 80-col text state. Initial unused tab is cleared.
VSREST        LD        A,(VSOK)
              OR        A
              JP        Z,CCPCLS
              CALL      VSMETA
              LD        A,(HL)
              OR        A
              JR        NZ,VRDRAW
              CALL      CCPCLS                         ; new tab: clear physical screen
              CALL      VSSAVE                         ; seed BOTH halves from clean physical screen
              JP        VSSTSAVE                       ; save current cursor/parser state
VRDRAW        XOR       A
              CALL      VSREAD
              CALL      VSPREP0                        ; MAIN screen target, bank 0
              LD        HL,VSSCRATCH
              LD        DE,VSTEXT
              LD        BC,VSMINSIZE
              LDIR
              LD        A,1
              CALL      VSREAD
              CALL      VSPREP0                        ; reset RAMRD/RAMWRT/PAGE1
              XOR       A
              LD        (VS80ON),A
              LD        A,(VSPAGE2)
              LD        HL,VSSCRATCH
              LD        DE,VSTEXT
              LD        BC,VSMINSIZE
              LDIR
              JP        VSPREP

VSPTR         DEFW      0
VSOK          DEFB      0

; Shared MAIN descriptors; never in the application's switchable AUX RAM.
              ORG       00C70H
; Extended TAB commands.  Parsed CCP tail is " N ACTION " or " LIST ".
TBCMD         LD        A,(FILEBUF)
              OR        A
              JP        Z,TB_LIST
              LD        A,(FILEBUF+2)
              CP        'L'
              JR        NZ,TC_CHECKH
              LD        HL,FILEBUF+2
              LD        DE,TCLIST
              CALL      TCMATCH
              JP        Z,TB_LIST
              JP        CCPBAD
TC_CHECKH     CP        'H'
              JR        NZ,TC_NUM
              LD        HL,FILEBUF+2
              LD        DE,TCHELP
              CALL      TCMATCH
              JP        Z,TB_HELP
              JP        CCPBAD
TC_NUM        CALL      TABDECODE
              JP        C,CCPBAD
              LD        B,A
              LD        A,(FILEBUF+3)
              CP        ' '
              JP        NZ,CCPBAD
              LD        A,(FILEBUF+4)
              OR        A                              ; TAB n ends with NUL after the SP
              JP        Z,TB_SWITCH
              LD        HL,FILEBUF+4
              LD        DE,TCSUSP
              CALL      TCMATCH
              JP        Z,TB_PAUSE
              LD        HL,FILEBUF+4
              LD        DE,TCRESUM
              CALL      TCMATCH
              JP        Z,TB_UNPS
              LD        HL,FILEBUF+4
              LD        DE,TCEXCL
              CALL      TCMATCH
              JP        Z,TB_EXCL
              LD        HL,FILEBUF+4
              LD        DE,TCKILL
              CALL      TCMATCH
              JP        Z,TB_SAFE_KILL
              JP        CCPBAD
TCMATCH       LD        A,(HL)
              CP        ' '                            ; any unambiguous prefix accepted
              RET       Z
              LD        A,(DE)
              CP        (HL)
              RET       NZ
              INC       DE
              INC       HL
              JR        TCMATCH


              ORG       00D00H
TABCTXS       DEFS      112                            ; 16 * 7 bytes
TSKFLAGS      DEFS      16                             ; one parked flag per logical session
TSKREGS       DEFS      432                            ; 16 * 27-byte saved Z80 contexts
VSMETAS       DEFS      160                            ; 16 * (valid + 9 terminal bytes)
CCPPROMS      DEFS      16                             ; 1 if restored CCP screen includes prompt
SCHWAIT       DEFS      16                             ; background task parked on input
SCHFG         DEFB      0                              ; visible/keyboard-owning session
SCHNEXT       DEFB      0                              ; round-robin background cursor
SCHQLEFT      DEFB      SCHFGQ                         ; syscall quantum remaining
SCHEN         DEFB      0                              ; enabled if >=2 sessions

; Reclaimed MAIN $4000-$6FFF: permanent CCP SAVE and helpers.
; No AUX LC snapshot is ever written here.
; AUX56 CCP SAVE: dump transient pages from $0100 through $DDFF.
; Read the owning tab's ordinary AUX RAM and AUX LC in place.
; Select its RamWorks bank; never use a global high-memory snapshot.
; Only MAIN $AUXSTAGE is passed as the ProDOS write DMA buffer.
; ================================================================
              ORG       04000H
; F8/9 from AUX CCP: [ID][80-byte normalized tail][36-byte FCB].
; MAIN page-zero FCB2 is prepared by the AUX filename parser.
; Reject SAVE before any completed .COM; do NOT emit CCP.COM bytes.
AXBSAVE      LD        HL,(AXBPTR)
              LD        DE,116
              ADD       HL,DE
              LD        A,H
              CP        0DEH
              JP        NC,AXBAD
              LD        HL,(AXBPTR)
              LD        DE,81
              ADD       HL,DE
              LD        DE,FCB2
              LD        BC,36
              CALL      LCA2M
              LD        HL,FCB2NAM
              CALL      ISWILD
              OR        A
              JP        NZ,CCPBAD
              LD        A,(FILEBUF+2)
              CP        '0'
              JR        NZ,AXBSREQ                    ; nonzero SAVE needs a prior transient
              LD        A,(FILEBUF+3)
              CP        ' '
              JR        Z,AXBSRUN                    ; SAVE 0: empty file is allowed
AXBSREQ      CALL      SVSFPTR
              LD        A,(HL)
              OR        A
              JR        NZ,AXBSRUN
              LD        DE,SVSMSG
              CALL      C_WRITESTR
              RET
AXBSRUN      CALL      SAVEFILE
              ; Native SAVEFILE restores bank 0. A syscall must instead
              ; return to the active tab's physical RamWorks AUX bank.
              LD        A,(TABMODE)
              CALL      TABPHYS
              JP        AXBANK
SVSMSG        DEFM      'No previous .COM image to SAVE'
              DEFB      13,'$'

SAVEFILE      LD        HL,FILEBUF+2                   ; decimal pages (the first argument)
              LD        B,0
SVDEC         LD        A,(HL)
              CP        ' '
              JR        Z,SVNUM
              SUB       '0'
              JP        C,SVBAD
              CP        10
              JP        NC,SVBAD
              LD        C,A
              LD        A,B
              CP        23                             ; max previous value 22: 22*10+9<256
              JP        NC,SVBAD
              ADD       A,A
              LD        D,A
              ADD       A,A
              ADD       A,A
              ADD       A,D
              ADD       A,C
              CP        222                            ; legal pages: 0 through 221 (DDFF top)
              JP        NC,SVBAD
              LD        B,A
              INC       HL
              JR        SVDEC
SVNUM         LD        A,B
              LD        (SVPAGES),A
              CP        176                            ; higher pages need post-transient LC image
              JR        C,SVMAKE
              CALL      SVFLPTR
              LD        A,(HL)
              OR        A
              JP        Z,SVBAD                        ; no completed image in THIS tab
SVMAKE        LD        DE,FCB2
              CALL      F_MAKE
              OR        A
              JP        NZ,SVIOERR
              LD        HL,0100H
              LD        (SVPTR),HL
              LD        A,(SVPAGES)
              OR        A
              JR        Z,SVEMPTY
              LD        A,(TABMODE)
              CALL      TABPHYS
              CALL      AXBANK                         ; select owner of low RAM and AUX LC
              CALL      SVPREP                         ; preserve ProDOS's full MAIN LC bank2
SVPAGE        LD        A,(SVPAGES)
              OR        A
              JR        Z,SVDONE
              LD        B,2                            ; two 128-byte records per page
SVRECORD      PUSH      BC
              CALL      SVCOPY                         ; ordinary AUX or live AUX LC
              LD        HL,AUXSTAGE
              LD        (DMAADDR),HL
              LD        DE,FCB2
              CALL      F_WRITE                        ; normal MAIN ProDOS write
              POP       BC
              OR        A
              JR        NZ,SVFAIL
              DJNZ      SVRECORD
              LD        A,(SVPAGES)
              DEC       A
              LD        (SVPAGES),A
              JR        SVPAGE
SVDONE        LD        DE,FCB2
              CALL      F_CLOSE
              LD        (SVSTAT),A
              CALL      SVREST                         ; restore full MAIN LC bank2/common
              LD        A,(SVSTAT)
              OR        A
              JR        NZ,SVIOERR
              JR        SVRESET
SVFAIL        LD        DE,FCB2
              CALL      F_CLOSE
              CALL      SVREST                         ; must restore LC on write failure too
              JR        SVIOERR
SVEMPTY       LD        DE,FCB2                        ; SAVE 0: just create empty file
              CALL      F_CLOSE
              OR        A
              JR        NZ,SVIOERR
SVRESET       XOR       A
              CALL      AXBANK                         ; restore bank 0, including error paths
              LD        HL,FILEBUF
              LD        (DMAADDR),HL
              RET
SVIOERR       LD        DE,REMSG
              CALL      C_WRITESTR
              JR        SVRESET
SVBAD         LD        DE,BFMSG
              CALL      C_WRITESTR
              JR        SVRESET

; SAVE temporarily installs the AUX RAM read trampoline in MAIN LC.
; Preserve ProDOS MAIN LC across that operation and F_WRITE, using
; MAIN $1000-$3FFF (scratch only after the transient has terminated).
SVPREP        XOR       A
              LD        (SW80OFF),A
              LD        (ZPMAIN),A
              LD        (RDMAIN),A
              LD        (WRMAIN),A
              LD        A,(LCB2RW)
              LD        A,(LCB2RW)
              LD        HL,0B000H
              LD        DE,01000H
              LD        BC,03000H
              LDIR
              LD        A,(LCB1RO)
              RET

; Before $B000 use the MAIN LC trampoline to read ordinary AUX RAM.
; From $B000, use ALTZP to read the selected bank's live AUX LC.
; This routine itself executes in ordinary MAIN $4000 code and writes
; to MAIN $AUXSTAGE, so it does not execute from the switched LC.
SVCOPY        LD        A,(AXMODE)                    ; AUX CCP or legacy MAIN CCP?
              OR        A
              JR        Z,SVCPLIVE                   ; legacy SAVE: direct live RAM
              LD        HL,(SVPTR)
              LD        DE,02100H                     ; first 8K ($0100..$20FF)
              OR        A
              SBC       HL,DE
              JP        C,SVSREAD                     ; AUX CCP overwrote these pages
SVCPLIVE      LD        HL,(SVPTR)
              LD        DE,0B000H
              XOR       A
              SBC       HL,DE
              JR        NC,SVHIGH
              LD        A,(LCB2RW)
              LD        A,(LCB2RW)
              LD        HL,LCIMG
              LD        DE,LCBASE
              LD        BC,LCLEN
              LDIR
              LD        HL,(SVPTR)
              LD        DE,AUXSTAGE
              LD        BC,128
              CALL      LCA2M                          ; BC=0 on return; HL advanced 128
              LD        (SVPTR),HL
              LD        A,(LCB1RO)
              RET
SVHIGH        LD        A,(LCB2RW)
              LD        A,(LCB2RW)                     ; select LC bank 2 read/write
              XOR       A
              LD        (ZPAUX),A                      ; read high memory from selected AUX LC
              LD        HL,(SVPTR)
              LD        DE,AUXSTAGE
              LD        BC,128
              LDIR                                     ; AUX LC -> ordinary MAIN staging
              LD        (ZPMAIN),A                     ; ProDOS's MAIN LC and zero page
              LD        A,(LCB1RO)
              LD        HL,(SVPTR)
              LD        DE,128
              ADD       HL,DE
              LD        (SVPTR),HL
              RET

; Put back ProDOS's original MAIN LC bank 2/common after closing file.
SVREST        LD        A,(LCB2RW)
              LD        A,(LCB2RW)
              LD        HL,01000H
              LD        DE,0B000H
              LD        BC,03000H
              LDIR
              LD        A,(LCB1RO)
              RET
SVPAGES       DEFB      0
SVPTR         DEFW      0100H
SVSTAT        DEFB      0
; SAVE validity belongs to the logical tab, not to a shared snapshot.
; Each tab's completed image remains in its own physical RamWorks bank.
SVVALID       DEFS      16
SVSFLAGS      DEFS      16                            ; saved low TPA, one per logical tab
; Screen backing banks 2/5/10/15 each have their HGR data at $1000-$2FFF.
; Unused ordinary AUX RAM at $3000-$AFFF contains four 8KB images.
; TABMODE low two bits select the image slot within the backing bank.
SVSADDR      LD        HL,(SVPTR)
              LD        DE,02F00H                     ; $0100 -> $3000
              ADD       HL,DE
              LD        A,(TABMODE)
              AND       3
              ADD       A,A
              ADD       A,A
              ADD       A,A
              ADD       A,A
              ADD       A,A                          ; slot * $2000, high-byte delta 0,20,40,60
              ADD       A,H
              LD        H,A
              RET
SVSREAD      CALL      SVSADDR
              PUSH      HL
              CALL      VSSBANK
              CALL      AXBANK                       ; select image bank (2,5,10,15)
              POP       HL
              LD        DE,AUXSTAGE
              LD        BC,128
              CALL      LCA2M                       ; 128 bytes screen-bank AUX -> MAIN
              LD        HL,(SVPTR)
              LD        DE,128
              ADD       HL,DE
              LD        (SVPTR),HL
              LD        A,(TABMODE)
              CALL      TABPHYS
              CALL      AXBANK                       ; restore running program bank
              RET
SVSFPTR      LD        A,(TABMODE)
              LD        L,A
              LD        H,0
              LD        DE,SVSFLAGS
              ADD       HL,DE
              RET
; Called after a child exits, before the AUX CCP is reloaded. Staging
; MAIN $1000-$2FFF is safe while no AUX program executes. Never use
; this area in an ordinary running program or during a scheduler yield.
SVSSNAP      LD        A,(VSOK)
              OR        A
              RET       Z                           ; requires 3+ physical RamWorks banks
              LD        A,(TABMODE)
              CALL      TABPHYS
              CALL      AXBANK
              LD        HL,0100H
              LD        DE,01000H
              LD        BC,02000H
              CALL      LCA2M                       ; child AUX low 8K -> MAIN staging
              CALL      VSSBANK
              CALL      AXBANK
              LD        HL,01000H
              LD        A,(TABMODE)
              AND       3
              ADD       A,A
              ADD       A,A
              ADD       A,A
              ADD       A,A
              ADD       A,A
              ADD       A,030H
              LD        D,A
              LD        E,0
              LD        BC,02000H
              CALL      AXM2A                       ; MAIN staging -> backing-bank AUX
              XOR       A
              CALL      AXBANK
              CALL      SVSFPTR
              LD        (HL),1
              RET
SVFLPTR       LD        A,(TABMODE)
              LD        L,A
              LD        H,0
              LD        DE,SVVALID
              ADD       HL,DE
              RET
SVCLEAR       LD        HL,SVVALID
              LD        DE,SVVALID+1
              LD        BC,31                          ; clear SVVALID and SVSFLAGS
              XOR       A
              LD        (HL),A
              LDIR
              RET

; Resident BYE confirmation retained for ProDOS recovery.
; Stage 27: removed unused code/data (Unreferenced legacy uppercaser).
; Shared confirmation reader. A=0 for Y; A=1 for N.
; Invalid input is ignored; C_READ echoes typed characters.
CCPYESNO      CALL      C_WRITESTR
CYKEY         CALL      XSCCPKEY                       ; check active XSUB stream first
              AND       0DFH
              CP        'Y'
              JR        Z,CYYES
              CP        'N'
              JR        NZ,CYKEY
              XOR       A
              LD        (XSLEFT),A                     ; discard pending synthetic CR of Y/N record
              LD        E,13
              CALL      C_WRITE
              LD        A,1
              RET
CYYES         XOR       A
              LD        (XSLEFT),A
              LD        E,13
              CALL      C_WRITE
              XOR       A
              RET
CCPBYE        LD        DE,BYEASK
              CALL      CCPYESNO
              OR        A
              RET       NZ
              XOR       A
              LD        (CMD),A
              JP        BYERESUME                      ; Stable SoftCard handoff; next start is cold
BYEASK        DEFM      'Y/N? $'



; CCP's built-in command table and terminal selector live in the unused
; MAIN-memory TPA.  $7600-$77FF is free of AXBDOS ($7000-$73xx)
; and the permanent AUX bridge staging region ($7800 onward).

; ---------------------------------------------------------------------
; Reclaimed MAIN ($4400 onward): IOBYTE devices + resident workspaces.
; This is ordinary, unbanked MAIN RAM: never part of an AUX transient.
; ---------------------------------------------------------------------
; ================================================================
; CP/M IOBYTE / physical serial and printer devices.
; MAIN $4400: former AUX LC snapshot space, now persistent MAIN code.
; Apple monitor slot firmware entry $Cn00 via Z80->6502 CMD=1.
; During ROM call set CSW/KSW appropriately so input/output is
; unambiguous to slot firmware. Restore monitor vectors on return.
; No per-card UART registers used. ROM input is blocking and 7-bit.
; ================================================================
              ORG       04400H
; Physical LST: from IOBYTE bits 7:6:
; TTY=serial2, CRT=screen, LPT=printer1, UL1=serial2.
IOLIST        LD        A,(IOBYTE)
              AND       0C0H
              CP        040H
              JP        Z,IOVOUT
              CP        080H
              JP        Z,IOPRN
              JP        IOSEROUT
; RDR and PUN are routed through their own IOBYTE fields.
; The selectors live at MAIN $4C00 to avoid crowding the slot driver.
IOPUNCH       JP        IOPUNSEL
IOREADER      JP        IORDRSEL
; CON: CRT=VRAWPUT, BAT=RDR input / LST output; TTY/UC1=serial2.
IOCONOUT      LD        A,(IOBYTE)
              AND       3
              CP        3
              JP        Z,UCOUT                         ; UC1: socket-backed console
              CP        2
              JP        Z,IOLIST
              JP        IOSEROUT
IOVOUT        LD        A,E
              LD        HL,RAWOUT
              JP        C_SENDA
; Main/AUX redirected BDOS 1 input. Console echo uses selected device.
IOCCOOK       CALL      IOCONIN
              PUSH      AF
              LD        E,A
              CALL      IOCONOUT
              POP       AF
              LD        L,A
              RET
; No portable poll-ready entry in arbitrary slot firmware.
; Conservative CONST = 00; LISTST = FF (blocking output driver).
IOZERO        XOR       A
              LD        L,A
              RET
IOSTAT        LD        A,(IOBYTE)
              AND       3
              CP        3
              JP        Z,UCSTAT
              JP        IOZERO
; Firmware output. E=CP/M character. Physical slot selected in A.
IOPRN         LD        A,010H
              LD        HL,0C100H
              JP        IOSEND
IOSEROUT      LD        A,020H
              LD        HL,0C200H
IOSEND        PUSH      BC
              PUSH      DE
              PUSH      HL
              LD        (XREG),A                       ; Apple slot ROMs conventionally use X=n*16
              LD        A,E
              OR        080H                           ; Apple monitor character convention
              LD        (AREG),A
              LD        (ADDR),HL
              LD        HL,(0F036H)                    ; 6502 monitor CSW
              PUSH      HL
              LD        HL,(0F038H)                    ; KSW
              PUSH      HL
              LD        HL,(ADDR)
              LD        (0F036H),HL                    ; current slot output
              LD        HL,0FD1BH                      ; native keyboard, not this slot
              LD        (0F038H),HL
              ; Card ROM invokes Apple Monitor at $Fxxx.  Normally the
              ; MAIN LC RAM is selected ($C088), so expose ROM briefly.
              LD        A,(0E08AH)                     ; 6502 $C08A: bank 1, read ROM
              LD        A,1
              LD        (CMD),A
              LD        (SOFTCARD),A
              LD        A,(LCB1RO)                     ; restore bank 1 LC RAM for ProDOS
              POP       HL
              LD        (0F038H),HL
              POP       HL
              LD        (0F036H),HL
              POP       HL
              POP       DE
              POP       BC
              XOR       A
              LD        L,A
              RET
; Input from slot 2. Firmware is blocking; high bit is Apple's
; character marker, not reliable serial 8-bit data, so strip it.
IOSERIN       PUSH      BC
              PUSH      DE
              PUSH      HL
              LD        A,020H
              LD        (XREG),A
              LD        HL,0C200H
              LD        (ADDR),HL
              LD        HL,(0F036H)
              PUSH      HL
              LD        HL,(0F038H)
              PUSH      HL
              LD        HL,0FDF0H                      ; monitor video COUT1 != slot 2
              LD        (0F036H),HL
              LD        HL,0C200H
              LD        (0F038H),HL                    ; select slot 2 as input
              ; Slot firmware can call the Monitor ROM at $Fxxx.
              LD        A,(0E08AH)                     ; 6502 $C08A: bank 1, read ROM
              LD        A,1
              LD        (CMD),A
              LD        (SOFTCARD),A
              LD        A,(LCB1RO)                     ; restore bank 1 LC RAM for ProDOS
              LD        A,(AREG)
              AND       07FH
              LD        (IOCHAR),A
              POP       HL
              LD        (0F038H),HL
              POP       HL
              LD        (0F036H),HL
              POP       HL
              POP       DE
              POP       BC
              LD        A,(IOCHAR)
              LD        L,A
              RET
IOCHAR        DEFB      0

              ORG       04500H
; 64 byte buffer for storing a file path as a Pascal style string
PATHBUF
PATHLEN       DEFB      0
PATH          DEFS      64

; 64 byte buffer for storing a second file path as a Pascal style string
PATHBUF2
PATHLEN2      DEFB      0
PATH2         DEFS      64

; Record file reference numbers for each I/O buffer
; Or 0 if no file is using the buffer
FRN1          DEFB      0
FRN2          DEFB      0
FRN3          DEFB      0
FRN4          DEFB      0

; 512 byte buffer for reading directories (used by F_SFIRST and F_SNEXT)
DIRBUF
DIRBUF1       DEFS      128
DIRBUF2       DEFS      128
DIRBUF3       DEFS      128
DIRBUF4       DEFS      128

              ORG       04800H
; Drive read-only check/reporter is an independent helper. Move it out
; of resident $8100-$97FF, which must not overlap IOBUF1 at $9800.
; Its callers use CALL DCHKRO / JP RODENY; all JR targets stay local.
DCHKRO        PUSH      BC
              PUSH      HL
              XOR       A
              LD        (ROERROR),A                    ; Clear stale error from previous call
              LD        A,(DE)
              OR        A
              JR        NZ,DCR_EXPL
              LD        A,(CURDRV)
              AND       0FH
              JR        DCR_IDX
DCR_EXPL      DEC       A
DCR_IDX       CP        16
              JR        NC,DCR_BAD
              LD        (RODRIVE),A                    ; Actual effective drive for message
              LD        B,A
              LD        HL,(ROVEC)
              LD        A,B
              OR        A
              JR        Z,DCR_BIT
DCR_SHF       SRL       H
              RR        L
              DEC       A
              JR        NZ,DCR_SHF
DCR_BIT       LD        A,L
              AND       01H
              JR        DCR_DONE
DCR_BAD       LD        A,1
              OR        A
DCR_DONE      POP       HL
              POP       BC
              RET
RODENY        JP        RODISK                         ; CP/M: BDOS Err on d: R/O



              ORG       04900H
; SUBMIT: diagnostics removed; preserve zero-length-file safeguard.
; CP/M 2.2 SUBMIT: A:$$$.SUB contains reversed 128-byte records.
; Record byte 0 is the command length, followed by command characters.
; On entry from CCPREAD, return A=1 with FILEBUF+1 count and +2 text,
; or A=0 when there is no pending command. Consume record ON DISK first.
; All filesystem buffers/ProDOS handles are MAIN-owned; only the CCP
; invokes this routine. The fixed FCB explicitly selects drive A.
; Native XSUB: this same record reader is called from the CCP and
; the AUX BDOS 0Ah handler.  A=1 means SUBREC has a valid next line;
; A=0 means absent/invalid submission (fall back to keyboard).
CCPSUB        XOR       A
              LD        (XSLEFT),A                     ; discard a previous program's partial line
              CALL      XSNEXT                         ; preserves the MAIN DMA pointer
              LD        (SBFROM),A                     ; current CCP line came from $$$.SUB
              OR        A
              JR        NZ,SBCCOPY
              LD        (XSFLAG),A                     ; stream ended, future scripts start disabled
              RET
SBCCOPY       JP        SBCOPY
SBNEXT        LD        A,(SBHALT)
              OR        A
              JR        Z,SBSTART
              XOR       A
              RET
SBSTART       LD        HL,SUBFCB+12
              LD        B,24
              XOR       A
SBCLEAR       LD        (HL),A
              INC       HL
              DJNZ      SBCLEAR
              LD        DE,SUBFCB
              CALL      F_OPEN
              OR        A
              JR        Z,SBOPEN
              XOR       A                              ; no $$$.SUB: normal keyboard input
              RET
SBOPEN        LD        DE,SUBFCB
              CALL      F_SIZE                         ; fills FCB random records 21H..23H
              OR        A
              JP        NZ,SBERROR
              LD        HL,(SUBFCB+21H)
              LD        A,H
              OR        L
              JR        NZ,SBHAVE
              LD        A,(SUBFCB+23H)
              OR        A
              JP        Z,SBZERO                       ; retain anomalous zero-sized file
SBHAVE                      ; Move random record index to the LAST existing record.
              LD        HL,(SUBFCB+21H)
              LD        A,H
              OR        L
              JR        NZ,SBDEC
              LD        HL,SUBFCB+23H
              DEC       (HL)                           ; borrow from high record counter
SBDEC         LD        HL,(SUBFCB+21H)
              DEC       HL
              LD        (SUBFCB+21H),HL
              LD        HL,SUBREC
              LD        (DMAADDR),HL
              LD        DE,SUBFCB
              CALL      F_READRAND
              LD        HL,FILEBUF
              LD        (DMAADDR),HL
              OR        A
              JP        NZ,SBERROR
              LD        A,(SUBREC)
              OR        A
              JP        Z,SBERROR                      ; never silently eat an empty/bad record
              CP        121
              JP        NC,SBERROR                     ; cannot fit CCP's 120-char buffer
              ; R0..R2 now contain the number of records to retain.
              LD        HL,(SUBFCB+21H)
              LD        A,H
              OR        L
              JR        NZ,SBTRUNC
              LD        A,(SUBFCB+23H)
              OR        A
              JR        NZ,SBTRUNC
              JP        SBEMPTY
SBZERO                      ; Preserve unexpectedly empty $$$.SUB for inspection.
              ; Mark halted to prevent a new attempt at every CCP prompt.
              LD        DE,SUBFCB
              CALL      F_CLOSE
              LD        A,1
              LD        (SBHALT),A
              LD        DE,SBZEROMSG
              CALL      C_WRITESTR
              XOR       A
              RET
SBEMPTY       LD        DE,SUBFCB
              CALL      F_CLOSE
              OR        A
              JP        NZ,SBERROR
              LD        DE,SUBFCB
              CALL      F_DELETE                       ; last command: ERA $$$.SUB
              OR        A
              JP        NZ,SBERROR
              JP        SBDONE
SBTRUNC                     ; Truncate an open ProDOS file to R0..R2 * 128 bytes.
              ; IO_BEGIN temporarily loans S2 to the physical ProDOS FRN.
              LD        IX,SUBFCB
              CALL      IO_BEGIN
              OR        A
              JP        NZ,SBERROR
              LD        A,(IX+0EH)
              LD        (SEMLIN),A
              LD        HL,(SUBFCB+21H)
              LD        A,(SUBFCB+23H)
              LD        B,7
SBSHIFT       ADD       HL,HL
              RLA
              DJNZ      SBSHIFT
              LD        (SEMLIE1),HL
              LD        (SEMLIE3),A
              LD        HL,SEMLI
              CALL      PRODOS
              CALL      IO_END                         ; restore the caller's S2
              PUSH      AF
              LD        DE,SUBFCB
              CALL      F_CLOSE
              LD        B,A
              POP       AF
              OR        A
              JP        NZ,SBERROR
              LD        A,B
              OR        A
              JP        NZ,SBERROR
SBDONE        LD        A,1                            ; record consumed; SUBREC remains valid
              RET
SBCOPY        LD        A,(SUBREC)
              ; Length was checked while the on-disk record still existed.
              LD        (FILEBUF+1),A
              LD        C,A
              LD        A,120
              LD        (FILEBUF),A
              LD        B,0
              LD        HL,SUBREC+1
              LD        DE,FILEBUF+2
              LDIR
              ; Echo the submitted command just as if typed at the prompt.
              LD        HL,SUBREC+1
              LD        A,(SUBREC)
              LD        B,A
SBECHO        LD        E,(HL)
              PUSH      HL
              PUSH      BC
              CALL      C_WRITE
              POP       BC
              POP       HL
              INC       HL
              DJNZ      SBECHO
              LD        E,13
              CALL      C_WRITE
              LD        A,1
              RET
SBERROR       LD        DE,SUBFCB
              CALL      F_CLOSE                        ; best effort, preserve file for diagnosis
              LD        A,1
              LD        (SBHALT),A                     ; do not retry corrupt file every prompt
              LD        DE,SBERRMSG
              CALL      C_WRITESTR
              XOR       A
              RET
SBERRMSG      DEFM      'SUBMIT invalid record or I/O error (file retained)'
              DEFB      13,'$'
SBZEROMSG     DEFM      'SUBMIT zero records - $$$.SUB retained for inspection'
              DEFB      13,'$'
SBHALT        DEFB      0
SUBFCB        DEFB      1
              DEFM      '$$$     SUB'
              DEFS      24
SUBREC        DEFS      128
; A WBOOT from a background AUX tab must never reset the foreground
; CCP stack. Defer it until that tab becomes the visible CCP.
SBW_PTR       LD        A,(TABMODE)
              LD        E,A
              LD        D,0
              LD        HL,SBWARM
              ADD       HL,DE
              RET
SBWSET        LD        A,(AXQUIT)
              CP        1
              RET       NZ
              CALL      SBW_PTR
              LD        (HL),1
              RET
SBWGET        CALL      SBW_PTR
              LD        A,(HL)
              RET
SBWCLR        CALL      SBW_PTR
              LD        (HL),0
              RET
SBWARM        DEFS      16

; ---------------------------------------------------------------------
; IOBYTE RDR:/PUN: routing.  CP/M physical device names are BIOS-defined.
; This system has only one serial port, so TTY and PTR/PTP both use slot 2.
; UP1 = parallel printer (slot 1); UP2 = Zapple screen.
; UR1 = Apple keyboard (blocking/no echo); UR2 = immediate CP/M EOF (^Z).
; IOBYTE field bits: RDR 3:2, PUN 5:4.
; Keep out of the 256-byte slot-firmware bridge at $4400-$44FF.
; ---------------------------------------------------------------------
              ORG       04C00H
IOPUNSEL      LD        A,(IOBYTE)
              AND       030H
              CP        020H
              JP        Z,IOPRN                        ; UP1: slot 1 printer
              CP        030H
              JP        Z,IOVOUT                       ; UP2: built-in video
              JP        IOSEROUT                       ; TTY/PTP: shared slot 2 serial
IORDRSEL      LD        A,(IOBYTE)
              AND       00CH
              CP        008H
              JP        Z,IORDKEY                      ; UR1: built-in keyboard
              CP        00CH
              JP        Z,IORDEOF                      ; UR2: no reader, return EOF
              JP        IOSERIN                        ; TTY/PTR: shared slot 2 serial
IORDKEY       LD        HL,RDKEY                       ; 6502 VGET, blocking, no echo
              LD        (ADDR),HL
              LD        A,1
              LD        (CMD),A
              LD        (SOFTCARD),A
              LD        A,(AREG)
              AND       07FH
              LD        L,A
              RET
IORDEOF       LD        A,01AH                         ; CP/M text EOF
              LD        L,A
              RET
; CON:=BAT: uses RDR: for input; other non-CRT console modes use serial.
IOCONIN       LD        A,(IOBYTE)
              AND       3
              CP        3
              JP        Z,UCIN                          ; UC1: socket-backed console
              CP        2
              JP        Z,IOREADER
              JP        IOSERIN

; New UC1 code lives in previously unused MAIN $4D00..$4FFF.
; Keep NETEND at its original location so the resident stack does not shrink.
              ORG       04D00H
; ------------------------------------------------------------------
; Phase 6B: UC1 (CON:=UC1:, low IOBYTE bits = 3) TCP console.
; Private BDOS $FD: E=1 bind D=socket, E=0 unbind, E=2 query.
; A=L returns 0 (success), FF (failure), or socket for query.
; Binding requires the current tab to own the allocated socket.
; Uses the same NXTX/NXRX ring code with MAIN-resident staging; no
; reentrant AUX BDOS or temporary AUX address is involved.
; This stage tests a single raw TCP console via nc(1).  Telnet IAC,
; nonblocking scheduler integration, and shell lifetime handoff remain
; Phase 6C work; DO NOT attach an idle remote CCP yet.
; ------------------------------------------------------------------
NCAPI         LD        A,E
              OR        A
              JP        Z,NCUNB
              CP        1
              JP        Z,NCBIND
              CP        2
              JP        Z,NCQUERY
              CP        3
              JP        Z,NCARM                       ; persist existing UC1 binding across CCP reload
              JP        NETBAD
NCBIND        LD        A,D
              CP        4
              JP        NC,NETBAD
              PUSH      DE
              CALL      NETPTR
              LD        A,(TABMODE)
              CP        (HL)
              POP       DE
              JP        NZ,NETBAD
              PUSH      DE                             ; UCBPTR uses DE for indexing
              CALL      UCBPTR
              POP       DE
              LD        (HL),D
              CALL      UCRPTR
              LD        (HL),0
              CALL      TNTPTR                         ; reset TELNET parser for this binding
              LD        (HL),0
              XOR       A
              JP        NETRET
NCUNB         CALL      UCPPTR
              LD        (HL),0                        ; unbind always revokes persistence
              CALL      UCBPTR
              LD        (HL),0FFH
              CALL      UCRPTR
              LD        (HL),0
              CALL      TNTPTR
              LD        (HL),0
              XOR       A
              JP        NETRET
NCQUERY       CALL      UCBPTR
              LD        A,(HL)
              JP        NETRET
NCARM         CALL      UCBPTR
              LD        A,(HL)
              CP        4
              JP        NC,NETBAD                     ; require an allocated UC1 socket
              CALL      NETPTR
              LD        A,(TABMODE)
              CP        (HL)
              JP        NZ,NETBAD
              CALL      UCPPTR
              LD        (HL),1
              XOR       A
              JP        NETRET
; Resolve per-tab bind and pending-byte arrays. DE/HL clobbered.
UCBPTR        LD        A,(TABMODE)
              LD        E,A
              LD        D,0
              LD        HL,UCBIND
              ADD       HL,DE
              RET
UCRPTR        LD        A,(TABMODE)
              LD        E,A
              LD        D,0
              LD        HL,UCREADY
              ADD       HL,DE
              RET
UCDPTR        LD        A,(TABMODE)
              LD        E,A
              LD        D,0
              LD        HL,UCCHAR
              ADD       HL,DE
              RET
UCPPTR        LD        A,(TABMODE)
              LD        E,A
              LD        D,0
              LD        HL,UCPERS
              ADD       HL,DE
              RET
; Called after NETFREE with A=socket. Clear only matching binding.
NCSFRE        PUSH      AF
              CALL      UCBPTR
              POP       AF
              CP        (HL)
              RET       NZ
              JP        NCUNB
; Called from NETCLN with B=tab (may not be currently selected).
NCXCLN        PUSH      BC
              LD        E,B
              LD        D,0
              LD        HL,UCBIND
              ADD       HL,DE
              LD        (HL),0FFH
              LD        HL,UCREADY
              ADD       HL,DE
              LD        (HL),0
              LD        HL,TNSTATE
              ADD       HL,DE
              LD        (HL),0
              POP       BC
              RET
; UCSTAT returns FF if a byte is pending, otherwise 0.
; Consumes from TCP only to fill per-tab cache, not on every peek.
UCSTAT        PUSH      BC
              PUSH      DE
              PUSH      HL
UCAGAIN       CALL      UCRPTR
              LD        A,(HL)
              OR        A
              JR        NZ,UCREADY1
              CALL      UCBPTR
              LD        A,(HL)
              CP        4
              JR        NC,UCEMPTY
              LD        (NXSOCK),A
              LD        A,1
              LD        (NXREQ),A
              LD        (UCFLAG),A
              CALL      NXRX
              PUSH      AF
              XOR       A
              LD        (UCFLAG),A
              POP       AF
              CP        1
              JR        NZ,UCDISC
              LD        A,(NXBUF)
              CALL      TNFEED                         ; C=1: ordinary key, C=0: TELNET protocol
              JR        NC,UCAGAIN                     ; consume IAC and retry without nesting stack
              LD        C,A                            ; save parsed key: UCDPTR overwrites A
              CALL      UCDPTR
              LD        (HL),C                          ; cache real character, not TABMODE
              CALL      UCRPTR
              LD        (HL),1
              JP        UCREADY1                      ; successful RX is ready NOW
; Socket CLOSE_WAIT/CLOSED: let the blocked read finish and ask the
; supervisor to terminate the *entire tab*, not reassign the still-running
; application to the physical console. Drain any pending RX data first.
UCDISC        LD        A,(NXSOCK)
              LD        D,A
              LD        A,3
              CALL      NI_READ
              CP        01CH                         ; SOCK_CLOSE_WAIT
              JR        Z,UCDOWN
              OR        A
              JR        NZ,UCEMPTY                     ; established/listen, no RX
UCDOWN        CALL      UCDPTR
              LD        (HL),13                        ; wake reader; do not invoke CCP ^C handler
              CALL      UCRPTR
              LD        (HL),1
              CALL      UCPPTR
              LD        (HL),2                         ; pending local fallback
UCREADY1      LD        A,0FFH
              JR        UCSDONE
UCEMPTY       XOR       A
UCSDONE       POP       HL
              POP       DE
              POP       BC
              LD        L,A
              RET
; BDOS 06 input. If a network byte is available return it;
; otherwise return A=L=0 without consuming keyboard input.
UC6IN         CALL      UCSTAT
              OR        A
              JP        Z,IOZERO
              JP        UCIN
; For Phase 6B this is a polling read. A nonblocking/yielding
; remote CCP is not safe until scheduler wakeup is implemented.
UCIN          CALL      UCSTAT
              OR        A
              JR        Z,UCIN
              CALL      UCDPTR
              LD        A,(HL)
              PUSH      AF
              CALL      UCRPTR
              LD        (HL),0
              POP       AF
              CP        0AH
              JR        NZ,UCNOTLF
              LD        A,0DH                          ; nc(1) sends LF for Enter
UCNOTLF       PUSH      AF
              CALL      UCPPTR
              LD        A,(HL)
              CP        2
              JR        NZ,UCINNOD
              CALL      NCDROP                         ; restore local console on disconnect
UCINNOD       POP       AF
              PUSH      AF
              XOR       A
              LD        (XREG),A                       ; remote key cannot trigger OA tab hotkeys
              POP       AF
              LD        L,A
              RET
; E=byte. Output via NXTX using existing W5100 driver. This is
; deliberately single-byte, not a duplicate ring implementation.
UCOUT         PUSH      BC
              PUSH      DE
              PUSH      HL
              LD        A,(AXQUIT)
              CP        5
              JR        Z,UCOEND                       ; on disconnect, discard echo/output
              LD        A,E
              LD        (NXBUF),A
              CALL      UCBPTR
              LD        A,(HL)
              CP        4
              JR        NC,UCOEND
              LD        (NXSOCK),A
; No implicit CRLF translation: the application owns line endings.
UCOSEND       JP        UC_TXTRY                       ; remote TX, including disconnect check
UCOEND        POP       HL
              POP       DE
              POP       BC
              RET
; Explicitly initialized arrays: DEFS does not promise zero fill.
UCFLAG        DEFB      0
UCBIND        DEFB      0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH
              DEFB      0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH
UCREADY       DEFB      0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
UCCHAR        DEFB      0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
UCPERS        DEFB      0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

; Do not extend MAIN $7C00..$7EBF (AUX BDOS entry), which ends immediately
; before the scheduler's fixed ORG $7EC0. Keep both hooks three bytes each.
UC6FG         LD        A,(IOBYTE)
              AND       3
              CP        3
              RET       Z                              ; UC1 can poll without owning CRT
              JP        SCHISFG                        ; normal foreground gate unchanged
UC6CUR        PUSH      AF
              LD        A,(IOBYTE)
              AND       3
              CP        3
              JR        NZ,UC6CRT
              POP       AF
              OR        A                              ; clear C: no deferred physical keyboard
              RET
UC6CRT        POP       AF
              JP        AB6CUR                         ; preserve original CRT cursor logic

; ---------------------------------------------------------------------
; Phase 6C: scheduler hooks (MAIN $4Dxx, after Phase 6B console).
; The local physical keyboard is NEVER read for a remote UC1 task.
; Remote tab 1+ should be left in the background while tab 0 owns CRT.
; ---------------------------------------------------------------------
; Original SCHPRE prologue occupies 3 bytes at $7Exx, now a JP here.
; Follow the original source from SCHPRE+3 for CRT/serial unchanged.
NCPRE         LD        A,(IOBYTE)
              AND       3
              CP        3
              JR        Z,NCPUC
              LD        A,(IOBYTE)
              JP        SCHPRE+3                       ; original AND/CP/JR from $7Exx
NCPUC         LD        A,C
              CP        1
              JR        Z,NCPREAD
              CP        10
              JR        Z,NCPREAD
              CP        0F2H
              JR        NZ,NCPALLOW
NCPREAD       CALL      UCSTAT                         ; FF if input cached
              OR        A
              RET       NZ                             ; never call physical BIOSCONST for UC1
              LD        A,C
              CP        1
              JP        Z,SPCOOK
              CP        10
              JP        Z,SPLINE
              JP        SPBIOS
NCPALLOW      OR        A                              ; no deferral for unrelated calls
              RET
; At BDOS-10 input, yield even in the middle of a line instead of
; blocking all tasks waiting for the next byte of a remote command.
NCALINE       LD        A,(IOBYTE)
              AND       3
              CP        3
              JR        NZ,NCALREAD
              CALL      UCSTAT
              OR        A
              JR        NZ,NCALREAD
              PUSH      DE
              PUSH      HL
              CALL      SCHBLCK
              POP       HL
              POP       DE
              LD        A,3
              LD        (AXQUIT),A
              SCF
              RET
NCALREAD      PUSH      BC
              PUSH      HL
              CALL      BIOSCONIN
              POP       HL
              POP       BC
              OR        A                              ; clear C, preserve character
              RET
; C = candidate background task. On UC1 wait, scheduler must continue
; polling even while no packet has arrived, rather than enter local VGET.
; Return Z if task should keep the foreground input loop polling.
NCSHCHK       PUSH      BC
              PUSH      DE
              PUSH      HL
              CALL      NCHSLOT
              JR        Z,NCHOK                       ; already runnable
              CALL      NCHBIND
              CP        4
              JR        C,NCHOK                       ; UC1 parked => poll while idle
              LD        A,1
              JR        NCHDONE
NCHOK         XOR       A
NCHDONE       POP       HL
              POP       DE
              POP       BC
              OR        A
              RET
; For actually scheduling, only resume when network RX data, cached
; char or socket CLOSED/CLOSE_WAIT. Never spin inside UCIN.
NCSOCHK       PUSH      BC
              PUSH      DE
              PUSH      HL
              CALL      NCHSLOT
              JR        Z,NCSRUN
              CALL      NCHBIND
              CP        4
              JR        NC,NCSBLCK
              LD        D,A                            ; physical socket
              LD        E,C
              LD        D,0
              LD        HL,UCREADY
              ADD       HL,DE
              LD        A,(HL)
              OR        A
              JR        NZ,NCSWAKE
              CALL      NCHBIND
              LD        D,A
              LD        A,3
              CALL      NI_READ                        ; Sn_SR
              CP        01CH
              JR        Z,NCSWAKE                      ; peer half-closed, wake to clean up
              OR        A
              JR        Z,NCSWAKE                      ; fully closed
              LD        A,026H
              CALL      NI_READ                        ; RX received size high
              OR        A
              JR        NZ,NCSWAKE
              LD        A,027H
              CALL      NI_READ                        ; RX received size low
              OR        A
              JR        Z,NCSBLCK
NCSWAKE       LD        E,C
              LD        D,0
              LD        HL,SCHWAIT
              ADD       HL,DE
              LD        (HL),0
NCSRUN        XOR       A
              JR        NCSDONE
NCSBLCK       LD        A,1
NCSDONE       POP       HL
              POP       DE
              POP       BC
              OR        A
              RET
NCHSLOT       LD        E,C
              LD        D,0
              LD        HL,SCHWAIT
              ADD       HL,DE
              LD        A,(HL)
              OR        A
              RET
NCHBIND       LD        E,C
              LD        D,0
              LD        HL,UCBIND
              ADD       HL,DE
              LD        A,(HL)
              RET
; Called after consuming the synthetic disconnect CR from UCIN.
; Abort via AUX gateway; never reassign the still-running program to CRT.
NCDROP        LD        A,5                           ; new remote-session abort code
              LD        (AXQUIT),A                    ; AXGATE will not resume AUX app
              RET                                     ; cleanup only after leaving AUX
; Shell EXIT/BDOS 0: restart a persistent network listener, or perform
; ordinary cleanup for local shells.  Called after AUX has fully exited.
NCSTOP        PUSH      BC
              LD        E,B
              LD        D,0
              LD        HL,UCPERS
              ADD       HL,DE
              LD        A,(HL)
              OR        A
              JR        Z,NCSTEND
              POP       BC
              JP        NC_REARM                        ; remote EXIT also re-listens
NCSTEND       POP       BC
              JP        NETKILL
              ORG       05000H
; Native XSUB: opt-in only by an XSUB directive *inside* .SUB.
; No resident AUX code; submit input stays in MAIN and is owned by one tab.
CCPXSUB       LD        A,(SBFROM)
              OR        A
              RET       Z                              ; manual XSUB does not enable batch mode
              LD        A,(TABMODE)
              LD        (XSOWNER),A
              LD        A,1
              LD        (XSFLAG),A
              XOR       A
              LD        (XSLEFT),A
              RET

; SBNEXT uses the shared MAIN DMA pointer. Don't perturb its caller.
XSNEXT        PUSH      BC
              PUSH      DE
              PUSH      IX
              PUSH      IY
              LD        HL,(DMAADDR)
              PUSH      HL
              CALL      SBNEXT
              POP       HL
              LD        (DMAADDR),HL
              POP       IY
              POP       IX
              POP       DE
              POP       BC
              RET

; A=1 if native XSUB is enabled for the current tab; A=0 otherwise.
; XSUB may redirect application console input, never CCP keyboard entry.
; The AUX supervisor marks the shell 1 and the launched child 2 in
; SHFLAGS[tab].  A lingering XSUB stream must not intercept the CCP's
; BDOS 10 fallback (or another shell console request).
XSENABL       PUSH      BC
              LD        A,(XSFLAG)
              OR        A
              JR        Z,XSEOFF
              LD        A,(TABMODE)
              LD        B,A
              LD        A,(XSOWNER)
              CP        B
              JR        NZ,XSEOFF
              PUSH      DE
              PUSH      HL
              CALL      SHPTR                          ; HL=&SHFLAGS[TABMODE]
              LD        A,(HL)
              POP       HL
              POP       DE
              CP        2                              ; 2=child, 1=shell
              JR        NZ,XSEOFF
              LD        A,1
              POP       BC
              RET
XSEOFF        XOR       A
              POP       BC
              RET

; Avoid parking a tab on physical keyboard input when a scripted
; character is actually ready. For other BDOS calls keep normal SCHPRE.
XSPRE         LD        A,C
              CP        1                              ; cooked BDOS CONIN
              JR        Z,XSPCHECK
              CP        10                             ; buffered BDOS CONIN
              JR        Z,XSPCHECK
              CP        0F2H                           ; BIOS CONIN
              JP        NZ,SCHPRE
XSPCHECK      CALL      XSREADY
              OR        A                              ; clear carry on a ready virtual byte
              RET       NZ
              JP        SCHPRE

; Lazy reverse-record fetch: pending line, then CR. Polls may prefetch,
; but the same record is subsequently consumed by *any* input API.
; Return A=1 when a character is ready; zero when none.
XSREADY       CALL      XSENABL
              OR        A
              RET       Z
              LD        A,(XSLEFT)
              OR        A
              JR        NZ,XSYES
              CALL      XSNEXT
              OR        A
              JR        Z,XSEOF
              LD        A,(SUBREC)
              INC       A
              LD        (XSLEFT),A
              LD        HL,SUBREC+1
              LD        (XSPTR),HL
XSYES         LD        A,1
              RET
XSEOF         XOR       A
              LD        (XSFLAG),A                     ; future submissions require XSUB again
              RET

; Carry set and A=byte when scripted, carry clear when keyboard needed.
XSCHAR        PUSH      BC
              PUSH      DE
              PUSH      HL
              CALL      XSREADY
              OR        A
              JR        Z,XSCNONE
              LD        A,(XSLEFT)
              DEC       A
              LD        (XSLEFT),A
              JR        Z,XSCR
              LD        HL,(XSPTR)
              LD        A,(HL)
              INC       HL
              LD        (XSPTR),HL
              JR        XSCGOT
XSCR          LD        A,13
XSCGOT        SCF
              JR        XSCEXIT
XSCNONE       XOR       A                              ; no virtual byte: carry clear
XSCEXIT       POP       HL
              POP       DE
              POP       BC
              RET

; Native MAIN BYE confirmation uses C_READ directly, not BDOS 0Ah/01h.
; Echo synthetic input just like C_READ does, otherwise original read.
XSCCPKEY      CALL      XSCHAR
              JP        NC,TSKCIN                      ; shell-safe ^C in BYE confirmation
              PUSH      AF
              LD        E,A
              CALL      C_WRITE
              POP       AF
              RET

; AUX BDOS 01: cooked, echoing input; normal scheduler when no script.
XSCIN         CALL      XSCHAR
              JP        NC,AXCIN
              LD        L,A
              PUSH      HL
              LD        E,A
              CALL      C_WRITE
              POP       HL
              LD        A,L
              RET

; AUX BIOS CONIN: raw input, no echo.
XSBIIN        CALL      XSCHAR
              JP        NC,AXBIREAD
              LD        L,A
              RET

; AUX BDOS 06: substitute only when E=FF (input mode).
XSRAW         LD        A,E
              CP        0FFH
              JP        NZ,AUXBDOS6
              CALL      XSCHAR
              JP        NC,AUXBDOS6
              LD        L,A
              RET

; AUX BDOS 11 and BIOS CONST: status polls see pending SUBMIT input.
XSSTAT        CALL      XSREADY
              OR        A
              JP        Z,ABDSTAT
              LD        A,0FFH
              LD        L,A
              RET
XSBSTAT       CALL      XSREADY
              OR        A
              JP        Z,AXBICON
              LD        A,0FFH
              LD        L,A
              RET

; AUX BDOS 0Ah: consume the *same* pending character stream as 01/06.
; This matters if an app polls before asking for buffered input, or
; consumes the first few characters via BDOS 01h before using 0Ah.
; AXLINE has validated caller buffer and fetched its capacity into AXLBUF.
AXLSUB        LD        B,0                            ; number of chars copied
              LD        HL,AXLBUF+2
XSLNEXT       PUSH      BC
              PUSH      HL
              CALL      XSCHAR
              POP       HL
              POP       BC
              JR        NC,XSLDONE
              CP        13
              JR        Z,XSLDONE
              LD        C,A                            ; preserve character
              LD        A,(AXLBUF)
              CP        B
              JR        Z,XSLNEXT                      ; discard beyond caller's capacity
              LD        (HL),C
              INC       HL
              INC       B
              PUSH      HL
              PUSH      BC
              LD        E,C
              CALL      C_WRITE
              POP       BC
              POP       HL
              JR        XSLNEXT
XSLDONE       LD        (HL),13
              LD        A,B
              LD        (AXLBUF+1),A
              LD        C,A
              LD        B,0
              INC       BC                             ; first buffer byte (maximum)
              INC       BC                             ; count byte
              INC       BC                             ; trailing CR
              LD        HL,AXLBUF
              LD        DE,(AXLIP)
              CALL      AXM2A
              LD        E,13
              CALL      C_WRITE
              XOR       A
              LD        L,A
              RET

XSFLAG        DEFB      0
XSOWNER       DEFB      0
SBFROM        DEFB      0
XSLEFT        DEFB      0
XSPTR         DEFW      0

              ORG       05200H
; Visited tab membership is independent of task activity and video validity.
; Each entry is 0 (never visited / killed) or 1 (visited).
TB_VPTR       LD        E,A
              LD        D,0
              LD        HL,TBVIS
              ADD       HL,DE
              RET
; Stage 27: removed unused code/data (Unused tab visited wrapper).
TB_VINIT      LD        HL,TBVIS
              LD        DE,TBVIS+1
              LD        BC,15
              XOR       A
              LD        (HL),A
              LDIR
              LD        A,1
              LD        (TBVIS),A
              RET
TBVIS         DEFS      16

              ORG       05300H
; Listing does not switch banks or enter the paused applications.
TB_LIST       LD        B,0
TL_NEXT       LD        A,B
              CALL      TB_VPTR
              LD        A,(HL)
              OR        A
              JR        Z,TL_SKIP                      ; slot has not been visited, or was KILLed
              PUSH      BC
              LD        A,(SCHFG)
              CP        B
              LD        E,' '
              JR        NZ,TL_MARK
              LD        E,'*'
TL_MARK       CALL      C_WRITE
              LD        A,B
              CALL      PHNYB
              LD        E,' '
              CALL      C_WRITE
              CALL      TL_DRIVE                       ; fixed-width drive/user field, 5 columns
              LD        A,B
              CALL      TB_TFL
              OR        A
              JR        NZ,TL_PROG
              LD        DE,TL_CCP
              JR        TL_NAME
TL_PROG       LD        A,B
              CALL      TBNPTR
              LD        C,8
TL_CHAR       LD        E,(HL)
              PUSH      BC
              PUSH      HL
              CALL      C_WRITE
              POP       HL
              POP       BC
              INC       HL
              DEC       C
              JR        NZ,TL_CHAR
              JR        TL_STATE
TL_NAME       CALL      C_WRITESTR
TL_STATE      LD        A,B
              CALL      TB_HPTR
              LD        A,(HL)
              OR        A
              JR        Z,TL_WAIT
              LD        DE,TL_HOLD
              JR        TL_LABEL
TL_WAIT       LD        E,B
              LD        D,0
              LD        HL,SCHWAIT
              ADD       HL,DE
              LD        A,(HL)
              OR        A
              JR        Z,TL_EOL
              LD        DE,TL_BLOCK
TL_LABEL      CALL      C_WRITESTR
TL_EOL        LD        E,13                           ; tab-list rows need CR+LF on UC1
              CALL      C_WRITE
              LD        E,10                           ; local Soroc swallows LF as before
              CALL      C_WRITE
              POP       BC
TL_SKIP       INC       B
              LD        A,(TABCOUNT)
              CP        B
              JR        NZ,TL_NEXT
              RET

; Drive for tab B. The currently executing tab has live CURDRV;
; inactive tabs have their last CURDRV (including user bits) at
; TABCTXS[tab*7 + 0]. Do NOT temporarily change TABMODE/TABPICK.
TL_DRIVE      LD        A,(TABMODE)
              CP        B
              JR        NZ,TL_DSAVE
              LD        A,(CURDRV)
              JR        TL_DCHAR
TL_DSAVE      LD        A,B
              LD        HL,TABCTXS
              LD        DE,7
TL_DLOOP      OR        A
              JR        Z,TL_DGET
              ADD       HL,DE
              DEC       A
              JR        TL_DLOOP
TL_DGET       LD        A,(HL)
; A = drive/user byte. Emit exactly FIVE columns:
;   A:___ (user 0), A1:__ (user 1..9), A15:_ (user 10..15)
; with underscores representing spaces. B holds the TAB LIST index.
TL_DCHAR      PUSH      BC
              LD        C,A                            ; preserve combined user/drive code
              AND       00FH
              ADD       A,'A'
              LD        E,A
              CALL      C_WRITE
              LD        A,C
              RRCA
              RRCA
              RRCA
              RRCA
              AND       00FH
              OR        A
              JR        Z,TL_UZERO
              CP        10
              JR        NC,TL_UTWO
              CALL      RWDECIMAL                      ; one user-number digit
              LD        B,2                            ; two spaces follow the colon
              JR        TL_COLON
TL_UTWO       CALL      RWDECIMAL                      ; two digits, user 10..15
              LD        B,1
              JR        TL_COLON
TL_UZERO      LD        B,3                            ; no user-number digits
TL_COLON      LD        E,':'
              PUSH      BC
              CALL      C_WRITE
              POP       BC
TL_DPAD       LD        E,' '
              PUSH      BC                             ; console output may affect counters
              CALL      C_WRITE
              POP       BC
              DJNZ      TL_DPAD
              POP       BC                             ; restore TAB LIST loop index
              RET




TL_CCP        DEFM      'CCP     $'                    ; 8 columns, same as .COM names

              ORG       05500H
; USER command lives in AUX CCP.COM; MAIN F_USERNUM remains in BDOS.
; Stage 27: removed unused code/data (Old resident USER handler).
; Lazy user-area directory creation. Called ONLY after a file CREATE
; returned $44 (parent pathname missing), never on ordinary opens.
; PATHBUF holds A3/FILE etc. Preserve its original Pascal length.
; ProDOS CREATE folder: filetype $0F and storage type $0D.
; Return A=0 on success or existing directory, else ProDOS error.
UD_MKDIR      LD        A,(CURDRV)
              AND       0F0H
              JP        Z,UD_MISS                      ; user zero's A/ must pre-exist
              LD        A,(PATHLEN)
              LD        (UD_OLEN),A
              LD        HL,PATH+0
              LD        B,0
UD_SLASH      LD        A,(HL)
              CP        '/'
              JR        Z,UD_FOUND
              INC       B
              INC       HL
              LD        A,B
              CP        5
              JR        C,UD_SLASH
              LD        A,044H
              RET
UD_FOUND      LD        A,B
              LD        (PATHLEN),A
              LD        A,00FH
              LD        (FMMLIT),A
              LD        A,00DH
              LD        (FMMLIS),A
              LD        HL,FMMLI
              CALL      PRODOS
              LD        (UD_STAT),A
              XOR       A
              LD        (FMMLIT),A
              INC       A
              LD        (FMMLIS),A
              LD        A,(UD_OLEN)
              LD        (PATHLEN),A
              LD        A,(UD_STAT)
              CP        047H                           ; a concurrent CREATE may have made it
              JR        Z,UD_OK
              OR        A
              RET
UD_OK         XOR       A
              RET
UD_MISS       LD        A,044H
              RET
UD_OLEN       DEFB      0
UD_STAT       DEFB      0
UC_SAVE       DEFB      0

; The S1=$A0|USER tag binds logical OPEN to its original USER area.
; S2 is application-owned, including during sequential/random record I/O.
; Returns A=0..15; preserves BC, DE, HL, IX, IY.
F2P_USER      PUSH      HL
              LD        HL,0EH
              ADD       HL,DE
              CALL      FCBVOPEN                       ; Z if S1 has our open/user tag
              JR        NZ,F2P_CUR
              DEC       HL
              LD        A,(HL)
              AND       00FH
              POP       HL
              RET
F2P_CUR       LD        A,(CURDRV)
              RRCA
              RRCA
              RRCA
              RRCA
              AND       00FH
              POP       HL
              RET

; Keep shared CLOSE compatibility constant while removing legacy CCP table.
CLOSE_TRIM_ONE EQU       1
; Stage 25: legacy MAIN CCP builtin table removed (former $5800).
              ORG       05700H
; Stage 28.4: compact command history in the safe part of each reserved
; snapshot RamWorks bank (2,5,10,15).  Each logical tab owns one $300
; slot.  Slots begin at AUX $0400, $0700, $0A00, $0D00 and end by $0FFF.
; Avoid $0000-$03FF (AUX zero page/stack and other low-memory state) and
; $B000-$BFFF (language-card window). HGR is $1000-$2FFF; SAVE uses
; $3000-$AFFF.  Each 762-byte record: head+count+10*76-char slots.
; F8/11 stores, F8/12 restores.  Uses MAIN AUXSTAGE scratch (128 bytes).
; The active CCP requests restore into a scratch record, *not* its live
; EDHEAD/EDCOUNT/EDH0..9 state. CCP validates/commits after F8 returns.
; Store path is unchanged from the successfully tested Stage 28.8.
AXHSTORE      LD        A,(VSOK)
              OR        A
              RET       Z                         ; no backing banks in single-bank system
              XOR       A
              LD        (AXHOP),A
              CALL      AXHINIT
              JP        NZ,AXBAD
              CALL      AXHCOPY
              CALL      AXHFLAG
              LD        (HL),1
              XOR       A
              LD        L,A
              RET
AXHLOAD       LD        A,(VSOK)
              OR        A
              JR        Z,AXHNONE
              CALL      AXHFLAG
              LD        A,(HL)
              OR        A
              JR        Z,AXHNONE                        ; new tab has no recorded commands
              LD        A,1
              LD        (AXHOP),A
              CALL      AXHINIT
              JP        NZ,AXBAD
              CALL      AXHCOPY
              LD        A,1                          ; an actual history image was transferred
              LD        L,A                          ; F8/12: 1=valid image, 0=no image
              RET
AXHNONE       XOR       A
              LD        L,A
              RET
; A per-tab validity flag lives in MAIN and is reset by SHINIT/SHCHECK.
AXHFLAG       LD        A,(TABMODE)
              LD        E,A
              LD        D,0
              LD        HL,HVALID
              ADD       HL,DE
              RET
AXHINIT       LD        HL,(FILEBUF)             ; caller AUX EDHEAD pointer
              LD        (AXHSRC),HL
              LD        DE,761
              ADD       HL,DE
              LD        A,H
              CP        0DEH
              JR        NC,AXHBADPTR
              LD        HL,(AXHSRC)
              LD        A,H
              OR        A
              JR        Z,AXHBADPTR
              LD        A,(TABMODE)
              AND       3
              LD        B,A
              ADD       A,A
              ADD       A,B                      ; 3 * slot index
              ADD       A,04H                     ; AUX $0400 + slot * $0300
              LD        H,A
              LD        L,0
              LD        (AXHDST),HL
              LD        A,6
              LD        (AXHCNT),A
              XOR       A
              RET
AXHBADPTR    LD        A,1
              OR        A
              RET
; Transfer 5*128 + 122 = 762 bytes per 768-byte slot.
; Switching RamWorks banks is legal only while inside the MAIN bridge.
AXHCOPY       LD        A,(AXHCNT)
              CP        1
              LD        DE,128
              JR        NZ,AXHLENOK
              LD        DE,122
AXHLENOK      LD        (AXHSTEP),DE
              LD        A,(AXHOP)
              OR        A
              JR        NZ,AXHFROMBK
              ; Store: live AUX session -> MAIN scratch -> backing bank.
              LD        A,(TABMODE)
              CALL      TABPHYS
              CALL      AXBANK
              LD        HL,(AXHSRC)
              LD        DE,AUXSTAGE
              LD        BC,(AXHSTEP)
              CALL      LCA2M
              CALL      VSSBANK
              CALL      AXBANK
              LD        HL,AUXSTAGE
              LD        DE,(AXHDST)
              LD        BC,(AXHSTEP)
              CALL      AXM2A
              JR        AXHADV
AXHFROMBK     CALL      VSSBANK
              CALL      AXBANK
              ; History restore reads from a RESERVED RamWorks bank.
              ; Unlike a live transient bank, it has no LC copy gateway
              ; at LCA2MR. LCA2M would otherwise jump into arbitrary
              ; memory in that bank and crash the running machine.
              ; Install only the self-contained LIA2M routine into this
              ; bank's AUX LC before attempting the read. AXM2A runs
              ; from MAIN and therefore needs no AUX executable shim.
              LD        HL,LIA2M
              LD        DE,LCA2MR
              LD        BC,LINOP-LIA2M
              CALL      AXM2A
              LD        HL,(AXHDST)
              LD        DE,AUXSTAGE
              LD        BC,(AXHSTEP)
              CALL      LCA2M
              LD        A,(TABMODE)
              CALL      TABPHYS
              CALL      AXBANK
              LD        HL,AUXSTAGE
              LD        DE,(AXHSRC)
              LD        BC,(AXHSTEP)
              CALL      AXM2A
AXHADV        LD        DE,(AXHSTEP)
              LD        HL,(AXHSRC)
              ADD       HL,DE
              LD        (AXHSRC),HL
              LD        HL,(AXHDST)
              ADD       HL,DE
              LD        (AXHDST),HL
              LD        A,(AXHCNT)
              DEC       A
              LD        (AXHCNT),A
              JP        NZ,AXHCOPY
              LD        A,(TABMODE)
              CALL      TABPHYS
              CALL      AXBANK                   ; restore live bank, not screen bank
              RET
AXHOP         DEFB      0
AXHCNT        DEFB      0
AXHSTEP       DEFW      0
AXHSRC        DEFW      0
AXHDST        DEFW      0

; Stage 28.6: the CCP editor polls BDOS 6 instead of BDOS 10,
; so it never enters the existing kernel cursor-on path.  Interpose
; TSKKEY and physical CUON/CUOFF without changing BDOS 6's footprint.
; Carry remains set only when TSKKEY queued an OA tab switch.
AB6CUR        CALL      TSKKEY
              JR        C,AB6CURSW
              OR        A
              JR        NZ,AB6CURKEY
              LD        A,(CUACTIVE)
              OR        A
              JR        NZ,AB6CURZERO                ; already drawn
              CALL      SHISCCP                       ; only foreground CCP gets cursor
              JR        NZ,AB6CURZERO
              CALL      CUON
              CALL      AB6BANKREST                   ; cursor maps physical bank 0
AB6CURZERO    XOR       A
              LD        L,A
              RET
AB6CURKEY     PUSH      AF
              CALL      CUOFF                         ; hide before editor changes text
              CALL      AB6BANKREST                   ; return to active AUX bank
              POP       AF
              LD        L,A
              OR        A                             ; no OA switch: clear carry
              RET
AB6CURSW      CALL      CUOFF                         ; hide before queued tab switch
              CALL      AB6BANKREST
              SCF                                     ; preserve deferred switch signal
              RET
AB6BANKREST   LD        A,(TABMODE)
              CALL      TABPHYS
              JP        AXBANK

; Stage 28.8: keep C_SENDA's original instruction footprint.
; This out-of-line helper hides the CCP cursor before *any* output,
; preserving the Stage 28.7 fix without enlarging packed BDOS code.
CSOUTPRE      LD        A,(CUACTIVE)
              OR        A
              JR        Z,CSOUTEND
              PUSH      DE
              CALL      CUOFF
              CALL      AB6BANKREST
              POP       DE
CSOUTEND      JP        CFO_CHECK

              ORG       05900H
AXF7F8        CP        0F7H
              JP        Z,AXEXEC
              CP        0F8H
              JP        Z,AXBUILT
              JP        AXBAD
AXBUILT       PUSH      DE
              CALL      SHPTR
              LD        A,(HL)
              POP       DE
              CP        1
              JP        NZ,AXBAD                       ; shell only
              LD        A,D
              OR        A
              JP        Z,AXBAD                        ; invalid AUX address
              LD        (AXBPTR),DE                     ; F8/9 also reads 36-byte FCB
              LD        HL,80
              ADD       HL,DE
              LD        A,H
              CP        0DEH
              JP        NC,AXBAD                       ; record must fit AUX TPA
              LD        H,D
              LD        L,E
              LD        DE,AXBID
              LD        BC,1
              CALL      LCA2M                          ; fetch command ID
              LD        DE,FILEBUF
              LD        BC,80
              CALL      LCA2M                          ; fetch length + normalized args
              LD        A,(AXBID)
              CP        1
              JP        Z,AXBCLS
              CP        2
              JP        Z,AXBBANKS
              CP        3
              JP        Z,CCPCACHE
              CP        4
              JP        Z,CCPTERM
              CP        5
              JP        Z,AXBTAB
              CP        6
              JP        Z,AXBXSUB
              CP        7
              JP        Z,AXBBYE
              CP        8
              JP        Z,AXBSESSION                  ; read active logical TABMODE for AUX prompt
              CP        9
              JP        Z,AXBSAVE                     ; native SAVE with preserved transient
              JP        AXBEXTRA                     ; private SUBMIT fetch or unknown ID
; Pure query: no scheduler mutation, no terminal switch, no AUX pointers.
; AXGATE returns both A and HL to the transient caller.
AXBSESSION    LD        A,(TABMODE)
              LD        L,A
              RET
AXBCLS        CALL      AXBNONE
              RET       NZ
              JP        NCLS_RUN                       ; user CLS goes to selected terminal
AXBBANKS      CALL      AXBNONE
              RET       NZ
              JP        CCPBANKS
AXBXSUB       CALL      AXBNONE
              RET       NZ
              JP        CCPXSUB
AXBBYE        CALL      AXBNONE
              RET       NZ
              JP        CCPBYE
AXBNONE       LD        A,(FILEBUF)
              OR        A
              RET       Z
              JP        CCPBAD
; Stage 21: native parser may inspect/edit tab bookkeeping during F8.
; A display/context switch itself is deferred by TB_SWGATE, after
; AXGATE has captured the full AUX CCP register+stack image.
AXBTAB        JP        TBCMD
AXBID         DEFB      0
AXBPTR       DEFW      0

; Intercept TB_SWITCH (from either TAB n or TAB n EXCLUSIVE).
; MAIN services use this helper directly; no resident CCP parser remains.
; From AUX, never perform bank/display switching inside AXGATE.
TB_SWGATE     LD        A,(AXMODE)
              OR        A
              JR        NZ,TB_SWDEFER
              CALL      CUOFF
              JP        TB_SWCONT
TB_SWDEFER    LD        A,(SCHFG)
              CP        B
              JP        Z,UNIMP                         ; current-tab request just beeps
              LD        A,(TABREQ)
              CP        0FFH
              JP        NZ,CCPBAD                       ; don't overwrite pending OA request
              LD        A,B
              LD        (TABREQ),A
              LD        A,3
              LD        (AXQUIT),A                      ; TASKSAVE at AXGATE, then TBAUTOSW
              RET

; Never KILL the visible/current tab: AUX CCP is still executing in
; that bank, so erasing its TSKFLAGS/SHFLAGS would orphan the stack.
TB_SAFE_KILL  LD        A,(SCHFG)
              CP        B
              JP        Z,TB_NOBG
              LD        A,(TABMODE)
              CP        B
              JP        Z,TB_NOBG
              JP        TB_KILL

              ORG       05A00H
; DE points at an S1-tagged CP/M FCB. Return A=0 on success / skip,
; nonzero on failed read/truncate. Application S2 and CR restored.
; On a successful trim, caller closes the cached ProDOS handle.
FC5TRIM       LD        A,CLOSE_TRIM_ONE
              OR        A
              RET       Z                             ; safe default, no implicit shrink
              PUSH      DE
              POP       IX
              LD        A,(IX+0EH)
              BIT       7,A                           ; CP/M S2 modification flag
              JR        Z,FC5DIRTY
              XOR       A
              RET                                     ; unchanged FCB, normal CLOSE
FC5DIRTY
              LD        A,(IX+0FH)
              CP        080H
              JP        NC,FC5SKIP                    ; RC 128/invalid: never trim
              CALL      IO_BEGIN                      ; obtain physical FRN in S2
              OR        A
              RET       NZ                            ; can't reopen; caller reports failure
              LD        A,(IX+0EH)
              LD        (GEMLIN),A
              LD        HL,GEMLI
              CALL      PRODOS                        ; exact physical ProDOS byte EOF
              OR        A
              JP        NZ,FC5DONE                    ; preserve error, restore S2
              ; Do not lose any partial final record: an RC-based shrink
              ; is only unambiguous when the existing EOF is 128-aligned.
              LD        A,(GEMLIE1)
              AND       07FH
              JP        NZ,FC5SKIP
              LD        A,(IX+20H)
              PUSH      AF                            ; application CR
              LD        A,(IX+0FH)
              LD        (IX+20H),A                     ; proposed next sequential rec
              CALL      SEQMARK                       ; mark = (EX,S2,RC) * 128
              LD        B,0                            ; preserve carry across CR restore
              JR        NC,FC5POSOK
              INC       B
FC5POSOK      POP       AF
              LD        (IX+20H),A                     ; don't modify caller CR
              LD        A,B
              OR        A
              JP        NZ,FC5SKIP                    ; >16MiB / invalid extent
              ; Prove that candidate EOF is exactly ONE 128-byte record
              ; below the real EOF. This also rules out earlier extents.
              LD        HL,(SMMLIP1)
              LD        BC,0080H
              ADD       HL,BC
              LD        A,(SMMLIP3)
              ADC       A,0
              JP        C,FC5SKIP
              LD        DE,(GEMLIE1)
              OR        A
              SBC       HL,DE
              JP        NZ,FC5SKIP
              LD        B,A
              LD        A,(GEMLIE3)
              CP        B
              JP        NZ,FC5SKIP
              ; A byte-precise ProDOS SET_EOF is now justified.
              LD        A,(IX+0EH)
              LD        (SEMLIN),A
              LD        HL,(SMMLIP1)
              LD        (SEMLIE1),HL
              LD        A,(SMMLIP3)
              LD        (SEMLIE3),A
              LD        HL,SEMLI
              CALL      PRODOS                        ; trim exactly one record
              OR        A
              JP        NZ,FC5DONE                    ; never mark failed trim clean
              ; CLOSE committed the explicit metadata adjustment.  Mark
              ; the *saved* CP/M S2 clean so a second CLOSE cannot apply
              ; the same shortening request again.  Do not touch S1.
              LD        A,(IOVS2)
              OR        080H
              LD        (IOVS2),A
              XOR       A
              JP        FC5DONE
FC5SKIP       XOR       A                             ; leave EOF untouched
FC5DONE       JP        IO_END                        ; restores app S2, sets L=result

              ORG       05C00H
; Stage 25: AUX CCP supervisor. All tabs start A:CCP.COM.
; No MAIN resident command interpreter. Missing CCP uses a minimal
; R=retry/B=ProDOS recovery monitor (not an infinite launch loop).
; SHFLAGS: 0 = no AUX shell/recovery, 1 = AUX CCP.COM, 2 = child .COM.
; A request is a BDOS $F7 call with DE -> 36-byte AUX FCB (COM extension).
; No direct AUX->AUX replacement occurs; old transient exits AXGATE first.
SHFLAGS       DEFS      16
HVALID        DEFS      16        ; ten-command history valid, indexed by TABMODE
; This is an out-of-line replacement for TSKINIT's original first
; instruction (LD HL,SCHWAIT, three bytes).  The jump occupies exactly
; the same three bytes in the crowded $0800-$0AFF region.
SHINIT        LD        HL,SHFLAGS
              LD        DE,SHFLAGS+1
              LD        BC,15
              XOR       A
              LD        (HL),A
              LDIR
              LD        HL,HVALID
              LD        DE,HVALID+1
              LD        BC,15
              XOR       A
              LD        (HL),A
              LDIR
              LD        HL,SCHWAIT
              JP        TSKINI2
SHPTR         LD        A,(TABMODE)
              LD        E,A
              LD        D,0
              LD        HL,SHFLAGS
              ADD       HL,DE
              RET

; Mark a launched CCP.COM as the supervisor-owned shell.
; A drive selection and any arguments don't affect the test.
SHCHECK       LD        HL,PATHBUF2+1
              LD        DE,SHNAME
              LD        B,11
SHCMP         LD        A,(DE)
              CP        (HL)
              RET       NZ
              INC       DE
              INC       HL
              DJNZ      SHCMP
              CALL      SHPTR
              LD        (HL),1
              ; Do NOT reset HVALID on every CCP.COM reload: a running child
              ; has just exited and its history must survive the re-load.
              ; SHINIT / SHNEW reset it on boot or genuinely new sessions.
              CALL      SVSFPTR                         ; fresh CCP, no completed child
              LD        (HL),0
              RET
SHNAME        DEFM      'CCP     COM'
SHFCB         DEFB      1                             ; always reload from drive A:
              DEFM      'CCP     COM'
              DEFS      24

; Called with MAIN stack, either after original AUXRUN or TABRESUM.
; On suspended status (AXQUIT=3) leave parked task untouched.
SHSTEP        JP        NCSHSTEP                       ; 6G.3: inspect hangup before reload
SHLOOP        CALL      SHPTR
              LD        A,(HL)
              OR        A
              RET       Z
              CP        2
              JR        Z,SHCHILD
              ; shell itself just returned (EXIT), or requested new .COM
              LD        A,(AXQUIT)
              CP        4
              JR        Z,SHLAUNCH
              ; Shell RET, BDOS 0 or failed load => recovery supervisor.
SHSTOP        XOR       A
              LD        (HL),A
              LD        A,(TABMODE)
              LD        B,A
              CALL      NCSTOP                         ; remote shell EXIT restores local console
              RET
SHLAUNCH      LD        (HL),2                     ; mark child before switching programs
              CALL      SHSUBRUN                   ; rearm SUBMIT on a fresh SUBMIT.COM launch
              LD        A,(AXQUIT)
              CP        3
              RET       Z                           ; child's bank saved by existing scheduler
              JP        SHLOOP                     ; child ended -> reload shell
SHCHILD       LD        A,(TABMODE)
              LD        B,A
              CALL      NETCLN                         ; child exited, release sockets
              CALL      SBWCLR                    ; child warm boot returns to file-loaded CCP
              CALL      SVSSNAP                       ; preserve child low 8K BEFORE CCP reload
              ; Clear page-zero FCBs/tail FIRST, before building the
              ; executable FCB.  Never allow the stale child launch record
              ; to serve as the shell reload target.
              CALL      SHNOARG
              ; Reconstruct reload FCB in-place; do not depend on its
              ; previous contents or the just-completed child FCB.
              LD        HL,PATHBUF2
              LD        B,36
              XOR       A
SHRZERO       LD        (HL),A
              INC       HL
              DJNZ      SHRZERO
              LD        A,1                            ; A:CCP.COM, independent of current drive
              LD        (PATHBUF2),A
              LD        HL,SHNAME
              LD        DE,PATHBUF2+1
              LD        BC,11
              LDIR
              ; Known-good Stage 18 launch record; no diagnostic console I/O.
              CALL      SHPTR
              LD        (HL),1
              CALL      AUXRUN
              LD        A,(AXQUIT)
              CP        3
              RET       Z                           ; shell suspended normally
              JP        SHLOOP
; Clear MAIN default FCBs and command tail before reloading/booting CCP.
; Application arguments travel through AXEXEC/F7, not through this helper.
SHNOARG       LD        HL,FCB1
              LD        (DMAADDR),HL
              CALL      CLRFCB
              LD        HL,FCB2
              LD        (DMAADDR),HL
              CALL      CLRFCB
              XOR       A
              LD        (FILEBUF),A
              LD        (FILEBUF+1),A
              LD        HL,FILEBUF
              LD        (DMAADDR),HL
              RET

; Stage 13 private BDOS $F7 shell->child handoff.
; AUX DE points to a *contiguous* 196-byte launch record:
; [0..35] launch FCB, [36..51] default FCB1, [52..67] default FCB2,
; [68..195] CP/M command tail including length byte and trailing CR.
; This copy must complete before AXGATE replaces the AUX image.
AXEXEC        PUSH      DE                            ; SHPTR uses DE as tab index
              CALL      SHPTR
              LD        A,(HL)
              POP       DE
              CP        1
              JP        NZ,AXBAD                       ; only CCP may request a chain
              CALL      AXCKFCB                        ; minimum 36-byte FCB bound
              JP        NZ,AXBAD
              LD        HL,195                          ; validate end of full parameter block
              ADD       HL,DE
              LD        A,H
              CP        0DEH                           ; all input below AUX BDOS at DE00
              JP        NC,AXBAD
              LD        H,D                            ; AUX source pointer
              LD        L,E
              LD        DE,PATHBUF2                    ; MAIN executable FCB
              LD        BC,36
              CALL      LCA2M                          ; HL advances, DE advances
              LD        A,(PATHBUF2+1)
              CP        ' '
              JP        Z,AXBAD
              LD        DE,FCB1                        ; MAIN default FCB1 005Ch
              LD        BC,16
              CALL      LCA2M
              LD        DE,FCB2                        ; MAIN default FCB2 006Ch
              LD        BC,16
              CALL      LCA2M
              LD        DE,FILEBUF                     ; MAIN command tail 0080h
              LD        BC,128
              CALL      LCA2M
              LD        HL,FILEBUF
              LD        (DMAADDR),HL
              LD        A,4
              LD        (AXQUIT),A                     ; AXGATE returns to MAIN, then SHSTEP
              XOR       A
              LD        L,A
              RET

; TABRESUM lives in the $0800-$0AFF fixed block, with no spare bytes.
; One CALL here replaces the two CALLs there, preserving its exact size.
SHAFTER       CALL      SHSTEP
              JP        SBWSET                       ; tail call: returns to TABRESUM

; AUXRUN used to restore the drive saved before AXSTART, even when the
; AUX CCP had selected another drive before issuing BDOS F7.  That made
; implicit executable names (FCB drive=0) open on the original drive.
; Keep the live drive/user state on cooperative suspension (AXQUIT=3)
; as well as on CCP program chaining (AXQUIT=4). Otherwise a CCP that
; started on A: but switched to B: reverts to A: when parked, breaking
; a running TYPE and later commands using the current drive.
; Preserve AUXRUN's previous restore behavior on actual exit paths.
; Called with the pre-AXSTART CURDRV byte in A, after POP AF; preserve AF.
SHDRKEEP      PUSH      AF
              LD        A,(AXQUIT)
              CP        3
              JR        NC,SHDRSKP                  ; suspension or chaining: keep CURDRV
              POP       AF
              LD        (CURDRV),A
              RET
SHDRSKP       POP       AF
              RET

; Stage 23.1: this helper formerly lived inline at AUXFOUND ($7C00).
; The $7C00-$7EBF region has only 5 free bytes in Stage 22.2.
; Keep the original decision while relocating it to verified spare MAIN RAM.
              ORG       05E80H
SVNEWCHILD    CALL      SHPTR
              LD        A,(HL)
              CP        1                              ; SHFLAGS=1: automatic CCP reload
              RET       Z                              ; keep previous transient snapshot
              CALL      SVSFPTR
              LD        (HL),0                          ; new child invalidates old low TPA
              CALL      SVFLPTR
              LD        (HL),0                          ; and its high-memory SAVE image
              RET

; The regular TAB switch occupies a fixed MAIN memory region. Replace
; its original visited-mark call with this same-sized CALL. SHFLAGS=3
; is a short-lived sentinel for a never-used or KILLed tab, not a shell
; state: TB_BOOTIFNEW consumes it after the video and scheduler are ready.
TB_VISMARK    LD        A,(TABMODE)
              CALL      TB_VPTR
              LD        A,(HL)
              OR        A
              RET       NZ                             ; revisiting: don't restart CCP
              LD        (HL),1                         ; now visited (TAB LIST membership)
              XOR       A
              LD        (CURDRV),A                     ; KILLed slot restarts in A:/USER 0
              CALL      SHPTR
              LD        (HL),3                         ; defer initial CCP launch
              RET

TB_BOOTIFNEW  CALL      SHPTR
              LD        A,(HL)
              CP        3
              JP        NZ,TABRESUM                   ; existing tab: resume as before
              CALL      SHNEW                         ; runs until yield/EXIT; no auto-resume
              RET                                      ; avoid reentering suspended CCP

; WBOOT vectors and DMA are initialized before entering here.
; A user WBOOT intentionally reloads CCP (no resident interpreter exists).
SHBOOTREPORT  JP        RWREPORT                       ; cold-boot report (3-byte call site)
SHBOOTENTRY   CALL      SHNEW
              JP        CCP                           ; permanent MAIN supervisor/recovery loop

; Stage 27.1: Ctrl-C is a *line cancel*, not a CCP.COM termination.
; Distinguish shell (SHFLAGS=1) from transient child (SHFLAGS=2).
; Both keyboard handlers live here to avoid growing fixed $0800 and
; $7000-$758F regions.  This $5E80-$5EFF region has 128 bytes total.
SHISCCP       PUSH      HL
              PUSH      DE
              CALL      SHPTR
              LD        A,(HL)
              POP       DE
              POP       HL
              CP        1
              RET
AXCCANCEL     CALL      SHISCCP
              JR        NZ,TSKCCKILL                   ; ordinary programs retain ^C abort
              LD        E,'^'
              CALL      C_WRITE
              LD        E,'C'
              CALL      C_WRITE
              LD        HL,AXLBUF+2
              LD        C,0                            ; discard partial command line
              JP        AXLDONE                        ; return empty BDOS 10 buffer
TSKCCANCEL    CALL      SHISCCP
              JR        NZ,TSKCCKILL
              LD        E,'^'
              CALL      C_WRITE
              LD        E,'C'
              CALL      C_WRITE
              LD        E,13                           ; finish the cancelled prompt line
              CALL      C_WRITE
              LD        A,'N'                          ; decline ERA/BYE confirmation
              LD        L,A
              RET
TSKCCKILL     LD        A,1                            ; normal CP/M warm boot for child
              LD        (LCQUIT),A
              XOR       A
              LD        L,A
              RET

              ORG       05F00H
; CP/M 2.2 permits programs to read/write IOBYTE at 0003h directly.
; Each AUX transient has a private 0003h; resident BIOS uses MAIN 0003h.
; Synchronize AUX -> MAIN at every syscall and at ordinary .COM exit.
; Do not modify caller register arguments, return registers or flags.
AXIOSBD       CALL      AXIOSYN
              JP        AUXBDOS                        ; tail-call: return to AXGATE
AXIOSYN       PUSH      AF
              PUSH      HL
              LD        HL,IOBYTE
              CALL      LCPEEK                         ; reads one byte from active AUX bank
              LD        (IOBYTE),A
              POP       HL
              POP       AF
              RET
; AXFIN may be entered directly from AUX LC with the application's SP.
; Restore the MAIN stack BEFORE calling the synchronizer.
AXIOSFX       LD        SP,(AXMSP)
              CALL      AXIOSYN
              XOR       A
              LD        (ZPMAIN),A
              LD        A,(LCB1RO)
              XOR       A
              LD        (AXMODE),A
              RET

; Bind the AUX BDOS SEARCH FIRST enumeration to the USER active when
; it starts, just as S8MSF already does for MAIN CCP searches.
; S8SAVE snapshots S8USER and S8REST uses it to reopen the directory
; on SEARCH NEXT. Without this, AUX DIR/PIP may switch to a stale USER
; (typically 0) after returning the first result for USER 3, etc.
; This replaces LD A,(LCB1RO) with an equal-sized CALL at AXSFIRST,
; keeping fixed-location AUX dispatch code completely unchanged in size.
S8AUXBIND     LD        A,(CURDRV)
              AND       0F0H
              LD        (S8USER),A
              LD        A,(LCB1RO)                     ; preserve original LC bank switch
              RET

; First visit to a tab: launch A:CCP.COM using the same FCB/loader
; path as the proven Stage 18 shell reload, with no command arguments.
; No transient is active yet, and the new tab is already foreground.
; If CCP.COM is missing, SHSTEP clears SHFLAGS and MAIN enters its
; minimal retry/BYE recovery monitor. Later TAB visits must not retry.
; Reuses the space formerly occupied by the disabled Stage 18 trace.
              ORG       05F60H
SHNEW         CALL      SHNOARG
              CALL      AXHFLAG
              LD        (HL),0                          ; genuinely new shell gets empty history
              LD        HL,PATHBUF2
              LD        B,36
              XOR       A
SHNZERO       LD        (HL),A
              INC       HL
              DJNZ      SHNZERO
              LD        A,1                            ; explicit drive A regardless of CURDRV
              LD        (PATHBUF2),A
              LD        HL,SHNAME
              LD        DE,PATHBUF2+1
              LD        BC,11
              LDIR
              CALL      SHCHECK                       ; mark as shell, reset SAVE validity
              CALL      AUXRUN
              JP        SHSTEP                        ; handle child chain or shell termination

; Relocated resident routines: ample MAIN memory, separate from AUX TPA.
; Stage 20/6G: cheap physical OA hotkey probe at syscall-return and
; main scheduler idle-loop boundaries.  The keyboard latch $C000 and
; OA switch $C061 are memory-mapped; the no-key path never enters
; 6502 firmware.  The physical keyboard remains available for tab
; switching even when the foreground session uses UC1 (Telnet).
; Never consume ordinary keys, Ctrl-C, or invalid OA combinations.
; TSKKEY's existing decoder handles 0..9, A..F, and both arrows.
; Preserve BC/HL, and restore the 6502 XREG scratch byte even when
; the decoded key queues a switch or beeps for the current tab.
              ORG       05FA0H
NC_HOT        CALL      SCHHOT                         ; SCHHOT preserves keyboard ordinary input
              LD        A,(TABREQ)                     ; original SMLOOP contract
              RET
SCHHOT        LD        A,(0E000H)                     ; $C000: common fast path
              BIT       7,A
              RET       Z                              ; one memory lookup; no key
              PUSH      BC
              LD        B,A                            ; retain key; don't clear strobe
              LD        A,(0E061H)                     ; Apple II $C061 OA keydown
              BIT       7,A
              JR        Z,SHNOTOA                      ; ordinary key is untouched
              CALL      SCHISFG
              JR        NZ,SHNOTOA                     ; background must not take input
              ; The physical OA hotkey is independent of IOBYTE:
              ; a remote UC1 tab must not disable console tab changes.
              LD        A,(TABREQ)
              CP        0FFH
              JR        NZ,SHNOTOA                     ; switch already queued
              PUSH      HL
              LD        A,(XREG)                       ; TSKKEY checks 6502 XREG bit 7
              LD        C,A                            ; preserve original XREG in C
              LD        A,080H                         ; synthesize sampled OA bit
              LD        (XREG),A
              LD        A,B
              AND       07FH                           ; ASCII + arrows as usual
              CALL      TSKKEY                         ; preserves caller's BC
              PUSH      AF                             ; preserve queued-switch carry
              LD        A,C
              LD        (XREG),A                        ; restore 6502 scratch register
              POP       AF
              POP       HL
              POP       BC
              RET       NC                             ; not a switch; leave ordinary key
              LD        A,(0E010H)                     ; valid OA switch: consume strobe
              RET
SHNOTOA       POP       BC
              RET

; Stage 26.1 SUBMIT restart guard.  The legacy resident CCP cleared
; SBHALT through BDOSWARM, but the AUX supervisor directly reloads CCP
; after each transient, bypassing BDOSWARM.  If a prior SUBMIT reader
; encountered an invalid or zero-length $$$.SUB and latched SBHALT,
; a later SUBMIT.COM can create a new $$$.SUB that is never examined.
;
; Only rearm when the CCP is about to launch a fresh SUBMIT.COM.
; This does NOT repeatedly retry a bad $$$.SUB at each CCP prompt.
; Diagnostic message prints ONLY if an old SBHALT latch was found.
; Same stack/return behaviour as original CALL AUXRUN in SHLAUNCH.
              ORG       06000H
SHSUBRUN      LD        HL,PATHBUF2+1
              LD        DE,SHSUBNAME
              LD        B,11
SHSUBCMP      LD        A,(DE)
              CP        (HL)
              JR        NZ,SHSUBGO
              INC       HL
              INC       DE
              DJNZ      SHSUBCMP
              ; Fresh SUBMIT.COM starts a new submission lifecycle.
              ; Don't let an earlier XSUB stream steal its console input
              ; or contaminate subsequent normal SUBMIT scripts.
              XOR       A
              LD        (XSFLAG),A
              LD        (XSLEFT),A
              LD        (SBFROM),A
              LD        A,(SBHALT)
              OR        A
              JR        Z,SHSUBGO
              LD        DE,SHSUBMSG
              CALL      C_WRITESTR
              XOR       A
              LD        (SBHALT),A
SHSUBGO       JP        AUXRUN
SHSUBNAME     DEFM      'SUBMIT  COM'
SHSUBMSG      DEFM      'SUBMIT: stale reader latch cleared'
              DEFB      13,'$'

; Stage 25: legacy CCP HELP removed (old $6000 block).
              ORG       06100H
; The S1 magic high nibble is the SOLE logical-open test. An application
; may change S2 (extent + CP/M flags), so we must never classify it via S2.
; In: HL=FCB+0EH. Out: Z if S1=$A0..$AF. Preserve HL and all except A/flags.
FCBVOPEN      DEC       HL
              LD        A,(HL)
              INC       HL
              AND       0F0H
              CP        0A0H
              RET

; Raw ProDOS FRNs in S2 are allowed ONLY in our internal directory FCB
; and transient loader FCB. AUX application FCBs are staged at AXFCB;
; their nonzero S2 can never be mistaken for a physical ProDOS handle.
; In: DE=FCB start. Out: Z for internal raw FCB; preserve all regs.
FCBRAW        PUSH      HL
              LD        HL,DFCB
              OR        A                              ; clear carry for 16-bit compare
              SBC       HL,DE
              JR        Z,FRAW_END
              LD        HL,PATHBUF2
              OR        A
              SBC       HL,DE
FRAW_END      POP       HL
              RET

; For logical CP/M I/O, briefly loan S2 to ProDOS as the physical FRN.
; IO_END restores the application's exact S2 byte, even after I/O errors.
IO_BEGIN      XOR       A
              LD        (IOVIRT),A
              PUSH      HL
              PUSH      DE
              PUSH      IX
              POP       HL
              LD        DE,0EH
              ADD       HL,DE
              CALL      FCBVOPEN                       ; classify without changing IX/BC
              POP       DE
              POP       HL
              JR        Z,IO_CACHE
              PUSH      DE
              PUSH      IX
              POP       DE
              CALL      FCBRAW                         ; no raw FRNs in application FCBs
              POP       DE
              JR        NZ,IO_BAD
              LD        A,(IX+0EH)
              OR        A
              JR        NZ,IO_PHYS
              JR        IO_BAD                         ; internal raw FCB not opened
IO_PHYS       XOR       A
              RET
IO_BAD        LD        A,9
              RET
IO_CACHE      LD        A,(IX+0EH)
              LD        (IOVS2),A                       ; preserve caller's S2
              LD        A,1
              LD        (IOVIRT),A
              PUSH      IX
              PUSH      IX
              POP       DE
              LD        IX,PATHBUF
              CALL      FCB2PATH
              CALL      CACHEFND
              POP       IX
              OR        A
              JR        Z,IO_REOPEN
              LD        (CMRU),A                       ; LRU bookkeeping on cache hit
              PUSH      AF
              LD        HL,CHITS
              CALL      CINC16
              POP       AF
              CALL      CACHEREF
              LD        (IX+0EH),A
              XOR       A
              RET
IO_REOPEN                   ; Miss: keep the caller's extent/RC/CR across _F_OPEN.
              PUSH      IX
              POP       DE
              LD        A,(IX+0FH)
              PUSH      AF
              LD        A,(IX+0CH)
              PUSH      AF
              LD        A,(IX+20H)
              PUSH      AF
              PUSH      DE
              PUSH      IX
              CALL      _F_OPEN
              LD        C,A
              POP       IX
              POP       DE
              POP       AF
              LD        (IX+20H),A
              POP       AF
              LD        (IX+0CH),A
              POP       AF
              LD        (IX+0FH),A
              LD        A,C
              OR        A
              JR        NZ,IO_FAIL
              LD        A,(IX+0EH)
              CALL      GETIOADDR
              CALL      CACHEPUT
              XOR       A
              RET
IO_FAIL       LD        A,(IOVS2)
              LD        (IX+0EH),A                     ; _F_OPEN may have touched S2
              XOR       A
              LD        (IOVIRT),A
              LD        A,C
              RET

; Preserve BDOS status, leave the physical ProDOS handle in the cache.
IO_END        PUSH      AF
              LD        A,(IOVIRT)
              OR        A
              JR        Z,IO_DONE
              LD        A,(IOVS2)
              LD        (IX+0EH),A                     ; CP/M sees original S2
IO_DONE       POP       AF
              LD        L,A
              RET
IOVIRT        DEFB      0
IOVS2         DEFB      0                              ; saved app extent S2 per BDOS call
FOS2          DEFB      0                              ; saved S2 across fresh F_OPEN

; Increment wrapping 16-bit counter at HL. No file handles are touched.
CINC16        INC       (HL)
              RET       NZ
              INC       HL
              INC       (HL)
              RET
; Reset counters only on cold start or via the explicit CACHE RESET.
CACHERST      LD        HL,0
              LD        (COPENS),HL
              LD        (CHITS),HL
              LD        (CEVICTS),HL
              RET
COPENS        DEFW      0
CHITS         DEFW      0
CEVICTS       DEFW      0

; Prepare a ProDOS sequential write at SMMLIP1..3.  ProDOS prohibits
; SET_MARK beyond EOF, whereas CP/M accepts skipped/unwritten records.
; On a gap, SET_EOF makes a sparse extension, as F_WRITERAND already does.
; IX points to the physical-ref FCB. Returns A=0 or ProDOS error.
SEQEXTEND     LD        A,(IX+0EH)
              LD        (GEMLIN),A
              LD        (SEMLIN),A
              LD        HL,GEMLI
              CALL      PRODOS                         ; GET_EOF
              OR        A
              RET       NZ
              LD        A,(GEMLIE1)
              LD        HL,SMMLIP1
              SUB       (HL)
              INC       HL
              LD        A,(GEMLIE2)
              SBC       A,(HL)
              INC       HL
              LD        A,(GEMLIE3)
              SBC       A,(HL)
              JR        NC,SEQX_OK                     ; EOF >= requested mark
              LD        HL,(SMMLIP1)
              LD        (SEMLIE1),HL
              LD        A,(SMMLIP3)
              LD        (SEMLIE3),A
              LD        HL,SEMLI
              CALL      PRODOS                         ; SET_EOF, return ProDOS status
              RET
SEQX_OK       XOR       A
              RET

; BDOS 21 successful sequential-write FCB bookkeeping.
; In: IX points to the CP/M FCB; CR must be 0..127.
; Increase RC to include the written record, but never shorten an
; existing extent on an overwrite.  Advance CR just as before.
; At CR=127 the next extent is selected with CR=0 and RC=0; that
; new extent's correct existing length still needs the future
; extent-aware OPEN/rollover update for overwriting large files.
; Changes A, B and flags only, apart from FCB EX/RC/CR.
RCSEQWRITE    LD        A,(IX+20H)                     ; CR of record just written
              INC       A                              ; number of records now used: 1..128
              LD        B,A
              LD        A,(IX+0FH)                     ; current extent RC
              CP        B
              JR        NC,RCSEQ_NEXT                  ; overwrote an existing record
              LD        A,B
              LD        (IX+0FH),A                     ; extend RC, maximum 128
RCSEQ_NEXT    LD        A,B
              CP        080H
              JR        Z,RCSEQ_ROLL
              LD        (IX+20H),A                     ; next CR
              RET
RCSEQ_ROLL    XOR       A
              LD        (IX+20H),A                     ; next extent's first record
              CALL      EXROLL                         ; wrap low 5 EX bits, carry S2
              JP        RCNEXT                         ; existing next extent may be nonempty

; Apply exact RC after a fresh CP/M OPEN (not internal raw _F_OPEN).
; FOS2 preserves the caller's S2; _F_OPEN temporarily stores a ProDOS FRN.
RCFRESHOPEN   PUSH      IY
              POP       IX
              LD        A,(FOS2)
              CALL      RCEOFRC
              LD        (IY+0FH),A
              RET

; A successful random WRITE must update RC for the target extent.
; On a post-write GET_EOF failure, leave RC alone, report the already
; successful write, and do not provoke a retry/duplicate write.
RCRANDWRITE   LD        A,(IOVIRT)
              OR        A
              RET       Z                              ; skip internal raw FRN files
              LD        A,(IX+0EH)                     ; temporary physical FRN
              LD        (GEMLIN),A
              LD        HL,GEMLI
              CALL      PRODOS                         ; new EOF after successful WRITE
              OR        A
              RET       NZ                             ; leave RC unchanged on failure
              LD        A,(IOVS2)                      ; now updated by RANDEXT
              CALL      RCEOFRC
              LD        (IX+0FH),A
              RET

; Stage 2: RC from ProDOS's exact 24-bit EOF, for the selected extent.
; In: IX=application FCB, A=application S2 (not temporary ProDOS FRN).
;     GEMLIE1..3 = exact ProDOS byte EOF from successful GET_EOF.
; Out: A=0..128, the number of records present in EX/S2's extent.
; EX bits 0..4 and S2 bits 0..5 form the logical extent number; S2 bit 7
; is a CP/M flag and must not contribute to the extent address.
; Calls may change A, BC, DE, HL, flags. IX and IY are preserved.
; Use ceil(EOF/128) minus (extent * 128), then clamp to [0,128].
; A 24-bit difference permits the full ProDOS 16-MiB range without wrap.
RCEOFRC       PUSH      AF                             ; S2, before EOF conversion
              LD        A,(GEMLIE1)
              AND       07FH
              LD        E,A                            ; nonzero fractional record?
              LD        HL,(GEMLIE1)
              LD        A,(GEMLIE3)
              LD        B,7
RCE_SHIFT     SRL       A                              ; A:HL = EOF >> 7
              RR        H
              RR        L
              DJNZ      RCE_SHIFT
              LD        C,A                            ; C:HL = floor(EOF/128)
              LD        A,E
              OR        A
              JR        Z,RCE_BASE
              INC       HL                             ; ceil for trailing short record
              LD        A,H
              OR        L
              JR        NZ,RCE_BASE
              INC       C                              ; carry into record-count byte 2
RCE_BASE      POP       AF                             ; S2 from caller
              LD        B,A
              AND       00FH
              RLCA
              RLCA
              RLCA
              RLCA
              LD        D,A                            ; base record bits 8..15: S2 low nibble
              LD        A,(IX+0CH)
              AND       01H
              RRCA
              LD        E,A                            ; base record bits 0..7: EX bit 0
              LD        A,(IX+0CH)
              SRL       A
              AND       00FH
              OR        D
              LD        D,A                            ; base record bits 8..15
              LD        A,B
              SRL       A
              SRL       A
              SRL       A
              SRL       A
              AND       03H
              LD        B,A                            ; base record bits 16..23
              LD        A,L
              SUB       E
              LD        L,A
              LD        A,H
              SBC       A,D
              LD        H,A
              LD        A,C
              SBC       A,B
              JR        C,RCE_ZERO                     ; extent starts after EOF
              OR        H
              JR        NZ,RCE_FULL                    ; >=256 records, clip to 128
              LD        A,L
              CP        080H
              RET       C                              ; 0..127 records
RCE_FULL      LD        A,080H
              RET
RCE_ZERO      XOR       A
              RET

; Stage 3: form a ProDOS 24-bit mark from the *application's* extent.
; EX[4:0], S2[5:0], CR[6:0] identify 128-byte records. IO_BEGIN
; temporarily stores a physical FRN in FCB+0E; use IOVS2 instead.
; Internal directory/loader FCBs have IOVIRT=0 and only EX/CR.
; IX=FCB; out: SMMLIP1..3, carry on invalid CR / byte offset >=16MiB.
SEQMARK       LD        A,(IX+20H)
              BIT       7,A
              JR        NZ,SQM_BAD
              AND       01H
              RRCA
              LD        (SMMLIP1),A
              LD        A,(IX+0CH)
              AND       03H
              RRCA
              RRCA
              LD        B,A                            ; EX bits 0..1 -> mark byte 1
              LD        A,(IX+20H)
              SRL       A
              OR        B
              LD        (SMMLIP2),A
              LD        A,(IOVIRT)
              OR        A
              JR        NZ,SQM_VEX
              LD        A,(IX+0CH)                     ; internal directory: legacy 8-bit EX
              JR        SQM_XHI
SQM_VEX       LD        A,(IX+0CH)
              AND       01FH                           ; CP/M app: EX low five bits
SQM_XHI       SRL       A
              SRL       A
              LD        B,A                            ; EX bits 2..4 -> byte 2 low bits
              LD        A,(IOVIRT)
              OR        A
              JR        Z,SQM_RAW
              LD        A,(IOVS2)
              AND       03FH                           ; exclude CP/M S2 flags
              BIT       5,A                            ; bit 5 exceeds ProDOS 16MiB
              JR        NZ,SQM_BAD
              ADD       A,A
              ADD       A,A
              ADD       A,A                            ; S2 bits 0..4 -> byte 2 bits 3..7
              OR        B
              JR        SQM_SET
SQM_RAW       LD        A,B                            ; raw internal FCB has no S2 extent
SQM_SET       LD        (SMMLIP3),A
              OR        A                              ; clear carry
              RET
SQM_BAD       SCF
              RET

; At CR 127 rollover, advance only EX bits 0..4; if wrapping 31->0,
; carry into IOVS2's low six bits while retaining S2 flag bits 6..7.
; Never touch FCB+0E while it contains the ProDOS reference number.
EXROLL        LD        A,(IOVIRT)
              OR        A
              JR        NZ,EXR_VIRT
              INC       (IX+0CH)                       ; internal raw FCB: old 8-bit EX
              RET
EXR_VIRT      LD        A,(IX+0CH)
              INC       A
              AND       01FH
              LD        B,A
              LD        A,(IX+0CH)
              AND       0E0H
              OR        B
              LD        (IX+0CH),A
              LD        A,B
              OR        A
              RET       NZ
              LD        A,(IOVIRT)
              OR        A
              RET       Z
              LD        A,(IOVS2)
              LD        C,A
              AND       03FH
              INC       A
              AND       03FH
              LD        B,A
              LD        A,C
              AND       0C0H
              OR        B
              LD        (IOVS2),A
              RET

; On moving into an existing extent, derive its RC from true ProDOS EOF.
; Otherwise RC=0. Failure to re-read EOF must never turn a successful
; sequential read/write into an error (nor cause the caller to retry it).
RCNEXT        LD        (IX+0FH),0
              LD        A,(IOVIRT)
              OR        A
              RET       Z
              LD        A,(IX+0EH)
              LD        (GEMLIN),A
              LD        HL,GEMLI
              CALL      PRODOS
              OR        A
              RET       NZ
              LD        A,(IOVS2)
              CALL      RCEOFRC
              LD        (IX+0FH),A
              RET

; Successful random I/O: publish 17-bit random position into EX/S2/CR.
; EX's high three bits and S2's high two flag bits are left unchanged.
; IOVS2 (not the temporarily borrowed FCB S2) receives the S2 update.
RANDEXT       LD        A,(IX+21H)
              AND       07FH
              LD        (IX+20H),A
              LD        A,(IX+21H)
              RLCA
              AND       01H
              LD        B,A
              LD        A,(IX+22H)
              ADD       A,A
              AND       01EH
              OR        B
              LD        B,A
              LD        A,(IX+0CH)
              AND       0E0H
              OR        B
              LD        (IX+0CH),A
              LD        A,(IOVIRT)
              OR        A
              RET       Z
              LD        A,(IX+22H)
              RRCA
              RRCA
              RRCA
              RRCA
              AND       00FH
              LD        B,A
              LD        A,(IX+23H)
              AND       01H
              RLCA
              RLCA
              RLCA
              RLCA
              OR        B
              LD        B,A
              LD        A,(IOVS2)
              AND       0C0H
              OR        B
              LD        (IOVS2),A
              RET

; BDOS 36: convert the NEXT sequential position (EX/S2/CR) into
; the 24-bit random record field; do not subtract one after a read.
RNEXT36       PUSH      DE
              POP       IX
              LD        A,(IX+20H)
              AND       07FH
              LD        B,A
              LD        A,(IX+0CH)
              AND       01H
              RRCA                                     ; EX bit 0 -> R0 bit 7
              OR        B
              LD        (IX+21H),A
              LD        A,(IX+0CH)
              RRCA                                     ; EX bits 1..4 -> R1 bits 0..3
              AND       00FH
              LD        B,A
              LD        A,(IX+0EH)
              RLCA
              RLCA
              RLCA
              RLCA
              AND       0F0H                           ; S2 bits 0..3 -> R1 bits 4..7
              OR        B
              LD        (IX+22H),A
              LD        A,(IX+0EH)
              RRCA
              RRCA
              RRCA
              RRCA
              AND       03H                            ; S2 bits 4..5 -> R2 bits 0..1
              LD        (IX+23H),A
              XOR       A
              LD        L,A
              RET

              ORG       06400H
; VT100/H19-to-Soroc translator in MAIN (not banked AUX TPA).
; TERM VT100=0, SOROC=1, H19/H89/VT52=2 (VT52 is H19 subset).
; Mode 2 uses 6502 Soroc VMODE=1 for translated escape sequences;
; the distinct terminal personality lives only in tab IX+6.
; Never feed translated bytes through VTGATE: VTEMIT uses B80F.
; Per-tab 8-byte state: parser, value, first argument, semicolon flag,
; saved row, saved column, private CSI flag, cooked CRLF suppression.
; H19 uses parser states 4=row, 5=column, 6=one mode parameter,
; and IX+2 as pending zero-based row. Save/restore remain IX+4/5.
; Only the Soroc display engine touches the hardware/virtual screen.
; Stage 11 output acceleration: terminal personality is cached for the
; currently running tab.  The old VTISEN walked TABCTXS (7 bytes/tab)
; on EVERY character.  Keep this in sync on switch and TERM requests.
VTISEN        LD        A,(VTMODEC)
              OR        A
              RET
VTMODEC       DEFB      1                              ; cold-start Soroc

; In: A=terminal mode. Preserves all caller registers and A.
VTSETMODE     PUSH      AF
              PUSH      BC
              PUSH      DE
              PUSH      HL
              PUSH      IX
              LD        C,A                            ; TABPICK does not touch C
              CALL      TABPICK
              LD        (IX+6),C
              LD        A,C
              LD        (VTMODEC),A                   ; update running terminal fast path
              ; Clear parser state when explicitly selecting a terminal.
              CALL      VTPTR
              XOR       A
              LD        B,8
VTRSTLOOP     LD        (IX+0),A
              INC       IX
              DJNZ      VTRSTLOOP
              POP       IX
              POP       HL
              POP       DE
              POP       BC
              POP       AF
              RET

; Return IX = state for current TABMODE; preserves BC/DE/HL.
VTPTR         PUSH      DE
              PUSH      HL
              LD        A,(TABMODE)
              LD        E,A
              LD        D,0
              LD        HL,VTSTATES
              ADD       HL,DE
              ADD       HL,DE
              ADD       HL,DE
              ADD       HL,DE
              ADD       HL,DE
              ADD       HL,DE
              ADD       HL,DE
              ADD       HL,DE
              PUSH      HL
              POP       IX
              POP       HL
              POP       DE
              RET

; A=original character, bit7 set only for cooked BDOS output.
VTCHAR        PUSH      BC
              PUSH      DE
              PUSH      HL
              PUSH      IX
              LD        C,A
              CALL      VTPTR
              LD        A,C
              AND       07FH
              LD        B,A
              CALL      VTISEN                         ; preserve IX and BC
              CP        2
              JP        Z,H19CHAR                      ; separate H19 escape decoder
              LD        A,(IX+0)
              OR        A
              JP        Z,VTIDLE
              DEC       A
              JP        Z,VTESC
              DEC       A
              JP        Z,VTCSI
              ; Ignore exactly one charset-designator byte after ESC ( or ).
              XOR       A
              LD        (IX+0),A
              JP        VTRET

VTIDLE        LD        A,B
              CP        01BH
              JR        NZ,VTLITERAL
              LD        (IX+0),1
              JP        VTRET
VTLITERAL     CP        0AH
              JR        NZ,VTNOTLF
              BIT       7,C
              JR        Z,VTRAWCHAR
              LD        A,(IX+7)
              LD        (IX+7),0
              OR        A
              JP        NZ,VTRET                       ; discard cooked LF after CR
              JR        VTRAWCHAR
VTNOTLF       XOR       A
              LD        (IX+7),A
              LD        A,B
              CP        0DH
              JR        NZ,VTRAWCHAR
              BIT       7,C
              JR        Z,VTRAWCHAR
              LD        (IX+7),1
              CALL      VTEMIT                         ; cooked CR -> CR + LF
              LD        A,0AH
              JR        VTRAWCHAR
VTRAWCHAR     LD        A,B
              CP        0DH
              JR        NZ,VTRAWOTHER
              BIT       7,C
              JR        Z,VTRAWOTHER
              LD        A,0AH                          ; already emitted cooked CR
              JR        VTRAWOTHER
VTRAWOTHER    CALL      VTEMIT
              JP        VTRET

VTESC         XOR       A
              LD        (IX+0),A
              LD        A,B
              CP        '['
              JR        Z,VTBEGIN
              CP        '('
              JR        Z,VTCHARSET
              CP        ')'
              JR        Z,VTCHARSET
              CP        '7'
              JP        Z,VTSAVE
              CP        '8'
              JP        Z,VTRESTORE
              CP        'D'
              JR        NZ,VTESCE
              LD        A,0AH                          ; IND: line feed
              JR        VTESCEMIT
VTESCE        CP        'E'
              JR        NZ,VTESCC
              LD        A,0DH
              CALL      VTEMIT
              LD        A,0AH
              JR        VTESCEMIT
VTESCC        CP        'c'
              JP        NZ,VTRET
              XOR       A
              LD        (IX+7),A
              CALL      VTNORMA
              CALL      VTCLEARALL
              JP        VTRET
VTESCEMIT     CALL      VTEMIT
              JP        VTRET
VTCHARSET     LD        (IX+0),3                         ; consume one charset designation
              JP        VTRET
VTBEGIN       LD        (IX+0),2
              XOR       A
              LD        (IX+1),A
              LD        (IX+2),A
              LD        (IX+3),A
              LD        (IX+6),A
              JP        VTRET

VTCSI         LD        A,B
              CP        '?'
              JR        NZ,VTNUM
              LD        (IX+6),1                         ; DEC private CSI: ignore safely
              JP        VTRET
VTNUM         CP        '0'
              JR        C,VTSEP
              CP        ':'
              JR        NC,VTSEP
              SUB       '0'
              LD        D,A                            ; new digit
              LD        A,(IX+1)
              CP        26
              JR        NC,VTMAX
              LD        E,A
              ADD       A,A
              ADD       A,A
              ADD       A,E
              ADD       A,A
              ADD       A,D
              JR        C,VTMAX
              LD        (IX+1),A
              JP        VTRET
VTMAX         LD        (IX+1),255
              JP        VTRET
VTSEP         CP        03BH                           ; ASCII semicolon; quoted ';' confuses z80asm
              JR        NZ,VTENDCSI
              LD        A,(IX+3)
              OR        A
              JP        NZ,VTRET                       ; ignore extra arguments
              LD        A,(IX+1)
              LD        (IX+2),A
              LD        (IX+3),1
              LD        (IX+1),0
              JP        VTRET
VTENDCSI      XOR       A
              LD        (IX+0),A
              LD        A,(IX+6)
              OR        A
              JP        NZ,VTRET                       ; e.g. ESC[?25l
              LD        A,B
              CP        'H'
              JP        Z,VTCUP
              CP        'f'
              JP        Z,VTCUP
              CP        'A'
              JP        Z,VTMOVEUP
              CP        'B'
              JP        Z,VTMOVEDOWN
              CP        'C'
              JP        Z,VTMOVERIGHT
              CP        'D'
              JP        Z,VTMOVELEFT
              CP        'J'
              JP        Z,VTERASESCREEN
              CP        'K'
              JP        Z,VTERASELINE
              CP        'm'
              JP        Z,VTSGR
              CP        's'
              JP        Z,VTSAVE
              CP        'u'
              JP        Z,VTRESTORE
              JP        VTRET

; Translate one-based ANSI CUP to zero-based Soroc coordinates.
VTCUP         LD        A,(IX+3)
              OR        A
              JR        Z,VTCUPONE
              LD        A,(IX+2)                       ; row argument
              LD        D,A
              LD        A,(IX+1)                       ; col argument
              JR        VTCUPC
VTCUPONE      LD        A,(IX+1)                       ; row, no column
              LD        D,A
              LD        A,1
VTCUPC        OR        A
              JR        NZ,VTCUPC1
              INC       A
VTCUPC1       CP        81
              JR        C,VTCUPC2
              LD        A,80
VTCUPC2       DEC       A
              LD        E,A
              LD        A,D
              OR        A
              JR        NZ,VTCUPR1
              INC       A
VTCUPR1       CP        25
              JR        C,VTCUPR2
              LD        A,24
VTCUPR2       DEC       A
              LD        D,A
              CALL      VTPOS
              JP        VTRET

; Read live 6502 VCOL/VROW, already virtualised by task switcher.
VTGETXY       LD        HL,(VSPTR)
              LD        E,(HL)
              INC       HL
              LD        D,(HL)
              RET
; D=zero-based row (0..23), E=zero-based col (0..79).
VTPOS         PUSH      DE
              LD        A,01BH
              CALL      VTEMIT
              LD        A,'='
              CALL      VTEMIT
              LD        A,D
              ADD       A,20H
              CALL      VTEMIT
              LD        A,E
              ADD       A,20H
              CALL      VTEMIT
              POP       DE
              RET
VTSTEP        LD        A,(IX+1)
              OR        A
              RET       NZ
              INC       A
              RET
VTMOVEUP      CALL      VTGETXY
              CALL      VTSTEP
              LD        L,A
              LD        A,D
              SUB       L
              JR        NC,VTMUY
              XOR       A
VTMUY         LD        D,A
              JR        VTMOVEGO
VTMOVEDOWN    CALL      VTGETXY
              CALL      VTSTEP
              ADD       A,D
              JR        C,VTMDMAX
              CP        24
              JR        C,VTMDY
VTMDMAX      LD        A,23
VTMDY         LD        D,A
              JR        VTMOVEGO
VTMOVERIGHT   CALL      VTGETXY
              CALL      VTSTEP
              ADD       A,E
              JR        C,VTMRMAX
              CP        80
              JR        C,VTMRX
VTMRMAX      LD        A,79
VTMRX         LD        E,A
              JR        VTMOVEGO
VTMOVELEFT    CALL      VTGETXY
              CALL      VTSTEP
              LD        L,A
              LD        A,E
              SUB       L
              JR        NC,VTMLX
              XOR       A
VTMLX         LD        E,A
VTMOVEGO      CALL      VTPOS
              JP        VTRET

VTERASESCREEN LD        A,(IX+1)
              CP        2
              JR        Z,VTEALL
              OR        A
              JP        NZ,VTRET                       ; ED 1 deferred
              LD        A,'Y'                          ; Soroc erase to end of page
              CALL      VTESCREQ
              JP        VTRET
VTEALL        CALL      VTCLEARALL
              JP        VTRET
VTCLEARALL    LD        A,'*'                          ; Soroc clear and home
VTESCREQ      PUSH      AF
              LD        A,01BH
              CALL      VTEMIT
              POP       AF
              JP        VTEMIT
VTERASELINE   LD        A,(IX+1)
              OR        A
              JR        Z,VTEOL
              CP        2
              JP        NZ,VTRET                       ; EL 1 deferred
              CALL      VTGETXY
              PUSH      DE
              LD        E,0
              CALL      VTPOS
              CALL      VTCLREOL
              POP       DE
              CALL      VTPOS
              JP        VTRET
VTEOL         CALL      VTCLREOL
              JP        VTRET
VTCLREOL      LD        A,'T'
              JP        VTESCREQ

VTSGR         LD        A,(IX+1)
              CP        7
              JR        Z,VTINVERSE
              OR        A
              JR        Z,VTNORMCALL
              CP        27
              JP        NZ,VTRET                       ; attributes not implemented
VTNORMCALL    CALL      VTNORMA
              JP        VTRET
; Render ANSI/H19 inverse with the Soroc write-protect video approximation.
; The real IQ-120 uses ESC ')' to START protected text and ESC '(' to END.
VTINVERSE     LD        A,')'
              CALL      VTATTR
              JP        VTRET
VTNORMA       LD        A,'('
VTATTR        JP        VTESCREQ
VTSAVE        CALL      VTGETXY
              LD        (IX+4),D
              LD        (IX+5),E
              JP        VTRET
VTRESTORE     LD        D,(IX+4)
              LD        E,(IX+5)
              CALL      VTPOS
VTRET         POP       IX
              POP       HL
              POP       DE
              POP       BC
              RET
VTEMIT        PUSH      HL
              LD        HL,RAWOUT                       ; B80F 6502 raw console
              CALL      C_SENDA
              POP       HL
              RET


; ---------------------------------------------------------------------------
; Heathkit H19 / H89 (also VT52) decoder. Called with B=7-bit character,
; C=original character including cooked bit, and IX=current terminal state.
; Share VTLITERAL's CR/LF handling and Soroc output primitives with VT100.
; ESC Y uses row+20h, column+20h, with BOTH parameter bytes consumed.
; ESC x/y/r require a single parameter; a new ESC in their place
; starts a new sequence (HITCH.COM emits ESC x ESC E).
; ---------------------------------------------------------------------------
H19CHAR       LD        A,(IX+0)
              OR        A
              JP        Z,H19IDLE
              CP        1
              JP        Z,H19ESC
              CP        4
              JP        Z,H19ROW
              CP        5
              JP        Z,H19COL
              ; Consume an x/y/r configuration parameter, but a new
              ; ESC cancels an incomplete command rather than eating it.
              XOR       A
              LD        (IX+0),A
              LD        A,B
              CP        01BH
              JP        Z,H19START
              JP        VTRET
H19IDLE       LD        A,B
              CP        01BH
              JP        Z,H19START
              JP        VTLITERAL                      ; shared normal output/CRLF
H19START      LD        (IX+0),1
              JP        VTRET

H19ESC        XOR       A
              LD        (IX+0),A
              LD        (IX+1),A                        ; motion commands are single-step
              LD        A,B
              CP        01BH
              JP        Z,H19START
              CP        'Y'
              JP        Z,H19ADR
              CP        'E'
              JP        Z,H19CLEAR
              CP        'H'
              JP        Z,H19HOME
              CP        'J'
              JP        Z,H19EOP
              CP        'K'
              JP        Z,H19EOL
              CP        'A'
              JP        Z,VTMOVEUP
              CP        'B'
              JP        Z,VTMOVEDOWN
              CP        'C'
              JP        Z,VTMOVERIGHT
              CP        'D'
              JP        Z,VTMOVELEFT
              CP        'j'
              JP        Z,VTSAVE
              CP        'k'
              JP        Z,VTRESTORE
              CP        'p'
              JP        Z,VTINVERSE
              CP        'q'
              JP        Z,H19NORM
              CP        'l'
              JP        Z,H19FLN
              CP        'z'
              JP        Z,H19RESET
              CP        'x'                             ; H19 operating mode set
              JP        Z,H19PARAM
              CP        'y'                             ; H19 operating mode reset
              JP        Z,H19PARAM
              CP        'r'                             ; H19 baud rate parameter
              JP        Z,H19PARAM
              ; ESC F/G graphics, =/> keypad, [ hold etc: safely ignore.
              ; Insert/delete line and character are not yet implemented.
              JP        VTRET
H19ADR        LD        (IX+0),4
              JP        VTRET
H19ROW        LD        A,B
              SUB       020H                           ; H19 cursor coordinates are +$20
              JR        NC,H19ROWOK
              XOR       A
H19ROWOK      CP        24
              JR        C,H19ROWIN
              LD        A,23
H19ROWIN      LD        (IX+2),A
              LD        (IX+0),5
              JP        VTRET
H19COL        XOR       A
              LD        (IX+0),A
              LD        A,B
              SUB       020H
              JR        NC,H19COLOK
              XOR       A
H19COLOK      CP        80
              JR        C,H19COLIN
              LD        A,79
H19COLIN      LD        E,A
              LD        D,(IX+2)
              CALL      VTPOS
              JP        VTRET
H19PARAM      LD        (IX+0),6                     ; discard one mode byte
              JP        VTRET
H19CLEAR      CALL      VTCLEARALL
              JP        VTRET
H19HOME       LD        DE,0
              CALL      VTPOS
              JP        VTRET
H19EOP        LD        A,'Y'                          ; Soroc erase to end of page
              CALL      VTESCREQ
              JP        VTRET
H19EOL        CALL      VTCLREOL
              JP        VTRET
H19NORM     CALL      VTNORMA
              JP        VTRET
H19RESET      CALL      VTNORMA
              CALL      VTCLEARALL
              JP        VTRET
H19FLN  CALL      VTGETXY
              PUSH      DE
              LD        E,0
              CALL      VTPOS
              CALL      VTCLREOL
              POP       DE
              CALL      VTPOS
              JP        VTRET

VTSTATES      DEFS      128

; =====================================================================
; Stage 8: per-session CP/M Search First/Next state.
; Save ONLY the 13 bytes that F_SNEXT examines from the search FCB;
; the raw ProDOS directory handle is closed after every search call.
; 21 bytes per tab: 13 search fields, EX, CR, count, extent (2),
; bound drive, bound USER nibble, valid byte. 16 * 21 = 336 bytes.
; Each Search Next reopens the same ProDOS directory and rereads the
; previous 512-byte block into the shared DIRBUF before continuing.
; This also protects a CCP DIR while background applications enumerate.
; =====================================================================
; ------------------------------------------------------------------
; Phase 6G: resident re-listen trampoline. NETCCP.COM exits once
; it binds UC1; on hangup the supervisor owns the lifetime and can
; launch it again as a child without nesting a new AUX process.
; This is reached ONLY after the AUX executable has been unwound.
; The listener executable is explicitly B:NETCCP.COM (Utils drive).
; Removing the tab with TAB <n> KILL stops the listener permanently.
; ------------------------------------------------------------------
              ORG       06900H
NC_REARM      LD        A,(TABMODE)
              LD        B,A
              CALL      NETKILL                         ; also revokes UCPERS/UC1
              LD        A,(TABMODE)
              LD        E,A
              LD        D,0
              LD        HL,SCHWAIT
              ADD       HL,DE
              LD        (HL),0                          ; no stale blocked read
              LD        A,(IOBYTE)
              AND       0FCH
              OR        1                              ; listener uses CRT until accept
              LD        (IOBYTE),A
              PUSH      AF
              CALL      TABPICK
              POP       AF
              LD        (IX+1),A                        ; keep descriptor consistent
              ; If the remote tab owns the physical screen, give it back
              ; to tab 0 while the listener restarts in the background.
              LD        A,(TABMODE)
              LD        B,A
              LD        A,(SCHFG)
              CP        B
              JR        NZ,NCR_GO
              LD        A,B
              OR        A
              JR        Z,NCR_GO                        ; tab 0 has no local fallback
              XOR       A
              LD        (TABREQ),A
NCR_GO        CALL      SHNOARG                         ; clean FCBs, command tail, DMA
              LD        HL,NCR_FCB
              LD        DE,PATHBUF2
              LD        BC,36
              LDIR
              CALL      SHPTR
              LD        (HL),2                          ; treat listener as transient child
              CALL      AUXRUN                          ; listener yields cooperatively
              LD        A,(AXQUIT)
              CP        3
              JP        Z,SHSTEP                        ; background listener suspended
              LD        A,(AUXEXCD)
              CP        6
              JP        NZ,SHSTEP                       ; normal listener accept/exit
              LD        DE,NCR_FAIL
              CALL      C_WRITESTR                     ; loading B:NETCCP.COM failed
              JP        SHSTEP
NCR_FAIL      DEFB      13,10
              DEFM      'NETCCP re-listen: could not load B:NETCCP.COM'
              DEFB      13,10,'$' 
NCR_FCB       DEFB      2                               ; B: regardless of CURDRV
              DEFM      'NETCCP  COM'                   ; eleven-byte CP/M 8.3
              DEFS      24

; A remote session can terminate by BDOS 0 / WBOOT after the W5100
; has entered CLOSE_WAIT, before UCIN gets to consume its synthetic CR.
; Catch the per-tab UCPERS=2 latch as well as AXQUIT=5 here; never
; accidentally reload a dead CCP.COM into a closed UC1 connection.
; Tail-jump from SHSTEP keeps its caller stack intact on re-listen.
              ORG       06A00H
NCSHSTEP      LD        A,(AXQUIT)
              CP        5
              JP        Z,NCABORT
              CP        3
              RET       Z                              ; suspended task, not terminated
              CALL      UCPPTR                         ; same tab: sticky disconnect latch
              LD        A,(HL)
              CP        2
              JP        Z,NCABORT
              CP        1
              JP        NZ,SHLOOP                       ; local CCP / listener startup
              ; Normal BDOS 0 can race a close: check the bound socket
              ; before reloading CCP.COM into a dead UC1 stream.
              CALL      UCBPTR
              LD        A,(HL)
              CP        4
              JP        NC,SHLOOP
              LD        D,A
              LD        A,3                            ; W5100 Sn_SR
              CALL      NI_READ
              CP        01CH                         ; CLOSE_WAIT
              JP        Z,NCABORT
              OR        A                             ; CLOSED
              JP        Z,NCABORT
              JP        SHLOOP

; CCP CLS emits the active terminal's clear/home sequence through
; normal console routing (including UC1). Do not call B812/CCPCLS.
; TERM VTMODEC: 0=VT100, 1=Soroc, 2=H19/VT52.
NCLS_RUN      LD        A,(VTMODEC)
              OR        A
              JR        Z,NCL_VT
              CP        2
              JR        Z,NCL_H19
              LD        HL,NCL_SR
              JR        NCL_SEND
NCL_VT        LD        HL,NCL_VTS
              JR        NCL_SEND
NCL_H19       LD        HL,NCL_HS
NCL_SEND      LD        A,(HL)
              OR        A
              RET       Z
              PUSH      HL
              LD        E,A
              CALL      C_WRITE
              POP       HL
              INC       HL
              JR        NCL_SEND
NCL_SR        DEFB      01BH,'*',0                     ; Soroc clear + home
NCL_HS        DEFB      01BH,'E',0                     ; Heath/VT52 clear + home
NCL_VTS       DEFB      01BH,'[','2','J',01BH,'[','H',0 ; ANSI clear + home

; Remote UC1 output is tail-jumped here to avoid expanding the crowded
; $4D00-$4FFF driver region. Preserve the UCOUT caller's stack depth.
UC_TXTRY     LD        A,1
              LD        (NXREQ),A
              LD        (UCFLAG),A
              CALL      NXTX
              PUSH      AF
              XOR       A
              LD        (UCFLAG),A
              POP       AF
              CP        1
              JR        Z,UC_TXEND                  ; successfully queued byte
              LD        B,A                          ; zero=TX full, FF=hardware error
              ; On either a full TX buffer or an error, check TCP status.
              LD        A,(NXSOCK)
              LD        D,A
              LD        A,3                           ; W5100 Sn_SR
              CALL      NI_READ
              CP        017H                        ; SOCK_ESTABLISHED
              JR        NZ,UC_TXCHK
              LD        A,B
              OR        A
              JR        Z,UC_TXTRY                   ; full buffer: retry when connected
              JR        UC_TXEND                     ; don't spin on a hardware error
UC_TXCHK      CP        01CH                        ; SOCK_CLOSE_WAIT
              JR        Z,UC_TXDRP
              OR        A                            ; SOCK_CLOSED
              JR        NZ,UC_TXEND                  ; other transient socket state
UC_TXDRP     LD        A,(AXMODE)
              OR        A
              JR        Z,UC_TXEND                  ; MAIN caller: no AUX app to unwind
              LD        A,5
              LD        (AXQUIT),A                    ; AXGATE must unwind remote app
              CALL      UCPPTR
              LD        (HL),2                        ; supervisor sees sticky hangup
UC_TXEND     JP        UCOEND

              ORG       06B00H
S8PTR         LD        HL,S8TABLE
              LD        A,(TABMODE)
              OR        A
              RET       Z
              LD        B,A
              LD        DE,21
S8PTLO        ADD       HL,DE
              DJNZ      S8PTLO
              RET

S8SAVE        CALL      S8PTR
              PUSH      HL
              EX        DE,HL
              LD        HL,AXSRCH
              LD        BC,13
              LDIR
              POP       HL
              LD        BC,13
              ADD       HL,BC
              LD        A,(DFCBEX)
              LD        (HL),A
              INC       HL
              LD        A,(DFCBSR)
              LD        (HL),A
              INC       HL
              LD        A,(CDBCOUNT)
              LD        (HL),A
              INC       HL
              LD        DE,(CDBEXT)
              LD        (HL),E
              INC       HL
              LD        (HL),D
              INC       HL
              LD        A,(DFCBDRV)                    ; bind implicit drive to current drive
              OR        A
              JR        NZ,S8DRIVE
              LD        A,(CURDRV)
              AND       00FH
              INC       A
S8DRIVE       LD        (HL),A
              INC       HL
              LD        A,(S8USER)                     ; keep original USER across SEARCH NEXT
              LD        (HL),A
              INC       HL
              LD        (HL),1
              RET

S8INVAL       CALL      S8PTR
              LD        DE,20
              ADD       HL,DE
              LD        (HL),0
              RET

; Save successful enumeration / invalidate unsuccessful enumeration.
; Close the raw directory FRN even if the search has further matches.
; Return the original BDOS search status in A (and L in caller).
S8EXIT        LD        (S8STATUS),A
              OR        A
              JR        NZ,S8BAD
              CALL      S8SAVE
              JR        S8CLOSE
S8BAD         CALL      S8INVAL
S8CLOSE       LD        DE,DFCB
              CALL      F_CLOSE
              LD        A,(S8STATUS)
              RET

; Restore search FCB, bound drive/user and directory block bookmark.
; _F_OPEN allocates a NEW raw ProDOS FRN; rewind by exactly four 128-byte
; records to reconstruct the directory block containing the last hit.
; Reposition CDBPTR using count * 39 from DIRBUF+4 (works for header).
S8REST        CALL      S8PTR
              PUSH      HL
              LD        DE,20
              ADD       HL,DE
              LD        A,(HL)
              POP       HL
              OR        A
              JP        Z,S8FAIL
              PUSH      HL
              LD        DE,AXSRCH
              LD        BC,13
              LDIR
              POP       HL
              LD        DE,13
              ADD       HL,DE
              LD        A,(HL)
              LD        (S8EX),A
              INC       HL
              LD        A,(HL)
              LD        (S8CR),A
              INC       HL
              LD        A,(HL)
              LD        (S8COUNT),A
              INC       HL
              LD        E,(HL)
              INC       HL
              LD        D,(HL)
              LD        (S8EXT),DE
              INC       HL
              LD        A,(HL)
              LD        (DFCBDRV),A
              INC       HL
              LD        A,(HL)
              LD        (S8USER),A
              LD        HL,AXSRCH
              LD        (TEMPWORD),HL
              LD        A,(CURDRV)
              LD        (S8CUR),A
              AND       00FH
              LD        B,A
              LD        A,(S8USER)
              OR        B
              LD        (CURDRV),A
              LD        DE,DFCB
              CALL      _F_OPEN
              PUSH      AF
              LD        A,(S8CUR)
              LD        (CURDRV),A
              POP       AF
              OR        A
              JP        NZ,S8FAIL
              LD        A,(S8EX)
              LD        (DFCBEX),A
              LD        A,(S8CR)
              CP        4
              JR        NC,S8CRPOS
              LD        A,(DFCBEX)
              DEC       A
              LD        (DFCBEX),A
              LD        A,(S8CR)
              ADD       A,124                          ; record 0->124 in previous extent
              JR        S8SETP
S8CRPOS       SUB       4
S8SETP        LD        (DFCBSR),A
              LD        HL,AXDATA
              LD        (DMAADDR),HL
              CALL      RDDIRBLK
              OR        A
              JP        NZ,S8FAIL
              LD        A,(S8COUNT)
              LD        (CDBCOUNT),A
              LD        HL,(S8EXT)
              LD        (CDBEXT),HL
              LD        A,(S8COUNT)
              LD        B,A
              LD        HL,DIRBUF+4
              LD        DE,FILEENTSZ
              OR        A
              JR        Z,S8POSOK
S8POSLO       ADD       HL,DE
              DJNZ      S8POSLO
S8POSOK       LD        (CDBPTR),HL
              XOR       A
              RET
S8FAIL        LD        A,0FFH
              RET

; The CCP's DIR is an in-memory MAIN search, not an AUX BDOS call.
; It uses the same slot snapshots, and returns the entry in FILEBUF.
S8MSF         LD        HL,FCB1
              LD        DE,AXSRCH
              LD        BC,13
              LDIR
              LD        DE,AXSRCH
              LD        A,(CURDRV)
              AND       0F0H
              LD        (S8USER),A
              CALL      F_SFIRST
              JP        S8EXIT
S8MSN         CALL      S8REST
              OR        A
              JR        Z,S8MSOK
              JP        S8EXIT                         ; invalidate and close on reopen error
S8MSOK        LD        HL,FILEBUF
              LD        (DMAADDR),HL
              CALL      F_SNEXT
              JP        S8EXIT

S8STATUS      DEFB      0
S8CUR         DEFB      0
S8USER        DEFB      0
S8EX          DEFB      0
S8CR          DEFB      0
S8COUNT       DEFB      0
S8EXT         DEFW      0
S8TABLE       DEFS      336

              ORG       07000H

AXBDOS        CALL      XSPRE                          ; skip physical keyboard wait if XSUB
              RET       C
              LD        A,C
              LD        (AXBADFN),A                    ; diagnostic: remember original BDOS C
              CP        0FDH                           ; NET UC1 per-session socket binding
              JP        Z,NCAPI
              CP        0FCH                           ; NET TX/RX via AUX parameter block
              JP        Z,NXIO
              CP        0FBH                           ; NET socket I/O (E=0 status, else command)
              JP        Z,NETIO
              CP        0FAH                           ; NET socket manager (E=operation, D=socket)
              JP        Z,NETAPI
              CP        0F9H                           ; private W5100 bridge: DE=AUX [hi,lo,data]
              JP        Z,AXW5WRITE                     ; use MAIN AXGATE before switching to 6502
              CP        0F7H                           ; AUX CCP: chain/load next .COM via MAIN supervisor
              JP        NC,AXF7F8                     ; F7 launch or F8 native CCP builtin
              CP        0F0H                           ; private TERM: 0 VT100 / 1 Soroc / 2 H19
              JP        Z,AXTMODE
              OR        A
              JP        Z,AUXBDOS0
              CP        1
              JP        Z,XSCIN
              CP        2
              JP        Z,AUXBDOS2
              CP        6
              JP        Z,XSRAW
              CP        9
              JP        Z,AUXBDOS9
              CP        3
              JP        Z,IOREADER
              CP        4
              JP        Z,IOPUNCH
              CP        5
              JP        Z,IOLIST
              CP        0F4H                           ; AUX LC BIOS LIST
              JP        Z,IOLIST
              CP        0F5H                           ; AUX LC BIOS PUNCH
              JP        Z,IOPUNCH
              CP        0F6H                           ; AUX LC BIOS READER
              JP        Z,IOREADER
              CP        11
              JP        Z,XSSTAT
              CP        12
              JP        Z,ABDVER
              CP        02DH                           ; CP/M 3: SET BDOS ERROR MODE (BBC BASIC)
              JP        Z,AXERRMODE                    ; accept request; ignore mode setting
              CP        10
              JP        Z,AXLINE
              CP        13
              JP        Z,AXRESET
              CP        24
              JP        Z,AXLOGV
              CP        27
              JP        Z,AXAVEC
              CP        28
              JP        Z,AXSETRO
              CP        29
              JP        Z,AXROV
              CP        31
              JP        Z,AXDPB
              CP        37
              JP        Z,AXDRST
              CP        30
              JP        Z,AXFSEL                       ; BDOS SET FILE ATTRIBUTES needs AUX FCB
              CP        0F1H
              JP        Z,XSBSTAT
              CP        0F2H
              JP        Z,XSBIIN
              CP        0F3H
              JP        Z,AXBIOUT
              CP        26
              JP        Z,AXSDMA
              CP        17
              JP        Z,AXSFIRST
              CP        18
              JP        Z,AXSNEXT
; Compact AUX BDOS FCB dispatch: contiguous function ranges.
; CP/JR/JP leave A untouched; AXFSEL expects original BDOS A value.
              CP        15
              JR        C,AXF17
              CP        17
              JP        C,AXFSEL                       ; 15,16
AXF17         CP        19
              JR        C,AXF24
              CP        24
              JP        C,AXFSEL                       ; 19..23
AXF24         CP        33
              JR        C,AXF37
              CP        37
              JP        C,AXFSEL                       ; 33..36
AXF37         CP        40
              JP        Z,AXFSEL
              CP        14
              JP        Z,AXDSET
              CP        25
              JP        Z,AXDGET
              CP        32
              JP        Z,AXUSER
              CP        7
              JP        Z,AXIOGET
              CP        8
              JP        Z,AXIOSET
; CP/M 3 BDOS $2D: Set error mode (E=FE in BBC BASIC).
; CP/M 2.2-style Zapple-II has no equivalent error-mode switch.
; The CP/M 3 call returns no value; return zero for compatibility.
AXERRMODE     XOR       A
              LD        L,A
              RET
; Unsupported calls must not pass AUX pointers to the MAIN BDOS.
; Private AUX BDOS $F9: socket-one W5100 register write via native 6502.
; On entry DE points to 3 AUX bytes: address high, address low, data.
; The AUX->MAIN copy is performed before the SoftCard CPU handoff.
; The calling AUX stack is parked by AXGATE, so the 6502 can return safely.
; Returns A=L=0. No reset or access to socket 0 is performed by service.
AXW5WRITE     EX        DE,HL                         ; HL = AUX parameter pointer
              LD        DE,AXW5BUF                     ; MAIN staging in $78xx
              LD        BC,3
              CALL      LCA2M                          ; existing AUX->MAIN copier
              LD        A,(AXW5BUF)
              LD        (AREG),A                        ; W5100 address high
              LD        A,(AXW5BUF+1)
              LD        (XREG),A                        ; W5100 address low
              LD        A,(AXW5BUF+2)
              LD        (YREG),A                        ; value
              LD        HL,0B827H                       ; new native W5WRITE vector
              LD        (ADDR),HL
              LD        A,1
              LD        (CMD),A
              LD        (SOFTCARD),A                    ; MAIN-safe existing handoff
              XOR       A
              LD        L,A
              RET

AXBAD         LD        A,2
              LD        (LCQUIT),A
              LD        A,0FFH
              LD        L,A
              RET
; TERM.COM must not switch to the 6502 directly from AUX RAM:
; the 6502 console lives at MAIN $B800. This dispatcher is called by
; LCGATE with MAIN RAM selected, and the original LC/stack are restored
; automatically on return. Private BDOS $F0: 0=VT100, 1=Soroc,
; 2=H19/VT52. The 6502 video renderer must receive Soroc mode (1)
; for H19: it cannot recognize the Z80-only personality value 2.
AXTMODE       JP        SCHTMCHK
AXTMRUN       CALL      VTSETMODE                      ; save active tab mode and reset CSI
              CP        2                              ; H19 translator emits Soroc
              JR        NZ,AXTM6502
              LD        A,1
AXTM6502      LD        (AREG),A
              LD        HL,0B80CH                      ; 6502 VSETMODE public entry
              LD        (ADDR),HL
              LD        A,1
              LD        (CMD),A
              LD        (SOFTCARD),A                   ; invoke 6502 with MAIN selected
              ; VSETMODE updates the Microsoft BASIC table in MAIN $0396.
              ; BASIC now executes in AUX and reads AUX $0396 instead.
              ; Mirror its nine bytes (Z80 $F396-$F39E) to AUX too.
              LD        HL,0F396H
              LD        DE,0F396H
              LD        BC,9
              CALL      AXM2A
              XOR       A
              LD        L,A
              RET
AXTMERR       LD        A,0FFH
              LD        L,A
              RET

; Require the full 36-byte FCB to lie below BDOS at $DE00.
AXCKFCB       LD        A,D
              CP        0DDH
              JR        C,AXCKOK
              JR        NZ,AXCKBAD
              LD        A,E
              CP        0DDH
              JR        NC,AXCKBAD
AXCKOK        XOR       A
              RET
AXCKBAD       LD        A,1
              RET
; An entire 128-byte record must fit below $DE00.
AXCKDMA       LD        HL,(AXDMAP)
              LD        A,H
              CP        0DDH
              JR        C,AXCKOK
              JR        NZ,AXCKBAD
              LD        A,L
              CP        081H
              JR        C,AXCKOK
              JR        AXCKBAD
AXSDMA        LD        (AXDMAP),DE
              XOR       A
              LD        L,A
              RET
AXDSET        CALL      DRV_SET
              XOR       A
              LD        L,A
              RET
AXDGET        CALL      DRV_GET
              LD        L,A
              RET
AXUSER        CALL      F_USERNUM
              LD        L,A
              RET
; Cooked CONIN via existing BIOS raw read, with echo and ^C exit.
; Avoid C_READ's nonreturning main-bank warm boot in AUX mode.
AXCIN         LD        A,(IOBYTE)
              AND       3
              CP        1
              JP        NZ,IOCCOOK                     ; redirected CON input
              JP        TSKCIN                         ; CRT: scheduler/Open Apple aware
AXIOGET       JP        GET_IOB
AXIOSET       JP        SET_IOB
AXAUXRD       LD        A,1AH                          ; no input device: CP/M EOF
              LD        L,A
              RET
AXAUXWR       XOR       A                              ; no punch/list device attached
              LD        L,A
              RET

; Direct BIOS console calls use private C codes $F1..$F3 from the LC
; jump-table shims. Caller registers are preserved by those shims.
AXBICON       LD        A,(IOBYTE)
              AND       3
              CP        1
              JP        NZ,IOSTAT
              JP        TSKSTAT                        ; CRT: catch Open Apple on BIOS CONST
AXBIREAD      LD        A,(IOBYTE)
              AND       3
              CP        1
              JP        NZ,IOCONIN
              JP        TSKBIRD                        ; CRT: handler moved under $0800
AXBIOUT       CALL      C_RAWPUT
              XOR       A
              LD        L,A
              RET

; CP/M disk control calls not involving AUX pointers.
AXLOGV        JP        DRV_LOGVEC
AXROV         JP        DRV_ROVEC
AXSETRO       CALL      DRV_SETRO
              XOR       A
              LD        L,A
              RET
AXDRST        CALL      DRV_RESET
              XOR       A
              LD        L,A
              RET
AXRESET       LD        A,(LCB1RO)
              CALL      DRV_ALLRST
              LD        (AXSTAT),A
              LD        A,(LCB2RW)
              LD        A,(LCB2RW)
              LD        HL,0080H
              LD        (AXDMAP),HL
              LD        A,(AXSTAT)
              LD        L,A
              RET

; Return pointers to storage outside the contiguous CP/M TPA.
; $F300 maps to AUX Apple $0300, $F800 to AUX Apple $0800-$0FFF.
; The caller may freely read these while LC bank2 remains mapped.
AXDPB         LD        A,(LCB1RO)
              CALL      DRV_DPB
              LD        DE,0F300H
              LD        BC,15
              CALL      AXM2A
              LD        HL,0F300H
              XOR       A
              RET
AXAVEC        LD        A,(LCB1RO)
              CALL      DRV_AVEC
              LD        DE,0F800H
              LD        BC,0800H
              CALL      AXM2A
              LD        HL,0F800H
              XOR       A
              RET

; CP/M BDOS 10: buffered line input into an AUX caller's buffer.
; Check the ACTUAL buffer capacity, not a blanket 260-byte region.
; The AUX TPA ends at DDFFH; BDOS stub starts at DE00H.
; For capacity N we may write N data bytes plus one CR at DE+2+N.
; 260-byte MAIN staging handles all legal one-byte capacities (0..255).
; Stage 22.2: when OA+tab interrupts a partly typed line, save its
; characters in the calling tab's AUX BDOS-10 buffer before parking.
; AXLINER (called only by AXRETRY) restores the count + characters
; after that tab is selected again, with no re-echo or lost input.
AXLINE        XOR       A                              ; fresh BDOS 10 call
              JR        AXLENTRY
AXLINER       LD        A,1                            ; resuming an interrupted line
AXLENTRY      LD        (AXLRESUME),A
              LD        (AXLIP),DE
              LD        A,D
              CP        0DEH
              JP        NC,AXBAD                       ; buffer header must be below DE00H
AXLVALID      EX        DE,HL
              LD        DE,AXLBUF
              LD        BC,1
              CALL      LCA2M                          ; read caller's capacity byte from AUX
              LD        A,(AXLBUF)
              LD        C,A
              LD        B,0
              LD        HL,(AXLIP)
              INC       HL
              INC       HL
              ADD       HL,BC                          ; address of final possible CR byte
              LD        A,H
              CP        0DEH
              JP        NC,AXBAD                       ; disallow touching DE00H+ BDOS page
              ; Only consume submitted input after XSUB was explicitly
              ; enabled from a script. XSREADY handles prior status polls.
              ; Never start a fresh XSUB line when resuming partial input.
              LD        A,(AXLRESUME)
              OR        A
              JR        NZ,AXLSETUP
              CALL      XSREADY
              OR        A
              JP        NZ,AXLSUB
AXLSETUP      LD        A,(AXLBUF)
              LD        B,A                            ; capacity for line editor
              LD        C,0                            ; bytes entered
              LD        HL,AXLBUF+2
              LD        A,(AXLRESUME)
              OR        A
              JR        Z,AXLNEXT                      ; new line, start empty
              ; Saved [max][count][partial text] lives in this tab's AUX
              ; buffer, so another tab's BDOS 10 cannot overwrite it.
              PUSH      BC
              PUSH      HL
              LD        HL,(AXLIP)
              LD        DE,AXLBUF
              LD        C,B
              LD        B,0
              INC       BC
              INC       BC                             ; capacity + 2 header bytes
              CALL      LCA2M
              POP       HL
              POP       BC
              LD        A,(AXLBUF+1)                  ; saved partial line count
              CP        B
              JR        C,AXLCOUNTOK                   ; count below capacity
              JR        Z,AXLCOUNTOK                   ; count equals capacity
              ; The saved count was larger than the current capacity.
              ; Discard invalid input rather than writing beyond staging.
              JP        AXBAD
AXLCOUNTOK    LD        C,A
              LD        E,C
              LD        D,0
              ADD       HL,DE                          ; resume at end of partial text
AXLNEXT       CALL      NCALINE                        ; nonblocking on UC1, CRT unchanged
              JR        C,AXLPARK
              NOP
              NOP
              AND       07FH
              ; Always process OA+tab, even when the line is nonempty.
              ; Previously TSKKEY was bypassed when C>0, making shortcuts
              ; unusable during command entry or any BDOS 10 edit.
              CALL      TSKKEY
              JP        C,AXLPARK
AXLKEY        CP        13
              JR        Z,AXLDONE
              CP        3
              JR        Z,AXLCAN
              CP        8
              JR        Z,AXLBS
              CP        127
              JR        Z,AXLBS
              CP        32
              JR        C,AXLNEXT
              PUSH      AF
              LD        A,B
              CP        C
              JR        Z,AXLFULL
              POP       AF
              LD        (HL),A
              INC       HL
              INC       C
              LD        E,A
              PUSH      BC
              PUSH      HL
              CALL      C_WRITE
              POP       HL
              POP       BC
              JR        AXLNEXT
AXLFULL       POP       AF
              JR        AXLNEXT
AXLBS         LD        A,C
              OR        A
              JR        Z,AXLNEXT
              DEC       C
              DEC       HL
              PUSH      BC
              PUSH      HL
              LD        E,8
              CALL      C_WRITE
              LD        E,' '
              CALL      C_WRITE
              LD        E,8
              CALL      C_WRITE
              POP       HL
              POP       BC
              JR        AXLNEXT
; Queue a manual tab switch without losing a partly entered BDOS 10
; line. We must checkpoint to the caller's per-tab AUX buffer because
; AXLBUF is a single shared MAIN staging buffer reused by other tabs.
; TSKKEY already set TABREQ/AXQUIT=3, and preserved BC and HL.
AXLPARK       LD        A,C
              LD        (AXLBUF+1),A
              PUSH      BC
              PUSH      HL
              LD        HL,AXLBUF
              LD        DE,(AXLIP)
              LD        B,0
              INC       BC
              INC       BC                             ; copy max/count/data[0..count)
              CALL      AXM2A
              POP       HL
              POP       BC
              LD        A,0FBH                         ; checkpointed-line marker
              LD        L,A
              RET

AXLCAN        JP        AXCCANCEL                      ; shell: empty line; child: warm boot
AXLDONE       LD        (HL),13
              LD        A,C
              LD        (AXLBUF+1),A
              PUSH      BC
              LD        E,13
              CALL      C_WRITE
              POP       BC
              LD        B,0
              INC       BC
              INC       BC
              INC       BC
              LD        HL,AXLBUF
              LD        DE,(AXLIP)
              CALL      AXM2A
              XOR       A
              LD        L,A
              RET

; Auxiliary searches use a per-tab bookmark. The raw directory handle and
; shared DIRBUF are released between calls, so other tabs cannot disturb it.
AXSFIRST      CALL      AXCKFCB
              JP        NZ,AXBAD
              CALL      AXCKDMA
              JP        NZ,AXBAD
              EX        DE,HL
              LD        DE,AXSRCH
              LD        BC,36
              CALL      LCA2M
              LD        DE,AXSRCH
              LD        HL,AXDATA
              LD        (DMAADDR),HL
              CALL      S8AUXBIND                     ; capture current USER at SEARCH FIRST
              CALL      F_SFIRST
              JP        AXSRDONE
AXSNEXT       CALL      AXCKDMA
              JP        NZ,AXBAD
              LD        A,(LCB1RO)
              CALL      S8REST                         ; reopen directory at saved cursor
              OR        A
              JP        NZ,AXSRDONE
              LD        HL,AXDATA
              LD        (DMAADDR),HL
              CALL      F_SNEXT
AXSRDONE      CALL      S8EXIT                        ; snapshot/invalidate and release FRN
              LD        (AXSTAT),A
              LD        A,(LCB2RW)
              LD        A,(LCB2RW)
              LD        A,(AXSTAT)
              OR        A
              JP        NZ,AXRETURN
              LD        HL,AXDATA
              LD        DE,(AXDMAP)
              LD        BC,128
              CALL      AXM2A
AXRETURN      LD        A,(AXSTAT)
              LD        L,A
              LD        H,0                            ; CP/M byte result: clear high byte
              RET

; Copy one 36-byte auxiliary FCB into MAIN staging; preserve the caller's
; AUX pointer to copy back RC/EX/CR/random-record updates afterwards.
AXFSEL        PUSH      AF
              CALL      AXCKFCB
              POP       BC                             ; B = original function number
              JP        NZ,AXBAD
              LD        A,B
              LD        (AXFN),A
              LD        (AXFCBP),DE
              EX        DE,HL
              LD        DE,AXFCB
              LD        BC,36
              CALL      LCA2M
; Writing a record: copy 128 bytes from auxiliary DMA to MAIN DMA first.
              LD        A,(AXFN)
              CP        21
              JP        Z,AXWPRE
              CP        34
              JP        Z,AXWPRE
              CP        40
              JP        Z,AXWPRE
              JR        AXDISP
AXWPRE        CALL      AXCKDMA
              JP        NZ,AXBAD
              LD        HL,(AXDMAP)
              LD        DE,AXDATA
              LD        BC,128
              CALL      LCA2M
AXDISP        LD        DE,AXFCB
              LD        HL,AXDATA
              LD        (DMAADDR),HL
; Wildcard F_DELETE uses FILEBUF internally, not DMAADDR: redirect it.
              LD        A,(AXFN)
              CP        19
              JP        NZ,AXNOTDEL
              LD        HL,FILEBUF
              LD        (DMAADDR),HL
AXNOTDEL      LD        A,(LCB1RO)
              LD        A,(AXFN)
              CP        15
              JP        Z,AXOP
              CP        16
              JP        Z,AXCL
              CP        19
              JP        Z,AXDEL
              CP        20
              JP        Z,AXRD
              CP        21
              JP        Z,AXWR
              CP        22
              JP        Z,AXMAKE
              CP        23
              JP        Z,AXREN
              CP        30
              JP        Z,AXATTR
              CP        33
              JP        Z,AXRRD
              CP        34
              JP        Z,AXRWR
              CP        40
              JP        Z,AXRWR
              CP        35
              JP        Z,AXSIZE
              CP        36
              JP        Z,AXRREC
              LD        A,(LCB2RW)
              LD        A,(LCB2RW)
              JP        AXBAD
AXOP          CALL      F_OPEN
              JR        AXFEND
AXCL          CALL      F_CLOSE
              JR        AXFEND
AXDEL         CALL      F_DELETE
              JR        AXFEND
AXRD          CALL      F_READ
              JR        AXFEND
AXWR          CALL      F_WRITE
              JR        AXFEND
AXMAKE        CALL      F_MAKE
              JR        AXFEND
AXREN         CALL      F_RENAME
              JR        AXFEND
AXATTR        CALL      F_ATTRIB
              JR        AXFEND
AXRRD         CALL      F_READRAND
              JR        AXFEND
AXRWR         CALL      F_WRITERAND
              JR        AXFEND
AXSIZE        CALL      F_SIZE
              JR        AXFEND
AXRREC        CALL      F_RANDREC
; Main filesystem has returned: reselect the gateway LC bank BEFORE
; returning to LIGATE's caller in the $B000 LC page.
AXFEND        LD        (AXSTAT),A
              LD        A,(LCB2RW)
              LD        A,(LCB2RW)
; Copy caller FCB back, including updated extent/record/file-open marker.
              LD        HL,AXFCB
              LD        DE,(AXFCBP)
              ; Sequential BDOS calls use only the 33-byte FCB.
              ; Copying 36 bytes would overwrite the next FCB in F80,
              ; which stores its source, listing and object FCBs adjacent.
              ; Random-record functions (33,34,35,36,40) need 36 bytes.
              LD        BC,33
              LD        A,(AXFN)
              CP        33
              JR        C,AXFCPY
              LD        BC,36
AXFCPY        CALL      AXM2A
; A successful read transfers the 128-byte MAIN DMA result to AUX.
              LD        A,(AXSTAT)
              OR        A
              JP        NZ,AXFRET
              LD        A,(AXFN)
              CP        20
              JP        Z,AXPOSTR
              CP        33
              JP        NZ,AXFRET
AXPOSTR       CALL      AXCKDMA
              JP        NZ,AXBAD
              LD        HL,AXDATA
              LD        DE,(AXDMAP)
              LD        BC,128
              CALL      AXM2A
AXFRET        LD        A,(AXSTAT)
              LD        L,A
              LD        H,0                            ; CP/M byte result: clear high byte
              RET

; MAIN to AUX copy. With RAMRD=MAIN the code remains executable while
; RAMWRT=AUX, but NO CALLs/PUSHes may occur until RAMWRT is reset.
AXM2A         LD        A,(LCB2RW)
              LD        A,(LCB2RW)
              XOR       A
              LD        (ZPAUX),A                      ; AUX LC bank2 for high addresses
              LD        (WRAUX),A
              LDIR
              LD        (WRMAIN),A
              LD        (ZPMAIN),A
              LD        A,(LCB1RO)
              XOR       A
              RET

; ================================================================

; Stage 22.2 deferred AUX input dispatcher relocated from MAIN $08xx.
; This area has spare room; keep the stable AXRETRY entry at $08xx.
AXRETRYX      LD        A,(AXRES)
              CP        0F1H
              JR        Z,ARCOOK
              CP        0F2H
              JR        Z,ARBIOS
              CP        0FAH
              JR        Z,ARLINE                       ; parked before reading any key
              CP        0FBH
              JR        Z,ARLRES                       ; parked with a partial line
              CP        0F6H
              JR        Z,ARRAW
              CP        0F3H
              JR        Z,ARSTAT
              JP        AXGO
ARCOOK        CALL      TSKCIN
              JR        ARDONE
ARBIOS        CALL      TSKBIRD
              JR        ARDONE
ARLINE        LD        DE,(AXLIP)
              CALL      AXLINE                        ; no partial text was checkpointed
              JR        ARDONE
ARLRES        LD        DE,(AXLIP)
              CALL      AXLINER                       ; restore saved partial BDOS 10 line
              JR        ARDONE
ARRAW         LD        E,0FFH
              CALL      AUXBDOS6
              JR        ARDONE
ARSTAT        CALL      TSKSTAT                        ; retry actual BIOS/BDOS status request
ARDONE        LD        (AXRES),A
              LD        (AXRHL),HL
              LD        A,(AXQUIT)
              CP        3
              CALL      Z,TASKSAVE
              LD        A,(AXQUIT)
              OR        A
              JP        NZ,AXFIN
              JP        AXGO


              ORG       07590H
TCLIST        DEFM      'LIST '
              DEFB      0
TCSUSP        DEFM      'SUSPEND '
              DEFB      0
TCRESUM       DEFM      'RESUME '
              DEFB      0
TCEXCL        DEFM      'EXCLUSIVE '
              DEFB      0
TCKILL        DEFM      'KILL '
              DEFB      0
TCHELP        DEFM      'HELP '
              DEFB      0
TL_HOLD       DEFM      ' [Suspended]$'
TB_HELP       LD        DE,TB_HELPMSG
              JP        C_WRITESTR


; Small command summary; keep clear of the $7600 command table.
TB_HELPMSG    DEFM      'TAB n [SUSP/RES/EXCL/KILL], TAB LIST/HELP'
              DEFB      13,'$'

              ORG       07600H
; Builtin dispatch table relocated to MAIN $5800.

; Native CCP terminal selector.  This code runs with MAIN RAM visible,
; unlike the old AUX .COM, so it calls the 6502 VSETMODE vector directly.
; The next AUXRUN already mirrors MAIN $0396-$039E to AUX for MBASIC.
CCPTERM       LD        HL,FILEBUF+2                   ; first argument, after leading space
              LD        DE,TMVT100
              CALL      TMCHK
              JR        Z,TMVT
              LD        HL,FILEBUF+2
              LD        DE,TMSOROC
              CALL      TMCHK
              JR        Z,TMSR
              LD        HL,FILEBUF+2
              LD        DE,TMH19
              CALL      TMCHK3
              JR        Z,TMHT
              LD        HL,FILEBUF+2
              LD        DE,TMH89
              CALL      TMCHK3
              JR        Z,TMHT
              LD        HL,FILEBUF+2
              LD        DE,TMVT52
              CALL      TMCHK4
              JP        NZ,CCPBAD                      ; require complete terminal name
TMHT          LD        A,2                            ; Heath H19/H89/VT52
              JR        TMSET
TMSR          LD        A,1                            ; Soroc
              JR        TMSET
TMVT          XOR       A                              ; VT100
TMSET         CALL      VTSETMODE                      ; update tab mode immediately
              CP        2                              ; 6502 renderer requires Soroc
              JR        NZ,TM6502
              LD        A,1
TM6502        LD        (AREG),A
              LD        HL,0B80CH                      ; 6502 VSETMODE, already in MAIN
              LD        (ADDR),HL
              LD        A,1
              LD        (CMD),A
              LD        (SOFTCARD),A
              RET
; Check five letters and the delimiting space, against a literal.
; The CCP parser guarantees a trailing space after the argument.
TMCHK         LD        B,5
              JR        TMCHL
TMCHK3        LD        B,3
              JR        TMCHL
TMCHK4        LD        B,4
TMCHL         LD        A,(DE)
              CP        (HL)
              RET       NZ
              INC       DE
              INC       HL
              DJNZ      TMCHL
              LD        A,(HL)
              CP        ' '
              RET
TMVT100       DEFM      'VT100'
TMSOROC       DEFM      'SOROC'
TMH19         DEFM      'H19'
TMH89         DEFM      'H89'
TMVT52        DEFM      'VT52'

; BDOS 30: Set CP/M file R/O attribute in ProDOS access byte.
; STAT enumerates wildcards and passes each resolved FCB individually.
; Leave FCB and DMA unchanged, preserve file type and modification date.
F_ATTRIB      CALL      DCHKRO
              JP        NZ,RODENY
              PUSH      DE
              POP       IX
              LD        A,(IX+09H)                     ; first extension byte's high bit
              AND       080H
              LD        (ATTR_RO),A
              LD        HL,1
              ADD       HL,DE
              LD        B,11
FA_VALID      LD        A,(HL)
              AND       07FH
              CP        '?'
              JR        Z,FA_ERROR
              INC       HL
              DJNZ      FA_VALID
              LD        IX,PATHBUF
              CALL      FCB2PATH
              CALL      CACHECLS                       ; Apply attributes with file physically closed
              OR        A
              JP        NZ,FA_ERROR
              LD        HL,GFIMLI
              CALL      PRODOS                         ; GET_FILE_INFO (param count 10)
              OR        A
              JR        NZ,FA_ERROR
              LD        A,(ATTR_RO)
              OR        A
              LD        A,(GFIMLIAC)
              JR        Z,FA_RW
              AND       03DH                           ; disable destroy/rename/write ($C2)
              JR        FA_CHG
FA_RW         OR        0C2H                           ; enable destroy/rename/write
FA_CHG        LD        (GFIMLIAC),A
              LD        A,7
              LD        (GFIMLIPL),A
              LD        HL,SFIMLI
              CALL      PRODOS                         ; SET_FILE_INFO reuses parameter block
              PUSH      AF
              LD        A,10
              LD        (GFIMLIPL),A                   ; restore for next GET
              POP       AF
              CP        04EH
              JP        Z,ROFILE
              OR        A
              JR        NZ,FA_ERROR
              LD        L,A
              RET
FA_ERROR      LD        A,0FFH
              LD        L,A
              RET
ATTR_RO       DEFB      0

; CP/M 2.2 distinguishes file R/O from software drive R/O.
; Errors still return FF to the caller; they do NOT force a warm boot.
ROFILE        LD        DE,ROFTEXT
              JR        ROPRINT
RODISK        LD        DE,RODTEXT
ROPRINT       PUSH      DE
              LD        A,1
              LD        (ROERROR),A
              LD        DE,ROPTEXT
              CALL      C_WRITESTR
              LD        A,(RODRIVE)
              ADD       A,'A'
              LD        E,A
              CALL      C_WRITE
              POP       DE
              CALL      C_WRITESTR
              LD        E,13
              CALL      C_WRITE
              LD        A,(AXMODE)                     ; .COM running in AUX?
              OR        A
              JR        Z,ROPRET
              LD        A,1
              LD        (AXQUIT),A                     ; Abort transient through normal AUX gateway
ROPRET        LD        A,0FFH
              LD        L,A
              RET
RODRIVE       DEFB      0
ROERROR       DEFB      0
ROPTEXT       DEFM      'BDOS Err on '
              DEFB      '$'
ROFTEXT       DEFM      ': File R/O'
              DEFB      '$'
RODTEXT       DEFM      ': R/O'
              DEFB      '$'

; Shared error reporting for native TAB/TERM/SAVE services.
; Stage 27: removed unused code/data (Old resident argument counter).
CCPBAD        LD        DE,BFMSG
              CALL      C_WRITESTR
              LD        A,1
              OR        A
              RET

; ISWILD is retained for native SAVE filename validation.
ISWILD        LD        B,11
IWLOOP        LD        A,(HL)
              CP        '?'
              RET       Z
              INC       HL
              DJNZ      IWLOOP
              XOR       A
              RET
; Stage 27: removed unused code/data (Old resident wildcard error wrapper).
; Legacy MAIN built-in TYPE/SAVE wrappers removed (AUX implements both).

; Permanent scratch: main TPA is unused by auxiliary transients.
; Cached Apple II text row addresses for the software cursor.
; Apple 80-column row interleave. Z80 $F400 = Apple text $0400.
CUROWTAB      DEFW      0F400H,0F480H,0F500H,0F580H,0F600H,0F680H,0F700H,0F780H
              DEFW      0F428H,0F4A8H,0F528H,0F5A8H,0F628H,0F6A8H,0F728H,0F7A8H
              DEFW      0F450H,0F4D0H,0F550H,0F5D0H,0F650H,0F6D0H,0F750H,0F7D0H


              ORG       07800H
AXDMAP        DEFW      0080H
AXFCBP        DEFW      0
AXFN          DEFB      0
AXSTAT        DEFB      0
AXFCB         DEFS      36
AXSRCH        DEFS      36
AXDATA        DEFS      128
AXLIP         DEFW      0
AXLBUF        DEFS      260
AXLRESUME     DEFB      0                              ; set only on AXRETRY BDOS 10
AXBADFN       DEFB      0                              ; last AUX BDOS function for diagnostics
AXW5BUF       DEFS      3                              ; private MAIN staging for AUX W5100 writes
BDOSFN        DEFB      0                              ; last MAIN BDOS function for diagnostics

 ; MAIN-to-AUX-LC resident transition helper, entirely in ordinary MAIN RAM.
 ; ALTZP can switch without changing the instruction fetch at $7Axx.
              ORG       07A00H
AXSTART       LD        (AXMSP),SP                     ; called with MAIN RAM and main LC
              XOR       A
              LD        (AXQUIT),A
              INC       A
              LD        (AXMODE),A
              LD        A,(LCB2RW)
              LD        A,(LCB2RW)
              XOR       A
              LD        (ZPAUX),A
              JP        LCREN                          ; enter the AUX LC DF00h gateway
; Resume a parked BDOS return. Called from TABRESUM on the MAIN stack.
; The suspended stack frame in its AUX bank is still there.
AXCONT        LD        (AXMSP),SP
              XOR       A
              LD        (AXQUIT),A
              INC       A
              LD        (AXMODE),A
              JP        AXRETRY
AXGATE        LD        (AXASP),SP                     ; user's stack may itself be in AUX LC
              LD        SP,(AXMSP)                     ; restore main resident stack
              XOR       A
              LD        (ZPMAIN),A                     ; restore ProDOS's ZP and LC
              LD        A,(LCB1RO)
              CALL      AXIOSBD                        ; sync AUX 0003h before dispatch
              LD        (AXRES),A
              LD        (AXRHL),HL
              CALL      SCHTICK                        ; never schedules INSIDE a syscall
              LD        A,(AXQUIT)
              CP        3
              CALL      Z,TASKSAVE                     ; save before the CCP/other session runs
              LD        A,(AXQUIT)
              OR        A
              JR        NZ,AXFIN
AXGO          LD        A,(LCB2RW)
              LD        A,(LCB2RW)
              XOR       A
              LD        (ZPAUX),A                      ; executable LC image now AUX
              LD        SP,(AXASP)
              LD        HL,(AXRHL)
              LD        A,(AXRES)
              JP        LCRES                          ; LC shim restores RAMRD/RAMWRT AUX
AXFIN         JP        AXIOSFX                        ; plain RET/JP 0000h must sync too
; AXMODE is only 1 during AUX transient. SAVE executes outside it,
; with its temporary LC shim installed into MAIN LC instead of AUX LC.
LCPEEK        LD        A,(LCB2RW)
              LD        A,(LCB2RW)
              LD        A,(AXMODE)
              OR        A
              JR        Z,LPLOCAL
              LD        (ZPAUX),A
LPLOCAL       CALL      LCPEE0
              PUSH      AF
              XOR       A
              LD        (ZPMAIN),A
              LD        A,(LCB1RO)
              POP       AF
              RET
LCA2M         LD        A,(LCB2RW)
              LD        A,(LCB2RW)
              LD        A,(AXMODE)
              OR        A
              JR        Z,LMLOCAL
              LD        (ZPAUX),A
LMLOCAL       CALL      LCA2MR
              XOR       A
              LD        (ZPMAIN),A
              LD        A,(LCB1RO)
              RET
AXMSP         DEFW      0
AXASP         DEFW      0
AXRES         DEFB      0
AXRHL         DEFW      0
AXQUIT        DEFB      0
AXMODE        DEFB      0

; The physical clear below is ONLY for video backing-store initialization.
; User-facing CLS is now NCLS_RUN (configured-terminal escape output).
; Software cursor restore; installed in the free tail of $7A00 region.
; Hide the physical cursor before key delivery, TAB switching or
; drawing. The cached address works even after terminal state changes.
CUOFF         LD        A,(CUACTIVE)
              OR        A
              RET       Z
              PUSH      AF
              PUSH      HL
              XOR       A
              LD        (CUACTIVE),A
              LD        HL,0B82DH                       ; VCUROFF - 6502 physical restore
              LD        (ADDR),HL
              LD        A,1
              LD        (CMD),A
              LD        (SOFTCARD),A
              POP       HL
              POP       AF
              RET
; Select the correct physical Apple II text half (bank 0), not a
; background session's virtual HGR backing store.
CUMAP         CALL      VSPREP0
              XOR       A
              LD        (VS80ON),A
              LD        A,(CUHALF)
              OR        A
              JR        Z,CUMAUX
              LD        A,(VSPAGE1)
              JR        CUSEL
CUMAUX        LD        A,(VSPAGE2)
CUSEL         LD        HL,(CUADDR)
              RET
CUACTIVE      DEFB      0
CUHALF        DEFB      0
CUADDR        DEFW      0F400H
CUUNDER       DEFB      0A0H


              ORG       07B00H
CCPCLS        LD        HL,0B812H
              LD        (ADDR),HL
              LD        A,1
              LD        (CMD),A
              LD        (SOFTCARD),A
              RET

; CACHE prints three wrapping 16-bit hexadecimal counters. "CACHE RESET"
; clears them first, without closing cached files or affecting LRU order.
CCPCACHE      LD        A,(FILEBUF)
              OR        A
              JR        Z,CCSHOW
              CP        7                              ; normalized tail is " RESET "
              JP        NZ,CCPBAD
              LD        HL,FILEBUF+2
              LD        DE,CCRESET
              LD        B,5
CCCRLP        LD        A,(DE)
              CP        (HL)
              JP        NZ,CCPBAD
              INC       DE
              INC       HL
              DJNZ      CCCRLP
              CALL      CACHERST
CCSHOW        LD        DE,CCOPENMSG
              CALL      C_WRITESTR
              LD        HL,COPENS
              CALL      CCHEX16
              LD        DE,CCHITMSG
              CALL      C_WRITESTR
              LD        HL,CHITS
              CALL      CCHEX16
              LD        DE,CCEVMSG
              CALL      C_WRITESTR
              LD        HL,CEVICTS
              CALL      CCHEX16
              LD        E,13
              CALL      C_WRITE
              LD        E,10                           ; CACHE final newline for UC1
              JP        C_WRITE
; Print four uppercase hex digits (high byte then low byte).
CCHEX16       LD        A,(HL)
              PUSH      AF
              INC       HL
              LD        A,(HL)
              CALL      CCHEX8
              POP       AF
CCHEX8        PUSH      AF
              RRCA
              RRCA
              RRCA
              RRCA
              CALL      PHNYB
              POP       AF
              JP        PHNYB
CCRESET       DEFM      'RESET'
CCOPENMSG     DEFM      'Cache (hex): opens='
              DEFB      '$'
CCHITMSG      DEFM      ' hits='
              DEFB      '$'
CCEVMSG       DEFM      ' evictions='
              DEFB      '$'

CCPBANKS      JP        RWREPORT

; TAB n SUSPEND/RESUME/EXCLUSIVE operate on manually runnable state.
TB_PAUSE      LD        A,(SCHFG)
              CP        B
              JP        Z,TB_NOBG                      ; background only
              LD        A,B
              CALL      TB_HPTR
              LD        (HL),1
              RET
TB_UNPS       LD        A,B
              CALL      TBCLEARH
              RET
TB_NOBG       JP        UNIMP                          ; a foreground tab cannot be paused
TB_EXCL
              PUSH      BC                             ; LDIR consumes BC; B is target tab
              LD        HL,TBHOLD
              LD        DE,TBHOLD+1
              LD        BC,15
              LD        A,1
              LD        (HL),A
              LDIR
              POP       BC
              LD        A,B
              CALL      TBCLEARH
              LD        A,(TABMODE)
              CP        B
              JP        NZ,TB_SWITCH
              RET

              ORG       07C00H

; LC entry points are absolute RUNTIME addresses, not source image labels.
LCBASE        EQU       0DF00H
LCBACK        EQU       03000H                         ; MAIN $3000-$3FFF: saved MAIN LC bank2
LC_BDOS       EQU       LCBASE-0100H                    ; $DE00, below conventional BIOS at $DF00
SW80OFF       EQU       0E000H
RDMAIN        EQU       0E002H
RDAUX         EQU       0E003H
WRMAIN        EQU       0E004H
WRAUX         EQU       0E005H
ZPMAIN        EQU       0E008H
ZPAUX         EQU       0E009H
LCB2RW        EQU       0E083H
LCB1RO        EQU       0E088H

; Read records using an ordinary MAIN buffer, copy them to AUX.
; F_READ owns the file handle/FCB and is called BEFORE LC installation:
; ProDOS MLI must run with its normal language-card mapping.
AUXRUN        XOR       A
              LD        (AXQUIT),A                    ; never inherit an earlier tab's exit code
              LD        A,6
              LD        (AUXEXCD),A                   ; pessimistic: loader failure
              LD        DE,PATHBUF2
              LD        HL,PATHBUF2
              LD        (DMAADDR),HL
              CALL      _F_OPEN
              OR        A
              JR        Z,AUXFOUND
              LD        A,(CURDRV)
              AND       0F0H                           ; current user already 0?
              JP        Z,RCOERR
              LD        A,(CURDRV)
              LD        (UC_SAVE),A
              AND       00FH                           ; retry only executable lookup in user 0
              LD        (CURDRV),A
              LD        DE,PATHBUF2
              CALL      _F_OPEN
              PUSH      AF
              LD        A,(UC_SAVE)
              LD        (CURDRV),A
              POP       AF
              OR        A
              JP        NZ,RCOERR
AUXFOUND      CALL      SVNEWCHILD                    ; preserve valid SAVE snapshot on CCP reload
              ; The transient's RAM can now be in AUX bank 1 instead of
              ; the system/video bank 0. 6502 HANDLR temporarily uses bank
              ; zero for ALL MLI, keyboard and video requests.
              LD        A,(TABMODE)
              CALL      TABPHYS
              CALL      AXBANK
              ; Protect ProDOS MAIN LC only; AUX LC is application-owned.
              CALL      AXSNAP
              LD        HL,0100H
              LD        (AUXDEST),HL
AUXLOAD       LD        HL,AUXSTAGE
              LD        (DMAADDR),HL
              LD        DE,PATHBUF2
              CALL      F_READ
              OR        A
              JR        Z,AUXREC
              CP        1
              JR        Z,AUXLDONE
              JP        AUXRERR
AUXREC        LD        HL,(AUXDEST)
              LD        DE,LC_BDOS
              OR        A
              SBC       HL,DE
              JP        NC,AUX2BIG
              LD        HL,(AUXDEST)
              LD        DE,0B000H
              OR        A
              SBC       HL,DE
              JR        NC,AUXLCREC                    ; destination in AUX LC bank2
              LD        HL,AUXSTAGE
              LD        DE,(AUXDEST)
              LD        BC,0080H
              XOR       A
              LD        (WRAUX),A
              LDIR
              LD        (WRMAIN),A
              JR        AUXADV
AUXLCREC      LD        A,(LCB2RW)
              LD        A,(LCB2RW)
              XOR       A
              LD        (ZPAUX),A
              LD        HL,AUXSTAGE
              LD        DE,(AUXDEST)
              LD        BC,0080H
              LDIR                                     ; MAIN src -> AUX LC destination
              LD        (ZPMAIN),A
              LD        A,(LCB1RO)
AUXADV        LD        HL,(AUXDEST)
              LD        DE,0080H
              ADD       HL,DE
              LD        (AUXDEST),HL
              JP        AUXLOAD
AUXRERR       LD        DE,PATHBUF2
              CALL      F_CLOSE
              CALL      AXREST
              XOR       A
              CALL      AXBANK
              JP        RCLERR
AUX2BIG       LD        DE,PATHBUF2
              CALL      F_CLOSE
              CALL      AXREST
              XOR       A
              CALL      AXBANK
              JP        AUXSIZEERR
AUXLDONE      LD        DE,PATHBUF2
              CALL      F_CLOSE
              OR        A
              JP        NZ,AUXRERR0
              LD        HL,FILEBUF
              LD        (DMAADDR),HL
              LD        HL,0080H
              LD        (AXDMAP),HL
              ; Install DE00 BDOS stub and DF00 BIOS gateway in AUX LC.
              LD        A,(LCB2RW)
              LD        A,(LCB2RW)
              XOR       A
              LD        (ZPAUX),A
              LD        HL,LCBDJP                      ; three-byte BDOS jump at $DE00
              LD        DE,LC_BDOS
              LD        BC,3
              LDIR
              LD        HL,LCIMG
              LD        DE,LCBASE
              LD        BC,LCLEN
              LDIR
              LD        (ZPMAIN),A
              LD        A,(LCB1RO)
              ; The helper can now fetch AUX RAM safely from AUX LC.
              LD        A,1
              LD        (AXMODE),A
              LD        HL,IOBYTE                      ; CP/M applications also see IOBYTE at 0003
              LD        DE,IOBYTE
              LD        BC,1
              CALL      AXM2A
              LD        HL,0F800H
              LD        DE,02000H
              LD        BC,0800H
              CALL      LCA2M
              LD        HL,0F300H
              LD        DE,02800H
              LD        BC,16
              CALL      LCA2M
              ; Restore the known-working page-zero copy. The SoftCard
              ; translates these Z80 addresses into Apple II $1000..$10FF,
              ; where RAMWRT=AUX selects the current RamWorks bank.
              LD        HL,0000H
              LD        DE,0000H
              LD        BC,0100H
              XOR       A
              LD        (WRAUX),A
              LDIR
              LD        HL,AUXPZERO
              LD        DE,0000H
              LD        BC,3
              LDIR
              LD        HL,AUXPZERO+5
              LD        DE,0005H
              LD        BC,3
              LDIR
              LD        (WRMAIN),A
              ; Refresh Apple CP/M BASIC's terminal table in AUX $0396.
              LD        HL,0F396H
              LD        DE,0F396H
              LD        BC,9
              CALL      AXM2A
              CALL      TBEXE                          ; remember the launched .COM name
              LD        A,(CURDRV)
              PUSH      AF
              CALL      AXSTART
              POP       AF
              CALL      SHDRKEEP                       ; keep AUX CCP's drive on F7 chain
              LD        A,(AXQUIT)
              CP        3
              JP        Z,AUXSUSP                      ; do NOT destroy the parked AUX LC image
              CALL      CACHEALL                       ; AUX termination also closes/flushed files
              LD        A,(AXQUIT)
              LD        (AUXEXCD),A
              ; Restore AUX low metadata (virtual DPB/ALV are not persistent).
              LD        HL,02000H
              LD        DE,0F800H
              LD        BC,0800H
              CALL      AXM2A
              LD        HL,02800H
              LD        DE,0F300H
              LD        BC,16
              CALL      AXM2A
              ; Retain this tab's completed AUX LC (and ordinary AUX TPA).
              ; Only ProDOS's MAIN LC needs restoring.
              CALL      AXMAINLC
              CALL      SVFLPTR
              LD        (HL),1
              XOR       A
              CALL      AXBANK                         ; CCP/ProDOS return to bank 0
              LD        HL,FILEBUF
              LD        (DMAADDR),HL
              LD        A,(AUXEXCD)
              CP        2
              JR        NZ,AUXEXOK
              LD        DE,AUXBADMSG
              CALL      C_WRITESTR
              LD        A,(AXBADFN)
              LD        C,A
              CALL      PRHEX                          ; original call in [XX] format
; A finished .COM may leave Soroc's write-protect/inverse mode active,
; or leave an unfinished terminal escape sequence in the 6502 renderer.
; Reset ONLY this session's terminal state, without clearing the display.
; Do not do this at AUXSUSP: parked programs must keep their attributes.
AUXEXOK       PUSH      IX
              CALL      TABPICK
              LD        A,(IX+6)                      ; preserve VT100/Soroc/H19 personality
              CALL      TMSET                         ; reset Z80 parser + 6502 VATTR/VSTATE
              POP       IX
              CALL      VSSTSAVE                      ; commit neutral terminal state for this tab
              CALL      NCEXCR                          ; don't print to a dead remote socket
              NOP
              NOP                                      ; same 5 bytes as old LD E / CALL
              LD        A,(AUXEXCD)
              CP        1                              ; AUX BDOS 0 -> normal warm boot
              RET       NZ
              CALL      SHPTR
              LD        A,(HL)
              OR        A
              RET       NZ                             ; CCP supervisor will reload CCP
              JP        BDOSWARM
; Returning to the CCP after Ctrl-] must not restore the old AUX LC:
; the parked transient, including its LC gateway, lives in that bank.
AUXSUSP       CALL      CACHEALL
              CALL      AXMAINLC                       ; restore ProDOS MAIN LC, keep AUX LC
              XOR       A
              CALL      AXBANK                         ; 6502/video service bank 0
              ; Backing display is live; no snapshot at suspension.
              LD        HL,FILEBUF
              LD        (DMAADDR),HL
              LD        HL,0080H
              LD        (AXDMAP),HL
              RET
AUXRERR0      CALL      AXREST
              XOR       A
              CALL      AXBANK
              JP        RCLERR

; Protect ProDOS's MAIN LC bank2 at $B000-$BFFF only.  AUX LC is
; owned by the currently selected RamWorks tab and remains untouched.
AXSNAP        DI
              XOR       A
              LD        (SW80OFF),A
              LD        (ZPMAIN),A
              LD        (RDMAIN),A
              LD        (WRMAIN),A
              LD        A,(LCB2RW)
              LD        A,(LCB2RW)
              LD        HL,0B000H
              LD        DE,LCBACK
              LD        BC,01000H
              LDIR
              LD        A,(LCB1RO)
              RET
; Error paths must still restore ProDOS's MAIN LC.
AXREST        JP        AXMAINLC

; Restore original 4K MAIN LC bank2 after AUX exit or suspension.
AXMAINLC      LD        A,(LCB2RW)
              LD        A,(LCB2RW)
              LD        HL,LCBACK
              LD        DE,0B000H
              LD        BC,01000H
              LDIR
              LD        A,(LCB1RO)
              RET

AUXBDOS       JP        AXBDOS
AUXBDOS0      LD        A,1
              LD        (AXQUIT),A
              XOR       A
              LD        L,A
              RET
ABDVER        LD        HL,0022H
              LD        A,L
              LD        B,H
              RET
AUXBDOS2      PUSH      DE
              CALL      C_WRITE
              POP       DE
              LD        A,E
              LD        L,A
              RET
AUXBDOS6      LD        A,E
              CP        0FFH
              JR        NZ,AB6OUT                      ; control-character output is not input
AB6IN         CALL      UC6FG                          ; UC1 bypasses physical-screen foreground check
              JR        Z,AB6KEY
              XOR       A
              LD        L,A
              RET
; Stage 28.6: new CCP nonblocking editor uses the same kernel
; cursor as other console input.  Call replaces CALL TSKKEY byte-for-byte.
AB6KEY        CALL      C_RAWIO
              CALL      UC6CUR                         ; UC1: no physical cursor; CRT: original AB6CUR
              RET       NC                             ; same BDOS 6 return contract
              LD        A,0F6H                         ; deferred BDOS 6 poll
              LD        L,A
              RET
AB6OUT        JP        C_RAWIO
ABDSTAT       LD        A,(IOBYTE)
              AND       3
              CP        1
              JP        NZ,IOSTAT                       ; UC1 status, others remain zero
              JP        TSKSTAT                        ; CRT: Open Apple aware
AUXBDOS9      PUSH      BC
              PUSH      DE
              PUSH      HL
              EX        DE,HL
AB9NEXT       CALL      LCPEEK
              CP        '$'
              JR        Z,AB9DONE
              PUSH      HL
              LD        E,A
              CALL      C_WRITE
              POP       HL
              INC       HL
              JR        AB9NEXT
AB9DONE       POP       HL
              POP       DE
              POP       BC
              XOR       A
              LD        L,A
              RET


TL_BLOCK      DEFM      ' [Blocked]$'

              ORG       07EC0H
; Stage 1 scheduler helpers in unused MAIN $7EC0-$7FFF.
; Keep clear of the resident BDOS, which now reaches roughly $9760.
; Foreground runs original VSETMODE; background remembers the mode.
SCHTMCHK      LD        A,E
              CP        3                              ; 0 VT100, 1 Soroc, 2 H19
              JP        NC,AXTMERR
              JP        AXTMRUN                        ; per-task 6502 mode is now virtual

; Basic six-byte per-session BDOS state without touching 6502 VMODE.
; TASKSAVE/TASKLOAD already handle each program's DMA and register state.
SCHSAVE       CALL      TABPICK
              LD        A,(CURDRV)
              LD        (IX+0),A
              LD        A,(IOBYTE)
              LD        (IX+1),A
              LD        HL,(LOGVEC)
              LD        (IX+2),L
              LD        (IX+3),H
              LD        HL,(ROVEC)
              LD        (IX+4),L
              LD        (IX+5),H
              RET
SCHLOAD       CALL      TABPICK
              LD        A,(IX+6)
              LD        (VTMODEC),A                   ; cooperative task switch
              LD        A,(IX+0)
              LD        (CURDRV),A
              LD        A,(IX+1)
              LD        (IOBYTE),A
              LD        L,(IX+2)
              LD        H,(IX+3)
              LD        (LOGVEC),HL
              LD        L,(IX+4)
              LD        H,(IX+5)
              LD        (ROVEC),HL
              RET

; Save a background terminal personality without changing the visible
; application's 6502 terminal parser state.
SCHTERM       PUSH      AF
              CALL      SCHISFG
              JR        NZ,STBG
              POP       AF
              OR        A
              RET
STBG          POP       AF
              PUSH      BC
              PUSH      DE
              PUSH      IX
              PUSH      AF
              CALL      TABPICK
              POP       AF
              LD        (IX+6),A
              LD        (VTMODEC),A                   ; TERM in background task
              POP       IX
              POP       DE
              POP       BC
              XOR       A
              LD        L,A
              SCF
              RET

; Z flag: this task owns foreground screen/keyboard.
SCHISFG       PUSH      BC
              LD        A,(TABMODE)
              LD        B,A
              LD        A,(SCHFG)
              CP        B
              POP       BC
              RET

; Mark current session as blocked on input. Both original foreground
; hotkey deferrals and new background input deferrals use this state.
SCHBLCK       LD        A,(TABMODE)
              LD        E,A
              LD        D,0
              LD        HL,SCHWAIT
              ADD       HL,DE
              LD        (HL),1
              RET

; Reactivate a task blocked on background console input when selected.
SCHWAKE       LD        A,(TABMODE)
              LD        E,A
              LD        D,0
              LD        HL,SCHWAIT
              ADD       HL,DE
              LD        (HL),0
              RET

; The virtual display is live, so no physical screen snapshot is needed
; when an application yields or a manual tab change is requested.
; Stage 27: removed unused code/data (Unused screen snapshot stub).
; Stage 3: defer blocking console reads if this task is in the
; background, OR if this is the foreground and another task can run
; while waiting for a keystroke. A physical key already pending may
; be consumed normally. With no other runnable task use VGET, which
; preserves the ordinary visible cursor behaviour.
; The existing AXRETRY markers re-enter the original read on resume.
SCHPRE        JP        NCPRE                         ; same length as original LD A,(IOBYTE)
              AND       3
              CP        1
              JR        NZ,SPNO                        ; serial firmware input cannot keyboard-defer
              LD        A,C
              CP        1                              ; BDOS 1 cooked input
              JR        Z,SPREAD
              CP        10                             ; BDOS 10 line input (at line start)
              JR        Z,SPREAD
              CP        0F2H                           ; BIOS CONIN via LC gateway
              JR        NZ,SPNO
SPREAD        CALL      SCHISFG
              JR        NZ,SPPARKCODE                  ; background: always defer input
              PUSH      BC
              CALL      SCHHAVE
              OR        A
              JR        Z,SPALLOW                      ; no runnable background work
              CALL      BIOSCONST                      ; $C000 peek; never consumes keyboard
              OR        A
              JR        NZ,SPALLOW                     ; a character is already waiting
              POP       BC
SPPARKCODE    LD        A,C
              CP        1
              JR        Z,SPCOOK
              CP        10
              JR        Z,SPLINE
              JR        SPBIOS                         ; validated only 1/10/F2 above
SPALLOW       POP       BC
SPNO          OR        A                              ; clear carry
              RET
SPCOOK        LD        A,0F1H
              JR        SPPARK
SPBIOS        LD        A,0F2H
              JR        SPPARK
SPLINE        LD        (AXLIP),DE
              LD        A,0FAH
SPPARK        PUSH      AF
              PUSH      DE
              CALL      SCHBLCK
              LD        A,3
              LD        (AXQUIT),A
              POP       DE
              POP       AF
              LD        L,A
              SCF
              RET

; Trigger only at an outer AUX BDOS/BIOS completion in AXGATE.
; AXQUIT=3 follows the preexisting TASKSAVE -> AUXSUSP/TABRESUM route.
SCHTICK       LD        A,(AXQUIT)
              OR        A
              RET       NZ
              LD        A,(SCHEN)
              OR        A
              RET       Z
              ; Sample OA hotkeys at EVERY completed AUX BDOS/BIOS call.
              ; Only a valid hotkey queues a cooperative switch; ordinary
              ; keys are left in $C000 for the foreground application.
              CALL      SCHHOT
              LD        A,(AXQUIT)                     ; hotkey requested a switch?
              OR        A
              RET       NZ
              LD        A,(SCHQLEFT)
              DEC       A
              LD        (SCHQLEFT),A
              RET       NZ
              LD        A,SCHFGQ
              LD        (SCHQLEFT),A
              CALL      SCHISFG
              JR        NZ,STYIELD                     ; background must release CPU
              CALL      SCHHAVE
              OR        A
              RET       Z                              ; no background work: stay in .COM
STYIELD       LD        A,3
              LD        (AXQUIT),A
              RET


; Stage 2: keep 6502 parser/cursor state coherent across scheduler
; and manual TAB switches. VSMETAS retains the nine original bytes.
; MAIN $8000-$80FF: per-tab terminal state helpers before BIOS $8100.
; Stage 27: removed unused code/data (Unused legacy help text).
              ORG       08000H
VSSTSAVE      LD        A,(VSOK)
              OR        A
              RET       Z
              CALL      VSMETA
              LD        (HL),1                         ; initialized backing display
              INC       HL
              EX        DE,HL
              LD        HL,(VSPTR)
              LD        BC,VSTLEN
              LDIR
              RET

VSSTLOAD      LD        A,(VSOK)
              OR        A
              RET       Z
              CALL      VSMETA
              LD        A,(HL)
              INC       HL
              OR        A
              JR        Z,VSTNEW
              LD        DE,(VSPTR)
              LD        BC,VSTLEN
              LDIR
              RET
VSTNEW        LD        DE,(VSPTR)
              LD        HL,VSDEFAULT
              LD        BC,VSTLEN
              LDIR
              RET
VSDEFAULT     DEFB      0,0,0,0,1,0,0,0,0              ; cursor 0,0 and Soroc

; B821: A=snapshot bank, X=physical flag, Y=offset. 6502 updates routing
; and Microsoft BASIC's current terminal control-byte table.
VSSELECT      PUSH      BC
              CALL      VSSBANK                        ; bank 2 / 5 / 10 / 15
              LD        (AREG),A
              CALL      SCHISFG
              LD        A,0
              JR        NZ,VSSEBG
              INC       A
VSSEBG        LD        (XREG),A                       ; physical output enabled when fg
              LD        A,(TABMODE)
              AND       3
              ADD       A,A
              ADD       A,A
              ADD       A,A
              ADD       A,01CH                         ; high-byte delta from $0400
              LD        (YREG),A
              LD        HL,VTASK
              LD        (ADDR),HL
              LD        A,1
              LD        (CMD),A
              LD        (SOFTCARD),A
              POP       BC
              RET


              ORG       BDOSADDR

; CP/M 2.2 BIOS jump table (17 entries, three bytes each).
; Applications discover the BIOS WBOOT entry from the 16-bit operand
; at 0001H. The following three JP instructions must be CONST, CONIN,
; CONOUT in that order; TE_APPLE.COM copies exactly those nine bytes.
; Keep this table contiguous. The disk-sector entries are safe stubs,
; NOT a ProDOS block/sector BIOS (BP/M files continue through BDOS).
BIOS          JP        BDOSINIT                       ; BOOT    +00H
BIOSWBOOT     JP        BDOSWARM                       ; WBOOT   +03H
BIOSCSTAT     JP        BIOSCONST                      ; CONST   +06H
BIOSCKBD      JP        BIOSCONIN                      ; CONIN   +09H
BIOSCTTY      JP        BIOSCONOUT                     ; CONOUT  +0CH
              JP        BIOSLIST                       ; LIST    +0FH
              JP        BIOSPUNCH                      ; PUNCH   +12H
              JP        BIOSRDR                        ; READER  +15H
              JP        BIOSHOME                       ; HOME    +18H
              JP        BIOSSELDSK                     ; SELDSK  +1BH
              JP        BIOSSETTRK                     ; SETTRK  +1EH
              JP        BIOSSETSEC                     ; SETSEC  +21H
              JP        BIOSSETDMA                     ; SETDMA  +24H
              JP        BIOSREAD                       ; READ    +27H
              JP        BIOSWRITE                      ; WRITE   +2AH
              JP        BIOSLSTST                      ; LISTST  +2DH
              JP        BIOSSECTRAN                    ; SECTRAN +30H

; Public BDOS entry must be in the FIRST page of resident memory.
; MESCC-based .COM programs (including TE_APPLE.COM) calculate their
; stack top by rounding down the address at CP/M $0006 to a page
; boundary. An address in $82xx would place SP at $8200 INSIDE BP/M!
; 17 BIOS JP vectors = 51 bytes, so this is $8100 + $33 = $8133.
BDOSENTRY     JP        BDOSIMP

; Fixed exit/resume point at $8136, immediately after the $8133 BDOS JP.
; The Z80 is *suspended*, not reset, when CMD=0 switches to the 6502.
; On a later ProDOS launch the new image resumes at the instruction after
; LD (SOFTCARD),A. Jump via the freshly reloaded cold vector at $0000.
; Keep this stub at $8136 in future releases (BIOS ABI + 3-byte BDOS JP).
BYERESUME     LD        (SOFTCARD),A                   ; CCPBYE already set CMD=0 and A=0
              JP        0000H                          ; Execute only after ProDOS relaunch

; CP/M BIOS console: unlike the cooked BDOS C_READ, CONIN does not
; echo or treat Ctrl-C specially. CONOUT takes its byte in C, and
; must not suppress LF at the Z80 layer (C_WRITE deliberately does).
; Neither routine touches the alternate Z80 register set.
BIOSCONST     LD        A,(IOBYTE)
              AND       3
              CP        1                              ; CRT uses physical keyboard latch
              JP        NZ,IOSTAT                      ; ROM input has no portable nonblock status
              LD        A,3                            ; 6502 keyboard peek
              LD        (CMD),A
              LD        (SOFTCARD),A
              LD        A,(AREG)
              OR        A
              RET       Z
              LD        A,0FFH                         ; CP/M CONST: FF=ready, 00=not
              RET

BIOSCONIN     LD        A,(IOBYTE)
              AND       3
              CP        1
              JP        NZ,IOCONIN                     ; BAT uses selected RDR:, TTY/UC1 serial
              PUSH      HL
              LD        HL,RDKEY                       ; VGET waits but doesn't echo
              LD        (ADDR),HL
              LD        A,1
              LD        (CMD),A
              LD        (SOFTCARD),A
              LD        A,(AREG)
              AND       7FH                            ; 6502 keyboard sets bit 7
              POP       HL
              RET

BIOSCONOUT    PUSH      DE                             ; C contains character
              PUSH      HL
              LD        E,C
              CALL      C_RAWPUT                       ; Uncooked output to VRAWPUT
              POP       HL
              POP       DE
              RET

; Physical CP/M BIOS device entry points (also called through AUX LC).
BIOSLIST      LD        E,C
              JP        IOLIST
BIOSPUNCH     LD        E,C
              JP        IOPUNCH
BIOSRDR       JP        IOREADER
; Firmware has no standardized ready query. Blocking writes assumed ready.
BIOSLSTST     LD        A,0FFH
              RET

; Sector BIOS is deliberately unimplemented: don't tell applications
; that reads or writes succeeded when no data was transferred.
; BDOS's existing ProDOS file-based interface remains unchanged.
BIOSHOME      RET
BIOSSELDSK    LD        HL,0000H                       ; no sector-level DPH available
              RET
BIOSSETTRK    RET
BIOSSETSEC    RET
BIOSSETDMA    LD        (DMAADDR),BC
              RET
BIOSREAD      LD        A,1                            ; error, not success
              RET
BIOSWRITE     LD        A,1                            ; error, not success
              RET
BIOSSECTRAN   LD        H,B                            ; identity mapping
              LD        L,C
              RET

; Entry at 0000H is a COLD start only until the first initialization.
; Repoint its JP operand to the real BIOS WBOOT jump (BIOS+3),
; so CP/M applications can discover CONST/CONIN/CONOUT via (0001H).
; Subsequent RST 0 / JP 0000H runs an ordinary warm boot.
BDOSINIT      DI
              LD        SP,STCKTOP                     ; Valid stack for BPMSIGN
              ; Set CON=CRT before BPMSIGN/RWREPORT print anything.
              ; Otherwise reset value 00H routes the boot banner to S2.
              LD        A,095H
              LD        (IOBYTE),A
              ; Cold start: the backing ProDOS unit has not been resolved yet.
              ; WBOOT deliberately preserves the cached unit.
              XOR       A
              LD        (VUCVALID),A
              LD        (CURDRV),A                     ; cold boot only: drive A:, user 0
              LD        HL,0001H
              LD        (LOGVEC),HL                    ; cold boot: A: initially logged in
              CALL      SVCLEAR                        ; reset all 16 tab-specific SAVE flags
              LD        HL,SBWARM
              LD        DE,SBWARM+1
              LD        BC,15
              XOR       A
              LD        (HL),A
              LDIR                                     ; clear per-tab pending WBOOT flags
              LD        (TABMODE),A                    ; cold boot starts in session 0
              LD        (XSFLAG),A                     ; cold boot clears native XSUB
              LD        (XSLEFT),A
              LD        (SBFROM),A
              CALL      TABINIT                        ; reset both CCP session descriptors
              CALL      TSKINIT                        ; discard suspended programs on cold boot
              CALL      CACHERST                       ; zero cache counters on cold start only
              LD        HL,BIOSWBOOT
              LD        (0001H),HL                     ; 0000H -> BIOS WBOOT JP (CP/M ABI)
              CALL      BPMSIGN
              CALL      SHBOOTREPORT                   ; display banks, arm one-shot tab 0 startup

; Warm-boot path for BDOS 0, RST 0, JP 0000H and Ctrl-C.
; Keep the existing BDOS reset semantics, but do not print BPMSIGN.
BDOSWARM      DI                                       ; Make sure interrupts are off
              LD        SP,STCKTOP                     ; Discard transient's stack
              CALL      SHPTR
              LD        (HL),0                         ; WBOOT clears previous AUX shell state
              XOR       A
              LD        (SBHALT),A                     ; recheck $$$.SUB on a new warm boot
              CALL      SBWCLR                         ; consume current tab's WBOOT request

              ; Applications such as Apple CP/M MBASIC 5.2 replace the
              ; warm-start address at $0001 with an address in the TPA.
              ; CP/M WBOOT must restore the page-zero system jump vectors.
              ; $0000: JP BIOSWBOOT, $0005: JP BDOSENTRY.
              LD        A,0C3H                         ; Opcode for JP absolute
              LD        (0000H),A
              LD        (0005H),A
              LD        HL,BIOSWBOOT
              LD        (0001H),HL
              LD        HL,BDOSENTRY
              LD        (0006H),HL

              ; WBOOT preserves IOBYTE, current drive/user, and LOGVEC.
              ; Only a cold boot initializes these session-owned values.
              XOR       A
              LD        (FILEBUF),A                    ; Zero chars in command tail
              CALL      CACHEALL                       ; CLOSE ALL, invalidate cache and all FRN slots
              LD        HL,FILEBUF                     ; Initialize DMAADDR to 0080H
              LD        (DMAADDR),HL                   ; ...
              LD        HL,0000H                       ; No drives write protected
              LD        (ROVEC),HL                     ; ...
              JP        SHBOOTENTRY                    ; start AUX shell after WBOOT setup

; The TPA is AUX 0100H..DDFFH. Derive KiB from its top at
; assembly time, then turn it into decimal at run time. 10 right shifts
; convert a byte count to KiB; valid for any sensible BDOS placement.
; We print two digits (CP/M's TPA cannot exceed 63 KiB).
BPMSIGN       LD        DE,BPMSG
              CALL      C_WRITESTR
              LD        HL,LC_BDOS
              LD        B,10
BPMSHIFT      SRL       H
              RR        L
              DJNZ      BPMSHIFT
              LD        A,L
              LD        B,'0'
BPMTENS       CP        10
              JR        C,BPMDIGITS
              SUB       10
              INC       B
              JR        BPMTENS
BPMDIGITS     PUSH      AF
              LD        E,B
              CALL      C_WRITE
              POP       AF
              ADD       A,'0'
              LD        E,A
              CALL      C_WRITE
              LD        DE,BPMSUFF
              JP        C_WRITESTR

BPMSG         DEFB      13
              DEFM      'BP/M AUX TPA '
              DEFB      '$'
BPMSUFF       DEFM      'K'
              DEFB      13,'$'

BDOSIMP
;;          CALL    PRHEX           ; Print sys call number

              LD        A,C                            ; Prepare to check C is in range
              LD        (BDOSFN),A                     ; preserve function before SLA C / vector lookup
              CP        41                             ; Max syscall# for CP/M 2.2 is 40
              JP        NC,BDOSUNSP                    ; unsupported function; report it
              LD        HL,BDOSVEC                     ; Start of vector table
              SLA       C                              ; Multiply C by 2
              LD        B,0                            ; MSB of BC is zero
              ADD       HL,BC                          ; Address of vector in HL
              LD        C,(HL)                         ; Read LSB of address to jump to
              INC       HL                             ; Read MSB of address to jump to
              LD        H,(HL)                         ; ...
              LD        L,C                            ; Address needs to be in HL
              JP        (HL)                           ; Jump to it!

; Vector table
BDOSVEC       DEFW      C_TERMCPM                      ; C=00H
              DEFW      C_READ                         ; C=01H
              DEFW      C_WRITE                        ; C=02H
              DEFW      IOREADER                       ; C=03H  RDR:
              DEFW      IOPUNCH                        ; C=04H  PUN:
              DEFW      IOLIST                         ; C=05H  LST:
              DEFW      C_RAWIO                        ; C=06H
              DEFW      GET_IOB                        ; C=07H
              DEFW      SET_IOB                        ; C=08H
              DEFW      C_WRITESTR                     ; C=09H
              DEFW      C_READSTR                      ; C=0AH
              DEFW      C_STAT                         ; C=0BH
              DEFW      S_BDOSVER                      ; C=0CH
              DEFW      DRV_ALLRST                     ; C=0DH
              DEFW      DRV_SET                        ; C=0EH
              DEFW      F_OPEN                         ; C=0FH
              DEFW      F_CLOSE                        ; C=10H
              DEFW      F_SFIRST                       ; C=11H
              DEFW      F_SNEXT                        ; C=12H
              DEFW      F_DELETE                       ; C=13H
              DEFW      F_READ                         ; C=14H
              DEFW      F_WRITE                        ; C=15H
              DEFW      F_MAKE                         ; C=16H
              DEFW      F_RENAME                       ; C=17H
              DEFW      DRV_LOGVEC                     ; C=18H
              DEFW      DRV_GET                        ; C=19H
              DEFW      F_DMAOFF                       ; C=1AH
              DEFW      DRV_AVEC                       ; C=1BH
              DEFW      DRV_SETRO                      ; C=1CH
              DEFW      DRV_ROVEC                      ; C=1DH
              DEFW      F_ATTRIB                       ; C=1EH  (F_ATTRIB)
              DEFW      DRV_DPB                        ; C=1FH
              DEFW      F_USERNUM                      ; C=20H
              DEFW      F_READRAND                     ; C=21H
              DEFW      F_WRITERAND                    ; C=22H
              DEFW      F_SIZE                         ; C=23H
              DEFW      F_RANDREC                      ; C=24H
              DEFW      DRV_RESET                      ; C=25H
              DEFW      BDOSUNSP                       ; C=26H  (*nothing* in CP/M 2.2)
              DEFW      BDOSUNSP                       ; C=27H  (*nothing* in CP/M 2.2)
              DEFW      F_WRITERAND                    ; C=28H  (F_WRITEZF)

; Diagnose unknown MAIN BDOS calls; retain old UNIMP bell afterwards.
BDOSUNSP      LD        DE,BDOSMSG
              CALL      C_WRITESTR
              LD        A,(BDOSFN)
              LD        C,A
              CALL      PRHEX
              LD        E,13
              CALL      C_WRITE
              JP        UNIMP

; Unimplemented BDOS call, just ring the bell
UNIMP         LD        HL,BELL                        ; We are going to call BELL
              LD        (ADDR),HL                      ; ...
              LD        A,1                            ; CMD=1 means call 6502 sub
              LD        (CMD),A                        ; ...
              LD        (SOFTCARD),A                   ; Do it!
              RET                                      ; Return to calling program

; System reset.  Jump to $0000 - doesn't return
C_TERMCPM     RST       0                              ; Quick jump to zero

; Wait for a character from the console, return it in A and L
; Also echoes the char to the console
C_READ        LD        A,(IOBYTE)
              AND       3
              CP        1
              JP        NZ,IOCCOOK                     ; redirected console, serial firmware
              LD        HL,RDKEY                       ; We are going to call RDKEY
              LD        (ADDR),HL                      ; ...
              LD        A,1                            ; CMD=1 means call 6502 sub
              LD        (CMD),A                        ; ...
              LD        (SOFTCARD),A                   ; Do it!
              LD        A,(AREG)                       ; Grab the return value
              CP        83H                            ; See if it is Ctrl-C
              JP        Z,BDOSWARM                     ; Ctrl-C is a warm boot (no banner)
              PUSH      AF                             ; Preserve A (and F)
              LD        HL,COUT                        ; Echo the character using COUT
              LD        (ADDR),HL                      ; ...
              LD        A,1                            ; CMD=1 means call 6502 sub
              LD        (CMD),A                        ; ...
              LD        (SOFTCARD),A                   ; Do it!
              POP       AF                             ; Restore A (and F)
              AND       7FH                            ; Mask high bit
              LD        L,A                            ; Copy A to L
              RET                                      ; Return to calling program

; BDOS console output.  The 6502 driver handles tabs, CR, backspace,
; clear-screen and the other minimal console controls.  Ignore LF because
; the direct video driver's CR already moves to the next line.
C_WRITE       LD        A,(IOBYTE)
              AND       3
              CP        1
              JR        NZ,C_RAWPUT                    ; serial/BAT must retain LF
              LD        A,E
              CP        0AH
              JR        NZ,C_PUT
              CALL      VTISEN                         ; only native Soroc swallows LF
              CP        1
              RET       Z                              ; VT100 and H19 process cooked LF
              JR        C_PUT

; Shared low-level output path for cooked and direct console writes.
; E = ASCII character; 6502 console driver accepts bit 7 set or clear.
C_RAWPUT      LD        A,(IOBYTE)
              AND       3
              CP        1
              JP        NZ,IOCONOUT                    ; redirected console bypasses screen driver
              LD        A,E                            ; raw output also updates virtual display
              AND       07FH                           ; preserve distinction from cooked BDOS
              LD        HL,RAWOUT                      ; B80F raw 6502 vector
              JR        VTGATE
C_PUT         LD        A,80H                          ; cooked output, both background/foreground
              OR        E
              LD        HL,COUT                        ; B803 cooked 6502 vector
VTGATE        PUSH      AF                             ; retain raw/cooked flag in bit 7
              PUSH      HL
              CALL      VTISEN                         ; 1=native Soroc, 0/2=translated
              CP        1
              JR        Z,VTNOGATE                     ; preserve saved output/flags
              POP       HL
              POP       AF
              JP        VTCHAR                         ; parse VT before 6502 handoff
VTNOGATE      POP       HL
              POP       AF
              JR        C_SENDA
; Step 3: CP/M terminal ^S/^Q output flow control.  All BDOS and
; BIOS console output passes through C_SENDA (cooked and raw).
; Only foreground output polls the keyboard.  Preserve a pending
; ordinary key; consume ^S/^Q, which applications must not see.
; Stage 28.7: BDOS 6 also polls for ^C during DIR/TYPE.  That polling
; can leave CUON's reverse-video cursor covering the next output cell.
; Remove it BEFORE sending any output, otherwise CUOFF later restores
; its old background byte over a character written by DIR.
; Only remap AUX on the uncommon path where a cursor was active.
C_SENDA       PUSH      AF                             ; A is the character being sent
              PUSH      HL                             ; HL is the 6502 output vector
              CALL      CSOUTPRE                       ; compact: same size as Stage 28.6
              POP       HL
              POP       AF
              LD        (AREG),A
              LD        (ADDR),HL
              LD        A,1
              LD        (CMD),A
              LD        (SOFTCARD),A
              RET

; Read Apple II $C000 keyboard latch from SoftCard Z80 $E000.
; Reading $C010 ($E010 to Z80) clears the keyboard strobe.
; Do not consume any other waiting key while output is running.
CFO_CHECK     CALL      SCHISFG                        ; background tasks must not take input
              RET       NZ
CFO_POLL      LD        A,(0E000H)                     ; physical $C000 (key + strobe)
              OR        A
              RET       P                              ; bit 7 clear: no key pending
              AND       07FH
              CP        013H                           ; ^S: stop output
              JR        Z,CFO_STOP
              CP        011H                           ; ^Q without ^S: discard quietly
              RET       NZ                             ; other keys belong to the application
              LD        A,(0E010H)                     ; consume ^Q
              RET
CFO_STOP      LD        A,(0E010H)                     ; consume ^S
CFO_WAIT      LD        A,(0E000H)
              OR        A
              JP        P,CFO_WAIT                     ; no key: remain paused
              AND       07FH
              CP        011H
              JR        Z,CFO_GO
              LD        A,(0E010H)                     ; discard other keys while paused
              JR        CFO_WAIT
CFO_GO        LD        A,(0E010H)                     ; consume ^Q and resume this output
              RET

; CP/M BDOS function 6: E=FF nonblocking read, else raw output.
; This route uses the raw 6502 entry (CR and LF independent).
C_RAWIO       LD        A,E
              CP        0FFH
              JR        Z,RIS1
              JR        C_RAWPUT

              ; If character is waiting, read from console & return in A
              ; Otherwise, return 00H in A
RIS1          LD        A,(IOBYTE)
              AND       3
              CP        3
              JP        Z,UC6IN                         ; UC1 BDOS 06 input
              CP        1
              JP        NZ,IOZERO                      ; no portable slot-2 nonblocking read
              LD        A,3                            ; CMD=3 means peek at keyboard
              LD        (CMD),A                        ; ...
              LD        (SOFTCARD),A                   ; Do it
              LD        A,(AREG)                       ; Grab the return value
              CP        0                              ; If zero, no chars are waiting
              JR        Z,RIS2                         ; ...
              LD        HL,RDKEY                       ; We are going to call RDKEY
              LD        (ADDR),HL                      ; ...
              LD        A,1                            ; CMD=1 means call 6502 sub
              LD        (CMD),A                        ; ...
              LD        (SOFTCARD),A                   ; Do it!
              LD        A,(AREG)                       ; Grab the return value
              AND       7FH                            ; Mask high bit
              LD        L,A                            ; Copy A to L
              RET                                      ;
RIS2          XOR       A                              ; No chars waiting, A=0
              LD        L,A                            ; Return in L also
              RET

; Get the IOBYTE in A and L
GET_IOB       LD        A,(IOBYTE)                     ;
              LD        L,A                            ; Copy to L
              RET

; Set the IOBYTE
; E contains the IOBYTE value to set
SET_IOB       LD        A,E
              LD        (IOBYTE),A
              LD        A,(AXMODE)                     ; CP/M $0003 is in AUX for AUX apps
              OR        A
              RET       Z
              LD        HL,IOBYTE
              LD        DE,IOBYTE
              LD        BC,1
              JP        AXM2A

; Write ASCII string to console. '$' is the terminator
; DE contains the address of the string
C_WRITESTR    LD        A,(DE)                         ; Fetch character from string
              CP        '$'                            ; Is it '$'?
              RET       Z                              ; If so, we are done
              PUSH      DE                             ; We are gonna need E
              LD        E,A                            ; For C_WRITE
              CALL      C_WRITE                        ; Sent char to console
              POP       DE                             ; Recover the pointer
              INC       DE                             ; Advance pointer
              JR        C_WRITESTR                     ; Handle the next char

; Read console string
; DE points to the string buffer. First byte of the buffer is the capacity
; of the buffer. This function writes the number of bytes written in second
; byte.  Entry finishes on CR or when the buffer is filled up.
; Supports ^H, DEL for deleting a character
; Supports ^Z for deleting entire line (since ^X doesn't work with RDKEY
C_READSTR     LD        H,D                            ; HL will be the working pointer
              LD        L,E                            ; ...
              INC       HL                             ; Advance to first character ...
              INC       HL                             ; ... 3rd byte of the buffer
              PUSH      DE                             ; Put DE into IX
              POP       IX                             ; ...
              XOR       A                              ; Set number of chars read to zero
              LD        (IX+1),A                       ; ...
; The console input routine must NOT echo before we know whether
; editing is legal. In particular, backspace on an empty line must not
; move the cursor into the CCP's A> prompt.  Both ^H and DEL erase one.
CRSL1         PUSH      HL
              CALL      SCHIDLE                        ; allow background jobs while CCP idle
              CALL      BIOSCONIN                      ; Raw key, no premature echo
              POP       HL
              CALL      TSKKEY                         ; includes Open Apple+arrows
              JP        C,CR_SELCMD
              OR        A
              JP        Z,CRSL1                        ; OA-current beep: no CCP input
              CP        3                              ; Preserve CP/M Ctrl-C abort
              JP        Z,BDOSWARM
              CP        13
              JR        Z,CRSEND
              CP        10
              JR        Z,CRSEND
              CP        8
              JR        Z,CRSS2
              CP        7FH
              JR        Z,CRSS2
              CP        26
              JR        Z,CRSS3
              LD        B,A
              LD        A,(IX+0)                       ; Buffer capacity
              SUB       (IX+1)
              RET       Z                              ; Full: accept/echo nothing else
              LD        (HL),B
              INC       HL
              INC       (IX+1)
              LD        E,B
              PUSH      HL
              CALL      C_WRITE                        ; Echo accepted character
              POP       HL
              JR        CRSL1
CRSEND        LD        E,A                            ; Echo line terminator
              CALL      C_WRITE
              RET
CRSS2         LD        A,(IX+1)                       ; Nothing to erase?
              OR        A
              JP        Z,CRSL1                        ; Do not touch prompt or cursor
              DEC       HL
              DEC       (IX+1)
              PUSH      HL
              LD        E,8                            ; Back up, erase, back up
              CALL      C_WRITE
              LD        E,' '
              CALL      C_WRITE
              LD        E,8
              CALL      C_WRITE
              POP       HL
              JP        CRSL1
CRSS3         LD        A,0                            ; Set character count to zero to ...
              LD        (IX+1),A                       ; ... cancel the entire entry
              LD        E,13                           ; Print a carriage return
              CALL      C_WRITE                        ; ...
              RET                                      ; Done

; Returns 0 in A and L if no chars waiting, non zero otherwise
C_STAT        LD        A,(IOBYTE)
              AND       3
              CP        1
              JP        NZ,IOZERO
              LD        A,3                            ; CMD=3 means peek at keyboard
              LD        (CMD),A                        ; ...
              LD        (SOFTCARD),A                   ; Do it
              LD        A,(AREG)                       ; Grab the return value
              LD        L,A                            ; Copy A to L
              RET

; Returns system type in B and H, BDOS version in A and L
S_BDOSVER     LD        B,0                            ; System is 8080 CP/M
              LD        H,B                            ; Also in H
              LD        A,22H                          ; Pretend to v2.2
              LD        L,A                            ; Also in A
              RET

; Reset disks
; Makes A: drive the default
DRV_ALLRST    LD        HL,0000H                       ; Clear all software R/O bits
              LD        (ROVEC),HL
              LD        HL,0001H                       ; A: is selected and logged in after reset
              LD        (LOGVEC),HL
              LD        A,(CURDRV)                     ; Contains both user & current drive
              AND       0F0H                           ; Set drive to 0, meaning A:
              LD        (CURDRV),A                     ; Store in CURDRV
              LD        BC,FILEBUF                     ; FILEBUF is at 0080H
              LD        (DMAADDR),BC                   ; Reset DMA address
              LD        HL,FLMLI                       ; Pass address of 6502 JSR instruction
              CALL      PRODOS                         ; Invoke ProDOS MLI to flush all files
              PUSH      AF
              CALL      S8INVAL                        ; reset invalidates this tab's search
              POP       AF
              RET

; Select disk
; Disk to select is passed in E (A: is 0, B: is 1 etc.)
; Return 00 for success, 0FFH for error in A and L
DRV_SET       LD        A,E                            ; Prepare to compare disk number
              CP        16                             ; Support 16 'drives' A: - P:
              JR        NC,DSERR                       ; If A>15 ... error
              LD        B,A                            ; Stash in B for now
              LD        A,(CURDRV)                     ; Has both user number & current drive
              AND       0F0H                           ; Mask out old drive number
              OR        B                              ; Replace with new drive number
              LD        (CURDRV),A                     ; Store the requested drive number

              ; Mark this drive in the 16-bit BDOS login vector.
              ; B is drive number 0..15 (A:..P:).
              LD        HL,0001H                       ; Bit 0 means drive A:
              LD        A,B
              OR        A
              JR        Z,DSMARK
DSMSHIFT      ADD       HL,HL                          ; Shift mask left one drive
              DEC       A
              JR        NZ,DSMSHIFT
DSMARK        LD        A,(LOGVEC)
              OR        L
              LD        (LOGVEC),A
              LD        A,(LOGVEC+1)
              OR        H
              LD        (LOGVEC+1),A

              XOR       A                              ; A=0: Return code meaning success
              JR        DSRET                          ;
DSERR         LD        A,0FFH                         ; Return code for error
DSRET         LD        L,A                            ; Return code in L too
              RET

; Open file
; DE is the address of the FCB describing the file to open
; Returns error codes in A and L:
; Returns 0 for success.  The FCB for the file opened is left at DMAADDR (slot 0)
; Returns 0FFH if file not found
; Opening a file must NOT replace an ongoing BDOS wildcard directory search.
; ProDOS OPEN already checks existence; F_SFIRST is not needed here.
F_OPEN                      ; Explicit CP/M OPEN replaces any cached handle for this name.
              ; This also initializes RC/CR from a fresh ProDOS GET_EOF.
              ; A new OPEN must use the *current* USER, not a stale S1
              ; binding retained across CLOSE for dBASE II compatibility.
              ; Clear the old tag before the first FCB2PATH/CACHECLS.
              PUSH      DE
              PUSH      DE
              POP       IX
              LD        (IX+0DH),0                     ; fresh FCB: no saved USER yet
              LD        IX,PATHBUF
              CALL      FCB2PATH
              CALL      CACHECLS
              POP       DE
              OR        A
              JP        NZ,FOERR
              ; A genuine CP/M 2.2 BDOS OPEN clears S2 on entry.
              ; Do not preserve the application's incoming S2: programs
              ; such as WINSTALL leave non-extent scratch ($C1/$C3) there.
              ; Stage 3's EX/S2/CR positioning would otherwise seek beyond EOF.
              ; _F_OPEN temporarily uses S2 for the ProDOS file reference.
              PUSH      DE
              POP       IX
              XOR       A
              LD        (FOS2),A                      ; new OPEN starts at S2 extent zero
              LD        (IX+0EH),0
              CALL      _F_OPEN
              OR        A
              JR        Z,FO_VOPEN
              PUSH      AF
              LD        A,(FOS2)
              LD        (IY+0EH),A                     ; restore S2 even on OPEN failure
              POP       AF
              RET
FO_VOPEN
              LD        A,(IY+0EH)                     ; New physical ProDOS reference
              CALL      GETIOADDR                      ; Find its newly allocated slot
              CALL      CACHEPUT                       ; Cache the pathname in PATHBUF
              ; The initial _F_OPEN RC assumes extent zero.  Recalculate for
              ; the application's requested EX/S2 using the exact 24-bit EOF.
              ; _F_OPEN needed S2 for the FRN, so use saved FOS2 instead.
              CALL      RCFRESHOPEN                    ; RC for application's requested extent
              ; Reserve S1 ($0D) for the USER at OPEN time. PIP [Gn]
              ; switches USER again before reading this very same FCB.
              LD        A,(CURDRV)
              RRCA
              RRCA
              RRCA
              RRCA
              AND       00FH
              OR        0A0H
              LD        (IY+0DH),A                     ; S1 alone identifies logical open
              LD        A,(FOS2)
              OR        080H                          ; CP/M 2.2: S2 write flag set on OPEN
              LD        (IY+0EH),A                     ; preserve extent/flags, advertise clean
              XOR       A
              LD        L,A
              RET

; Alternative entrypoint used for opening ProDOS directory files
; and used by the CCP to load .COM files.  No directory lookup.
_F_OPEN       LD        IX,PATHBUF                     ; Destination buffer
              CALL      FCB2PATH                       ; Populate PATHLEN and PATH

              PUSH      DE                             ; Copy pointer to FCB ...
              POP       IY                             ; ... into IY

              ; Work out which IOBUF to allocate for this file
              CALL      CACHEFREE                      ; Free slot or evict LRU cached file
              CP        0FFH                           ; Check for error
              JP        Z,FOFULL                       ; If no slots available, diagnostic

              LD        (TEMPBYTE),A                   ; Record the buffer index in local var
              LD        BC,OFFSET                      ; Add offset to convert to 6502 address
              ADD       HL,BC                          ; ...
              LD        (FOMLII),HL                    ; Store in parameter list

              LD        HL,FOMLI                       ; Pass address of 6502 JSR instruction
              CALL      PRODOS                         ; Invoke ProDOS MLI
              CP        0                              ; See if there was an error
              JP        NZ,FOERR                       ; Handle error

              ; Do not publish S2/claim an FRN slot before GET_EOF succeeds.
              ; On failure, OPEN has nevertheless allocated a ProDOS handle:
              ; close it using the ref number from FOMLIN, then return error.
              LD        A,(FOMLIN)
              LD        (GEMLIN),A
              LD        (FCMLIN),A                     ; Prepare cleanup CLOSE (no slot yet)
              LD        HL,GEMLI
              CALL      PRODOS                         ; GET_EOF (24-bit size)
              OR        A
              JR        Z,FO_EOF_OK
              LD        HL,FCMLI
              CALL      PRODOS                         ; CLOSE even if GET_EOF failed
              JP        FOERR                          ; Do not trust GEMLIE1..3 or FCB S2
FO_EOF_OK     LD        A,(FOMLIN)
              LD        (IY+0EH),A                     ; Publish physical reference only now

              ; CP/M RC counts records in extent zero (maximum 128).
              ; Round partial 128-byte records up; honour ProDOS's 24-bit EOF.
              LD        A,(GEMLIE3)
              OR        A
              JR        NZ,FO_RC_FULL
              LD        A,(GEMLIE2)
              CP        40H                            ; >= $4000 bytes (16 KiB)?
              JR        NC,FO_RC_FULL
              ; ceil(EOF/128) for EOF < $4000, with no 16-bit wrap.
              LD        HL,(GEMLIE1)
              LD        BC,127
              ADD       HL,BC
              LD        A,L
              RLCA
              AND       1
              LD        B,A
              LD        A,H
              ADD       A,A
              OR        B
              JR        FO_RC_STORE
FO_RC_FULL    LD        A,80H
FO_RC_STORE   LD        (IY+0FH),A

              ; Set sequential record number to zero
              XOR       A                              ; Zero the sequential record number
              LD        (IY+20H),A                     ; ...

              ; Store ProDOS FRN in slot FRN1 or FRN2
              LD        A,(TEMPBYTE)                   ; Obtain IOBUF idx (1,2)
              LD        HL,FRN1-1                      ; Compute address of FRN slot to use
              LD        B,0                            ; ...
              LD        C,A                            ; ...
              ADD       HL,BC                          ; ...
              LD        A,(FOMLIN)                     ; Get ProDOS file reference number
              LD        (HL),A                         ; Store in FRN slot

              XOR       A                              ; Success
              LD        L,A                            ; Copy to L
              RET                                      ; Done

; Retain diagnostic on genuine buffer exhaustion while testing.
FOFULL        PUSH      DE
              LD        DE,FOFULLMSG
              CALL      C_WRITESTR
              POP       DE
              JR        FOERR
FOFULLMSG     DEFM      'NO IOBUF'
              DEFB      13,'$'

FOERR         LD        A,0FFH                         ; Error return status
              LD        L,A                            ; Copy to L
              RET                                      ; Done (error)

; Close file
; DE is the address of the FCB describing the file to close
; Returns error codes in A and L:
F_CLOSE       LD        H,D                            ; Pointer to FCB ...
              LD        L,E                            ; ... into HL
              LD        BC,0EH                         ; Offset to S2 field (reserved field)
              ADD       HL,BC                          ; Compute address
              CALL      FCBVOPEN                       ; same open test as I/O and F2P_USER
              JR        Z,FCVIRT
              ; Only our own directory/loader FCBs may contain a raw FRN.
              ; Never CLOSE an arbitrary application S2 value as a ProDOS FRN.
              CALL      FCBRAW
              JR        Z,FC_RAW
              LD        A,(HL)
              OR        A
              JR        Z,FCSUCC                       ; harmless CLOSE of unopened FCB
              JR        FCERR                          ; untagged and nonzero != FRN
FC_RAW        LD        A,(HL)
              JR        FCPHYS
FCVIRT                      ; Flush and guarded one-record RC shrink on CLOSE.
              ; Never change S1/open state if the EOF check or close fails.
              PUSH      HL
              PUSH      DE
              PUSH      IX
              CALL      FC5TRIM
              POP       IX
              POP       DE
              POP       HL
              OR        A
              JP        NZ,FCERR
              ; Names, not FCB addresses, identify cache entries (AUX staging).
              PUSH      HL
              PUSH      DE
              PUSH      IX
              LD        IX,PATHBUF
              CALL      FCB2PATH
              CALL      CACHECLS
              POP       IX
              POP       DE
              POP       HL
              OR        A
              JP        NZ,FCERR
              ; CP/M-compatible post-CLOSE FCB reuse: CLOSE has flushed the
              ; physical ProDOS handle through CACHECLS.  Keep the logical
              ; S1=$A0|USER tag, so a later READ/WRITE through the same FCB
              ; can reopen by pathname via IO_BEGIN.  dBASE II does this
              ; after CREATE without another explicit BDOS OPEN.
              ; Preserve EX/RC/CR; on a successful one-record trim FC5TRIM
              ; sets only S2's bit-7 clean flag (S1 remains bound).
              JP        FCSUCC
FCPHYS        CP        0                              ; If file reference number is zero ...
              JR        Z,FCSUCC                       ; ... Nothing to do, just return
              LD        (FCMLIN),A                     ; Store in parameter list
              LD        HL,FCMLI                       ; Pass address of 6502 JSR instruction
              CALL      PRODOS                         ; Invoke ProDOS MLI
              CP        0                              ; See if there was an error
              JR        NZ,FCERR                       ; Handle error

              LD        A,(FCMLIN)                     ; Obtain file reference number again
              CALL      GETIOADDR                      ; Returns FRN slot in A, IOBUF in HL
              CP        0FFH                           ; Check for error
              JR        Z,FCERR                        ; If FRN not found, error out

              LD        HL,FRN1-1                      ; Compute addr of FRN slot to set to zero
              LD        B,0                            ; ...
              LD        C,A                            ; ...
              ADD       HL,BC                          ; ...
              XOR       A                              ; And zero it
              LD        (HL),A                         ; ...

              PUSH      DE                             ; Copy pointer to FCB ...
              POP       IX                             ; ... into IX
              XOR       A                              ; Zero out the S2 field
              LD        (IX+0EH),A                     ; ...

FCSUCC        XOR       A                              ; Return zero for error
              LD        L,A                            ; Return in L also
              RET

FCERR         LD        A,0FFH                         ; 0FFH for error
              LD        L,A                            ; Return code in L also
              RET

DIRHDSZ       EQU       2BH                            ; Size of ProDOS directory header
FILEENTSZ     EQU       27H                            ; Size of ProDOS file entry
ENTPERBLK     EQU       0DH                            ; Number of file entries per block

; Search for first match of filename in directory
; DE is the address of the FCB describing the file to look for
; Returns error codes in A and L: 0 for success, 0FFH for not found
; The matching FCB is always in slot 0, so success return code always 0
F_SFIRST      LD        (TEMPWORD),DE                  ; Store pointer to search FCB
              LD        A,(DE)                         ; Obtain drive number
              LD        (DFCBDRV),A                    ; Copy to directory FCB
              LD        DE,DFCB                        ; Use this FCB to open the directory
              CALL      F_CLOSE                        ; Close the directory, if open
              LD        DE,DFCB                        ; Use this FCB to open the directory
              CALL      _F_OPEN                        ; Open the directory (avoiding recursion!)
              OR        A                              ; _F_OPEN returns status in A, not flags
              JR        NZ,FSFS2                       ; OPEN failed: return no match, no stale DFCB read

FSFL1         LD        HL,0FFFFH                      ; first extent of next ProDOS dirent
              LD        (CDBEXT),HL
              CALL      RDDIRBLK                       ; Read first 512 byte block
              CP        0                              ; See if it was an error
              JR        NZ,FSFS2                       ; If error, assume EOF & just return

              ; RDDIRBLK sets CDBPTR/CDBCOUNT based on the link pointer.
              LD        DE,(TEMPWORD)                  ; Get ptr to search FCB back
              CALL      CHKDIRBLK                      ; Search directory block
              CP        0                              ; See if it was a match
              JR        Z,FSFS1                        ; If so, return
              JR        FSFL1                          ; Loop

FSFS1         LD        DE,(TEMPWORD)                  ; Get ptr to search FCB back
              LD        A,(DE)                         ; Obtain drive number
              LD        HL,(DMAADDR)                   ; Pointer to FCB we are returning
              LD        (HL),A                         ; Copy drive number to FCB
              XOR       A                              ; Match
              RET                                      ;
FSFS2         JR        FSNS2                          ; Shared EOF cleanup (also OPEN failure)

; Search for next match of filename in directory
; The address of the FCB describing the file to look for is in TEMPWORD
; Caller restores DIRBUF/DFCB via S8REST if another tab ran in between.
; Returns error codes in A and L: 0 for success, 0FFH for not found
; The matching FCB is always in slot 0, so success return code always 0
F_SNEXT       LD        A,(CDBCOUNT)                   ; Entries already consumed
              CP        ENTPERBLK                      ; Last entry returned on previous search?
              JR        NC,FSNNEW                      ; Advance block before dereferencing
FSNL1         LD        DE,(TEMPWORD)                  ; Get ptr to search FCB back
              CALL      CHKDIRBLK                      ; Search directory block
              CP        0                              ; See if it was a match
              JR        Z,FSNS1                        ; If so, return

FSNNEW        LD        HL,0FFFFH                      ; first extent in next ProDOS block
              LD        (CDBEXT),HL
              CALL      RDDIRBLK                       ; Read next 512 byte block
              CP        0                              ; See if it was an error
              JR        NZ,FSNS2                       ; If error, assume EOF & just return

              ; RDDIRBLK sets CDBPTR/CDBCOUNT based on the link pointer.
              JR        FSNL1                          ; Loop

FSNS1         LD        DE,(TEMPWORD)                  ; Get ptr to search FCB back
              LD        A,(DE)                         ; Obtain drive number
              LD        HL,(DMAADDR)                   ; Pointer to FCB we are returning
              LD        (HL),A                         ; Copy drive number to FCB
              XOR       A                              ; Match
              RET                                      ;
FSNS2         JP        SEARCH_EOF                     ; Release directory FRN on end-of-search

; Delete file
; DE is the address of the FCB describing the file to delete
; Returns error codes in A and L:
; For an exact name, destroy directly; don't clobber the caller's
; F_SFIRST/F_SNEXT enumeration.  Preserve old logic for wildcards.
F_DELETE      CALL      DCHKRO
              JP        NZ,RODENY
              LD        H,D
              LD        L,E
              INC       HL                             ; Skip FCB drive byte
              LD        B,11                           ; 8 + 3 filename characters
FD_CHKWILD    LD        A,(HL)
              CP        '?'
              JR        Z,FD_WILD
              INC       HL
              DJNZ      FD_CHKWILD
              LD        IX,PATHBUF
              CALL      FCB2PATH
              CALL      CACHECLS                       ; ProDOS DESTROY requires no cached OPEN
              OR        A
              JR        NZ,FD_ERR
              LD        HL,FDMLI
              CALL      PRODOS
              CP        04EH                           ; ProDOS access denied, not missing
              JP        Z,ROFILE
              OR        A
              JR        Z,FD_OK
FD_ERR        LD        A,0FFH
FD_OK         LD        L,A
              RET
; Wildcard delete: never mutate an open ProDOS directory while using
; its cached search state.  Delete ONE match, close the directory before
; DESTROY, then restart F_SFIRST against the updated directory.
; The first search distinguishes "no matches" from "all matches deleted".
FD_WILD       PUSH      DE                             ; Save original wildcard FCB
              CALL      F_SFIRST                       ; Find the first matching file
              CP        0FFH
              JR        Z,FDS2                         ; Nothing matched initially
FDL1          LD        DE,DFCB
              CALL      F_CLOSE                        ; Release directory before DESTROY
              OR        A
              JR        NZ,FDS2
              LD        DE,FILEBUF                     ; Matching FCB from F_SFIRST
              LD        IX,PATHBUF
              CALL      FCB2PATH
              CALL      CACHECLS                       ; Close cached match before DESTROY
              OR        A
              JR        NZ,FDS2
              LD        HL,FDMLI
              CALL      PRODOS                         ; ProDOS DESTROY
              CP        04EH
              JR        NZ,FDWCHK
              LD        A,1
              LD        (ROERROR),A                    ; Delay report until search is closed
              JR        FDS2
FDWCHK        OR        A
              JR        NZ,FDS2
              POP       DE                             ; Restore original wildcard
              PUSH      DE
              CALL      F_SFIRST                       ; Re-read directory after deletion
              CP        0FFH
              JR        NZ,FDL1                        ; Another match
FDS1          XOR       A                              ; Success: at least one file deleted
              JR        FDSDONE
FDS2          LD        A,0FFH                         ; No match / ProDOS error
FDSDONE       PUSH      AF                             ; Preserve deletion status
              LD        DE,DFCB
              CALL      F_CLOSE                        ; Release directory on every exit
              POP       AF
              POP       DE                             ; Balance saved wildcard FCB
              LD        L,A
              PUSH      AF
              LD        A,(ROERROR)
              OR        A
              JR        Z,FDWRET
              POP       AF
              JP        ROFILE
FDWRET        POP       AF
              RET

; Read next record
; DE is the address of the FCB describing the file from which to read
; Returns error codes in A and L:
; 0 OK, 1 EOF, 9 invalid FCB, 10 media changed, 0FFH h/w error
F_READ        PUSH      DE                             ; Copy pointer to FCB ...
              POP       IX                             ; ... into IX
              CALL      IO_BEGIN                       ; Reopen logical CP/M FCB if needed
              OR        A
              JR        Z,F_READ_GO
              LD        L,A                            ; Invalid/open-error FCB
              JP        IO_END                         ; IO_END relocated to $A200 (out of JR range)
F_READ_GO
              LD        A,(IX+0EH)                     ; Obtain file reference num from FCB S2
              LD        (SMMLIN),A                     ; Store in parameter list for SET_MARK
              LD        (FRMLIN),A                     ; Store in parameter list for READ

              CALL      SEQMARK                        ; EX[4:0], S2[5:0], CR[6:0]
              JP        C,FREOF                        ; beyond ProDOS 24-bit mark
              LD        HL,SMMLI                       ; Pass address of 6502 JSR instruction
              CALL      PRODOS                         ; Invoke ProDOS MLI - SET_MARK
              CP        4DH                            ; See if position was out of range
              JP        Z,FREOF                        ; If so, return EOF (1)
              CP        43H                            ; See if it was a bad file ref number
              JP        Z,FRBFCB                       ; If so, return invalid FCB code (9)
              CP        0                              ; See if there was some other error
              JP        NZ,FRERR                       ; If so, return code 0FFH (h/w error)

              LD        HL,(DMAADDR)                   ; Write data starting at DMA buffer addr
              LD        BC,OFFSET                      ; Convert to 6502 address
              ADD       HL,BC                          ; ...
              LD        (FRMLIDB),HL                   ; Store I/O buffer address in parm list

              CALL      READ128                        ; READ and pad a short record with ^Z
              CP        4CH                            ; See if it was EOF
              JR        Z,FREOF                        ; If so, return EOF code (1)
              CP        43H                            ; See if it was a bad file ref number
              JR        Z,FRBFCB                       ; If so, return invalid FCB code (9)
              CP        0                              ; See if there was some other error
              JR        NZ,FRERR                       ; If so, return code 0FFH (h/w error)

              LD        A,(IX+20H)                     ; Get sequential rec num from FCB
              INC       (IX+20H)                       ; Increment sequential record number
              CP        127                            ; Accumulator before increment
              JR        NZ,FRS1                        ; If not, then nothing else to do
              XOR       A                              ; Set sequential rec num to zero
              LD        (IX+20H),A
              CALL      EXROLL                         ; EX 31 -> 0, carry into saved S2
              CALL      RCNEXT                         ; RC of next extent from actual EOF

FRS1          XOR       A                              ; Zero for success
              JP        IO_END                         ; Close transient handle
FREOF         LD        A,1                            ; EOF return code
              JP        IO_END                         ; Close transient handle
FRBFCB        LD        A,9                            ; Invalid FCB return code
              JP        IO_END                         ; Close transient handle
FRERR         LD        A,0FFH                         ; All other errors are 0FFH
              JP        IO_END                         ; Close transient handle

; Write next record
; DE is the address of the FCB describing the file to which to write
; Returns error codes in A and L:
; 0 OK, 1 dir full, 2 disk full, 9 invalid FCB, 10 media changed, 0FFH h/w error
F_WRITE       CALL      DCHKRO
              JP        NZ,RODENY
              PUSH      DE                             ; Copy pointer to FCB ...
              POP       IX                             ; ... into IX
              CALL      IO_BEGIN                       ; Reopen logical CP/M FCB if needed
              OR        A
              JR        Z,F_WRITE_GO
              JP        IO_END                         ; Close transient handle
F_WRITE_GO
              LD        A,(IX+0EH)                     ; Obtain file reference num from FCB S2
              LD        (SMMLIN),A                     ; Store in parameter list for SET_MARK
              LD        (FWMLIN),A                     ; Store in parameter list for WRITE

              CALL      SEQMARK                        ; include saved S2 in 24-bit mark
              JP        C,FWDF                         ; no room beyond $FFFFFF
              ; ProDOS SET_MARK refuses offsets past EOF.  CP/M sequential
              ; writes may skip records, so extend logical EOF if necessary.
              CALL      SEQEXTEND
              OR        A
              JP        NZ,FWERR

;;          ; DEBUG
;;          PUSH    HL
;;          LD      DE,HEXBUF       ; (obsolete diagnostic)
;;          CALL    NUM2HEX         ; (obsolete diagnostic)
;;          LD      DE,HEXBUF       ; Write hex value to console
;;          CALL    C_WRITESTR      ;
;;          POP     HL
;;          ; END DEBUG

              LD        HL,SMMLI                       ; Pass address of 6502 JSR instruction
              CALL      PRODOS                         ; Invoke ProDOS MLI - SET_MARK
              CP        4DH                            ; See if position was out of range
              JP        Z,FWBFCB                       ; If so, return invalid FCB code (9)
              CP        43H                            ; See if it was a bad file ref number
              JP        Z,FWBFCB                       ; If so, return invalid FCB code (9)
              CP        0                              ; See if there was some other error
              JP        NZ,FWERR                       ; If so, return code 0FFH (h/w error)

              LD        HL,(DMAADDR)                   ; Write data at DMA address
              LD        BC,OFFSET                      ; Convert to 6502 address
              ADD       HL,BC                          ; ...
              LD        (FWMLIDB),HL                   ; Store I/O buffer address in parm list

              LD        HL,FWMLI                       ; Pass address of 6502 JSR instruction
              CALL      PRODOS                         ; Invoke ProDOS MLI - WRITE
              CP        04EH                           ; No write permission
              JP        Z,FWRO
              CP        43H                            ; See if it is a bad reference number
              JR        Z,FWBFCB                       ; If so, return invalid FCB code (9)
              CP        48H                            ; See if it was an overrun error
              JR        Z,FWDF                         ; If so, return disk full code (2)
              CP        0                              ; See if there was some other error
              JR        NZ,FWERR                       ; If so, return code 0FFH (h/w error)

              ; ProDOS WRITE succeeded.  Advance CR and update RC for
              ; the extent just written; do not change either on errors.
              CALL      RCSEQWRITE
FWS1          XOR       A                              ; Zero for success
              JP        IO_END                         ; Close transient handle
FWBFCB        LD        A,9                            ; Invalid FCB return code
              JP        IO_END                         ; Close transient handle
FWDF          LD        A,2                            ; Disk full return code
              JP        IO_END                         ; Close transient handle
FWERR         LD        A,0FFH                         ; All other errors are 0FFH
              JP        IO_END                         ; Close transient handle
FWRO          LD        A,0FFH
              CALL      IO_END                         ; Release ProDOS handle first
              JP        ROFILE

; Create (and open) file
; DE is the address of the FCB describing the file to create
; Returns error codes in A and L:
; 0 for success, 0FFH if file could not be created
F_MAKE        CALL      DCHKRO
              JP        NZ,RODENY
              ; A fresh CREATE must not inherit S1's former USER binding.
              ; F_OPEN below will establish the new $A0|USER tag on success.
              PUSH      DE
              POP       IX
              LD        (IX+0DH),0
              LD        IX,PATHBUF                     ; Destination buffer
              CALL      FCB2PATH                       ; Populate PATHLEN and PATH
              LD        HL,FMMLI                       ; Pass address of 6502 JSR instruction
              CALL      PRODOS                         ; Invoke ProDOS MLI
              CP        044H                           ; ProDOS: parent directory not found?
              JR        NZ,FM_CHECK
              PUSH      DE
              CALL      UD_MKDIR                       ; create A1..A15 etc on first write
              POP       DE
              OR        A
              JP        NZ,FMERR
              LD        HL,FMMLI
              CALL      PRODOS                         ; retry the original file creation
FM_CHECK      CP        0                              ; See if there was an error
              JR        NZ,FMERR                       ; Handle error
              CALL      F_OPEN                         ; Open same FCB without touching search state
              OR        A
              RET       Z
              PUSH      AF                             ; Diagnostic for post-CREATE OPEN failure
              PUSH      BC
              PUSH      DE
              LD        C,A
              LD        DE,FMOPENMSG
              CALL      C_WRITESTR
              CALL      PRHEX                          ; Underlying Zapple-II error code
              POP       DE
              POP       BC
              POP       AF
              RET
FMERR         CP        04EH
              JP        Z,ROFILE
              PUSH      AF
              PUSH      BC
              PUSH      DE
              LD        C,A
              LD        DE,FMCRMSG
              CALL      C_WRITESTR
              CALL      PRHEX                          ; Show true ProDOS CREATE error
              POP       DE
              POP       BC
              POP       AF
              LD        A,0FFH                         ; 0FFH for error
              LD        L,A                            ; Return code in L also
              RET
FMCRMSG       DEFM      'Zapple-II CREATE error: '
              DEFB      '$'
FMOPENMSG     DEFM      'Zapple-II OPEN-after-CREATE error: '
              DEFB      '$'

; Rename file
; DE is the address of the FCB describing the file to be renamed. The new name
; is stuffed into FCB+16 (where the allocation map usually goes)
; Returns error codes in A and L - 0 for success, 0FFH for file not found
; ProDOS RENAME checks that the old file exists.  Doing F_SFIRST here
; would clobber a wildcard enumeration in progress (notably PIP).
F_RENAME      CALL      DCHKRO                         ; Check source FCB drive
              JP        NZ,RODENY
              ; CP/M BDOS 23 ignores the drive byte at FCB+16.
              ; The old and new filenames must stay on the source drive.
              LD        IX,PATHBUF                     ; Destination buffer 1
              CALL      FCB2PATH                       ; Populate PATHLEN and PATH for first file
              PUSH      DE
              CALL      CACHECLS                       ; Close source cached handle before RENAME
              POP       DE
              OR        A
              JP        NZ,FRNERR
              LD        IX,PATHBUF2                    ; Destination buffer 2
              LD        H,D                            ; DE -> HL for addition
              LD        L,E                            ; ...
              LD        BC,16                          ; Increment by 16 bytes to 2nd part of FCB
              ADD       HL,BC                          ; ...
              LD        D,H                            ; HL back to DE
              LD        E,L                            ; ...
              CALL      FCB2PATH                       ; Encode second name, then override drive
              LD        A,(PATH)                       ; FCB+0 is the sole BDOS 23 drive
              LD        (PATH2),A                       ; ignore second FCB's drive byte
              LD        HL,FRNMLI                      ; Pass address of 6502 JSR instruction
              CALL      PRODOS                         ; Invoke ProDOS MLI
              CP        0                              ; See if there was an error
              JR        NZ,FRNERR                      ; Handle error
              XOR       A                              ; Success
              LD        L,A                            ; Return code in L also
              RET
FRNERR        CP        04EH
              JP        Z,ROFILE
              LD        A,0FFH                         ; 0FFH for error
              LD        L,A                            ; Return code in L also
              RET

; Return bitmap of logged-in drives in HL
DRV_LOGVEC    LD        HL,(LOGVEC)                    ;
              RET

; Return current drive in A
DRV_GET       LD        A,(CURDRV)                     ; Contains user number & current drive
              AND       0FH                            ; Mask out user number
              RET

; Set DMA address
; DMA address is passed in DE
F_DMAOFF      LD        (DMAADDR),DE                   ;
              RET

; Return CP/M allocation map. Build it from the actual ProDOS volume bitmap.
DRV_AVEC      CALL      V_GETFREE
              LD        HL,ALLOCVEC
              RET

; Scan every ProDOS bitmap block, up to the full 65535-block (~32 MiB)
; volume limit. Set DSM to the actual volume capacity in 2 KiB CP/M blocks.
; The CP/M allocation vector is held in 6502 $0800-$0FFF (Z80 $F800-$FFFF)
; and built only AFTER all ProDOS READ_BLOCK calls are finished: the input
; block buffer and the returned allocation vector intentionally overlap.
;
; Volume directory block 2 has:
;  $04 = $Fx storage type, $23 = $27 entry length, $24 = $0D entries
;  $27/$28 = volume bitmap start, $29/$2A = number of 512-byte blocks.
; ProDOS bitmap: 1 = free, MSB first. CP/M bitmap: 0 = free, MSB first.
; NOTE: one bit per *virtual* 2K block; the bitmap only conveys a free
; space count. Block identities are synthetic (see N2FMAP).
;
; On errors, leave a fully allocated map, i.e. report zero free space.
; Last ProDOS READ_BLOCK error is recorded in VERR (for MAME debugger).
; ProDOS unit discovered from current prefix or drive directory by V_FINDUNIT.
V_GETFREE     XOR       A
              LD        (VERR),A

              ; Discover the physical unit containing the CP/M directories.
              ; This must precede READ_BLOCK of the volume header.
              CALL      V_FINDUNIT
              JP        NZ,V_ERROR

              LD        HL,2
              LD        (VRBLK),HL
              CALL      V_READ
              JP        NZ,V_ERROR

              ; Validate that READ_BLOCK returned a volume header.
              LD        A,(VOLBUF+04H)
              AND       0F0H
              CP        0F0H
              JP        NZ,V_BADHDR
              LD        A,(VOLBUF+23H)
              CP        027H
              JP        NZ,V_BADHDR
              LD        A,(VOLBUF+24H)
              CP        00DH
              JP        NZ,V_BADHDR

              ; How big is the actual volume? Retain this for debugging.
              LD        HL,(VOLBUF+29H)
              LD        (VTOTAL),HL
              LD        A,H
              OR        L
              JP        Z,V_BADHDR

              ; All 16-bit ProDOS block numbers are representable.
              ; 65535 blocks require 16 consecutive bitmap blocks.
              LD        (VLEFT),HL

              ; CP/M virtual capacity: floor(number_of_512B_blocks / 4).
              SRL       H
              RR        L
              SRL       H
              RR        L
              LD        A,H
              OR        L
              JP        Z,V_BADHDR
              LD        (VNBLOCKS),HL
              DEC       HL
              LD        (DPBDSM),HL                    ; Correct DSM, e.g. 399 for 800 KiB

              ; Last CP/M block uses byte DSM/8 and mask $80 >> (DSM%8).
              LD        A,L
              AND       07H
              LD        B,A
              LD        A,080H
V_SETMASK     LD        C,A
              LD        A,B
              OR        A
              LD        A,C
              JR        Z,V_MASKDONE
              SRL       A
              DEC       B
              JR        V_SETMASK
V_MASKDONE    LD        (VFMASK),A
              LD        HL,(DPBDSM)
              SRL       H
              RR        L
              SRL       H
              RR        L
              SRL       H
              RR        L
              LD        DE,ALLOCVEC
              ADD       HL,DE
              LD        (VFEND),HL

              ; Reserve blocks 0..8 for CP/M directory / synthetic IDs.
              LD        HL,(VNBLOCKS)
              LD        DE,9
              OR        A
              SBC       HL,DE
              JR        NC,V_BUDGETOK
              LD        HL,0
V_BUDGETOK    LD        (VBUDGET),HL

              ; Bitmap pointer must be a real volume block.
              LD        HL,(VOLBUF+27H)
              LD        A,H
              OR        L
              JP        Z,V_BADHDR
              LD        (VRBLK),HL
              LD        DE,(VTOTAL)
              OR        A
              SBC       HL,DE
              JP        NC,V_BADHDR
              LD        HL,0
              LD        (VFREE),HL

V_NEXTMAP     LD        HL,(VLEFT)
              LD        A,H
              OR        L
              JP        Z,V_READY
              CALL      V_READ
              JP        NZ,V_ERROR
              LD        HL,VOLBUF
              LD        BC,512
V_MAPBYTE     LD        E,(HL)
              LD        D,8
V_MAPBIT      PUSH      HL
              LD        HL,(VLEFT)
              LD        A,H
              OR        L
              JR        Z,V_DONEPOP
              DEC       HL
              LD        (VLEFT),HL
              POP       HL
              LD        A,E
              ADD       A,A
              LD        E,A
              JR        NC,V_USED
              PUSH      HL
              LD        HL,(VFREE)
              INC       HL
              LD        (VFREE),HL
              POP       HL
V_USED        DEC       D
              JR        NZ,V_MAPBIT
              INC       HL
              DEC       BC
              LD        A,B
              OR        C
              JR        NZ,V_MAPBYTE
              LD        HL,(VRBLK)
              INC       HL
              LD        (VRBLK),HL
              JP        V_NEXTMAP

V_DONEPOP     POP       HL
              JR        V_READY

; All input READ_BLOCK calls have finished. Reuse the $0800-$0FFF
; main-memory scratch area as the complete 2048-byte CP/M allocation map.
; 65535 ProDOS blocks / 4 = 16383 virtual 2K allocation blocks.
; Fill with $FF (occupied), then clear the free bits from the high end.
V_READY       CALL      V_CLEARVEC
              LD        HL,(VFREE)
              SRL       H
              RR        L
              SRL       H
              RR        L
              LD        B,H
              LD        C,L

V_MARK        LD        A,B
              OR        C
              RET       Z
              LD        HL,(VBUDGET)
              LD        A,H
              OR        L
              RET       Z                              ; Cannot exceed actual disk capacity
              DEC       HL
              LD        (VBUDGET),HL
              LD        HL,(VFEND)
              LD        A,(VFMASK)
              CPL
              AND       (HL)
              LD        (HL),A
              LD        A,(VFMASK)
              SRL       A
              JR        NZ,V_NEXTBIT
              LD        A,080H
              DEC       HL
V_NEXTBIT     LD        (VFMASK),A
              LD        (VFEND),HL
              DEC       BC
              JR        V_MARK

V_BADHDR      LD        A,0FEH                         ; Invalid/misread volume header
V_ERROR       LD        (VERR),A                       ; Capture MLI status for MAME debug
              ; On failure advertise zero free blocks.
              CALL      V_CLEARVEC
              RET

; Fill the full 2K vector with $FF, not just 64 bytes. A $FF in the
; CP/M allocation bitmap means all blocks are used. LDIR copies the first
; $FF forward into each following location, taking 2047 transfers.
V_CLEARVEC    LD        HL,ALLOCVEC
              LD        (HL),0FFH
              LD        DE,ALLOCVEC+1
              LD        BC,2047
              LDIR
              RET

V_READ        LD        HL,VRMLI
              CALL      PRODOS
              OR        A
              RET

; Find and cache the one physical ProDOS unit hosting Zapple-II.
; CP/M A:..P: are subdirectories of the SAME ProDOS volume, so changing
; CP/M drive must not trigger an expensive ON_LINE enumeration.
; A nonempty GET_PREFIX identifies the volume; if it is empty, search
; for the first online volume containing the selected drive directory.
; Only this FIRST discovery uses GET_PREFIX and ON_LINE (unit=0).
; VUCVALID is cleared by BDOSINIT on cold start, not by WBOOT.
; Free-space bitmap reads in V_GETFREE are still done on every request.
; All MLI scratch space is in 6502 main $0800-$097F; the direct console
; uses text page 1, and READ_BLOCK overwrites this scratch area later.
; Returns A=0 on success, else an MLI error or $FD (no matching volume).
V_FINDUNIT    LD        A,(VUCVALID)
              OR        A
              JR        Z,VUCDISC
              XOR       A                              ; VRUNIT still holds our ProDOS unit
              RET
VUCDISC       XOR       A
              LD        (VRUNIT),A                     ; Invalidate stale unit on failure
              LD        HL,VPMLI                       ; GET_PREFIX -> $0800
              CALL      PRODOS
              OR        A
              RET       NZ
              LD        A,(VOLBUF)                     ; Pascal prefix length
              OR        A
              JP        Z,V_NOPREFIX
              LD        B,A
              LD        HL,VOLBUF+1
              LD        A,(HL)
              CP        '/'
              JP        NZ,V_NOMATCH
              INC       HL
              DEC       B
              LD        C,0
V_PFXNAME     LD        A,B
              OR        A
              JP        Z,V_NOMATCH
              LD        A,(HL)
              CP        '/'
              JR        Z,V_PFXDONE
              INC       C
              LD        A,C
              CP        16                             ; ProDOS volume name is <= 15 chars
              JP        NC,V_NOMATCH
              INC       HL
              DEC       B
              JR        V_PFXNAME
V_PFXDONE     LD        A,C
              OR        A
              JP        Z,V_NOMATCH
              LD        (V_NAMELEN),A
              LD        A,1
              LD        (V_HASPFX),A
              JR        V_ENUM
V_NOPREFIX    XOR       A
              LD        (V_HASPFX),A

V_ENUM        LD        HL,VOMLI                       ; ON_LINE all units -> $0880
              CALL      PRODOS
              OR        A
              RET       NZ
              LD        IX,VOLBUF+080H
              LD        B,16                           ; Up to sixteen 16-byte records
V_SCAN        LD        A,(IX+0)
              OR        A                              ; End of returned list
              JP        Z,V_NOMATCH
              AND       0FH
              JP        Z,V_NEXT                       ; Device error; no name
              LD        C,A                            ; Name length from ON_LINE
              LD        A,(V_HASPFX)
              OR        A
              JR        Z,V_TRYDIR
              LD        A,(V_NAMELEN)
              CP        C
              JP        NZ,V_NEXT
              PUSH      BC
              PUSH      IX
              POP       DE
              INC       DE                             ; First character of ON_LINE name
              LD        HL,VOLBUF+2                    ; After leading '/' in prefix
              LD        B,C
V_CMPNAME     LD        A,(DE)
              AND       0DFH                           ; Case-insensitive ProDOS name
              LD        C,A
              LD        A,(HL)
              AND       0DFH
              CP        C
              JR        NZ,V_DIFFER
              INC       DE
              INC       HL
              DJNZ      V_CMPNAME
              POP       BC
              JP        V_FOUND
V_DIFFER      POP       BC
              JP        V_NEXT

; Null prefix: see whether /VOLUME/<driveletter> is a ProDOS directory.
; The volume search order from ON_LINE mirrors relative pathname search.
V_TRYDIR      PUSH      BC
              LD        A,C
              ADD       A,3                            ; '/' + volume + '/' + drive
              LD        (VOLBUF),A
              LD        HL,VOLBUF+1
              LD        (HL),'/'
              INC       HL
              PUSH      IX
              POP       DE
              INC       DE
              LD        B,C
V_MKPATH      LD        A,(DE)
              LD        (HL),A
              INC       HL
              INC       DE
              DJNZ      V_MKPATH
              LD        (HL),'/'
              INC       HL
              LD        A,(CURDRV)
              AND       0FH
              ADD       A,'A'
              LD        (HL),A
              LD        HL,VFMLI                       ; GET_FILE_INFO on absolute path
              CALL      PRODOS
              OR        A
              JR        NZ,V_TRYNEXT
              LD        A,(VFTYPE)
              CP        0FH                            ; $0F is a ProDOS subdirectory
              JR        NZ,V_TRYNEXT
              POP       BC
              JR        V_FOUND
V_TRYNEXT     POP       BC
V_NEXT        LD        DE,16
              ADD       IX,DE
              DEC       B
              JP        NZ,V_SCAN
V_NOMATCH     LD        A,0FDH                         ; Prefix volume / CP/M dir not found
              RET
V_FOUND       LD        A,(IX+0)
              AND       0F0H                           ; ProDOS unit DSSS0000
              LD        (VRUNIT),A
              LD        A,1
              LD        (VUCVALID),A                   ; Keep it for ALL logical drives
              XOR       A
              RET

; Software R/O for current drive: BDOS 28, drive 0 -> bit 0, etc.
DRV_SETRO     LD        A,(CURDRV)
              AND       0FH
              LD        B,A
              LD        HL,0001H
              LD        A,B
              OR        A
              JR        Z,DSR_SET
DSR_LOOP      ADD       HL,HL
              DEC       A
              JR        NZ,DSR_LOOP
DSR_SET       LD        A,(ROVEC)
              OR        L
              LD        (ROVEC),A
              LD        A,(ROVEC+1)
              OR        H
              LD        (ROVEC+1),A
              XOR       A
              LD        L,A
              RET

; Return Z iff the FCB's effective drive is writable. Preserve DE, HL, BC.
; FCB drive=0 means CURDRV; 1..16 mean explicitly A:..P:.

; Return bitmap of read-only drives in HL
DRV_ROVEC     LD        HL,(ROVEC)                     ; Bit 0 of L is A:, bit 7 of H is P:
              RET

; Return pointer to Drive Parameter Block in HL
DRV_DPB       CALL      V_GETFREE                      ; Set DSM from real volume first
              LD        HL,DPB                         ; Pointer to drive parameter block
              RET

; Get/set user number
; E contains the user number to set, or 0FFH to get current user number
; If E is 0FFH then user number is returned in A
F_USERNUM     LD        A,E
              CP        0FFH
              JR        Z,FUNS1
              AND       00FH                           ; CP/M USER numbers modulo 16
              RLCA
              RLCA
              RLCA
              RLCA
              LD        B,A
              LD        A,(CURDRV)
              AND       00FH
              OR        B
              LD        (CURDRV),A
              XOR       A                              ; SET has no meaningful return value
              LD        L,A
              RET
FUNS1         LD        A,(CURDRV)
              RRCA
              RRCA
              RRCA
              RRCA
              AND       00FH                           ; no sign extension for user 8..15
              LD        L,A
              RET

; Random access read record
; DE contains address of FCB describing the file to read
; Return code in A and L:
; 0 success, 1 reading unwritten data, 4 reading unwritten extent,
; 6 rec number out of range, 9 invalid FCB, 10 media changed, 0FFH h/w err
F_READRAND    PUSH      DE                             ; Copy pointer to FCB ...
              POP       IX                             ; ...
              CALL      IO_BEGIN                       ; Reopen logical CP/M FCB if needed
              OR        A
              JR        Z,F_READR_GO
              JP        IO_END                         ; Close transient handle
F_READR_GO
              LD        A,(IX+0EH)                     ; Obtain file reference num from FCB S2
              LD        (SMMLIN),A                     ; Store in parameter list for SET_MARK
              LD        (FRMLIN),A                     ; Store in parameter list for READ

              CALL      RAND2MARK                      ; Set full 24-bit ProDOS position
              JR        NC,FRR_MARK_OK
              LD        A,6                            ; Record outside ProDOS's 24-bit range
              JP        IO_END
FRR_MARK_OK
              LD        HL,SMMLI                       ; Pass address of 6502 JSR instruction
              CALL      PRODOS                         ; Invoke ProDOS MLI - SET_MARK
              CP        4DH                            ; See if position was out of range
              JP        Z,FRRRUD                       ; If so, return reading unwritten data (1)
              CP        43H                            ; See if it was a bad file ref number
              JP        Z,FRRBFCB                      ; If so, return invalid FCB code (9)
              CP        0                              ; See if there was some other error
              JP        NZ,FRRERR                      ; If so, return code 0FFH (h/w error)

              LD        HL,(DMAADDR)                   ; Write data starting at DMA buffer addr
              LD        BC,OFFSET                      ; Convert to 6502 address
              ADD       HL,BC                          ; ...
              LD        (FRMLIDB),HL                   ; Store I/O buffer address in parm list
              CALL      READ128                        ; READ and pad a short record with ^Z
              CP        4CH                            ; See if it was EOF
              JR        Z,FRRRUD                       ; If so, return EOF code (1)
              CP        43H                            ; See if it was a bad file ref number
              JP        Z,FRBFCB                       ; If so, return invalid FCB code (9)
              CP        0                              ; See if there was some other error
              JR        NZ,FRRERR                      ; If so, return code 0FFH (h/w error)

              CALL      RANDEXT                        ; publish EX/S2/CR after success

              XOR       A                              ; Zero for success
              JP        IO_END                         ; Close transient handle
FRRRUD        LD        A,1                            ; Reading unwritten data return code
              JP        IO_END                         ; Close transient handle
FRRBFCB       LD        A,9                            ; Invalid FCB return code
              JP        IO_END                         ; Close transient handle
FRRERR        LD        A,0FFH                         ; All other errors are 0FFH
              JP        IO_END                         ; Close transient handle

; Random access write record
; DE contains address of FCB describing the file to write
; Return code in A and L:
; 0 success, 1 reading unwritten data, 4 reading unwritten extent,
; 6 rec number out of range, 9 invalid FCB, 10 media changed, 0FFH h/w err
F_WRITERAND   CALL      DCHKRO
              JP        NZ,RODENY
              PUSH      DE                             ; Copy pointer to FCB ...
              POP       IX                             ; ...
              CALL      IO_BEGIN                       ; Reopen logical CP/M FCB if needed
              OR        A
              JR        Z,F_WRTR_GO
              JP        IO_END                         ; Close transient handle
F_WRTR_GO
              LD        A,(IX+0EH)                     ; Obtain file reference num from FCB S2
              LD        (GEMLIN),A                     ; Store in parameter list for GET_EOF
              LD        (SEMLIN),A                     ; Store in parameter list for SET_EOF
              LD        (SMMLIN),A                     ; Store in parameter list for SET_MARK
              LD        (FWMLIN),A                     ; Store in parameter list for WRITE

              LD        HL,GEMLI                       ; Pass address of 6502 JSR instruction
              CALL      PRODOS                         ; Invoke ProDOS MLI - GET_EOF
              OR        A                              ; A nonzero means GEMLIE1..3 are invalid
              JP        NZ,FWRERR                      ; IO_END releases transient handle

              CALL      RAND2MARK                      ; Full 24-bit offset, carry if out of range
              JR        NC,FWR_MARK_OK
              LD        A,6
              JP        IO_END
FWR_MARK_OK
              ; Compare 24-bit EOF against requested position.
              LD        A,(GEMLIE1)
              LD        HL,SMMLIP1
              SUB       (HL)
              INC       HL
              LD        A,(GEMLIE2)
              SBC       A,(HL)
              INC       HL
              LD        A,(GEMLIE3)
              SBC       A,(HL)
              JR        NC,FWRS1

              LD        HL,(SMMLIP1)
              LD        (SEMLIE1),HL
              LD        A,(SMMLIP3)
              LD        (SEMLIE3),A
              LD        HL,SEMLI                       ; Pass address of 6502 JSR instruction
              CALL      PRODOS                         ; Invoke ProDOS MLI - SET_EOF
              OR        A                              ; On failure, do NOT attempt SET_MARK/WRITE
              JP        NZ,FWRERR                      ; IO_END releases transient handle

FWRS1         LD        HL,SMMLI                       ; Pass address of 6502 JSR instruction
              CALL      PRODOS                         ; Invoke ProDOS MLI - SET_MARK
              CP        4DH                            ; See if position was out of range
              JP        Z,FWRBFCB                      ; If so, return invalid FCB code (9)
              CP        43H                            ; See if it was a bad file ref number
              JP        Z,FWRBFCB                      ; If so, return invalid FCB code (9)
              CP        0                              ; See if there was some other error
              JP        NZ,FWRERR                      ; If so, return code 0FFH (h/w error)

              LD        HL,(DMAADDR)                   ; Get DMA buffer address
              LD        BC,OFFSET                      ; Convert to 6502 address
              ADD       HL,BC                          ; ...
              LD        (FWMLIDB),HL                   ; Store I/O buffer address in parm list
              LD        HL,FWMLI                       ; Pass address of 6502 JSR instruction
              CALL      PRODOS                         ; Invoke ProDOS MLI - WRITE
              CP        43H                            ; See if it was a bad file ref number
              JR        Z,FWRBFCB                      ; If so, return invalid FCB code (9)
              CP        48H                            ; See if it was a bad file ref number
              JR        Z,FWRDF                        ; If so, return invalid FCB code (9)
              CP        0                              ; See if there was some other error
              JR        NZ,FWRERR                      ; If so, return code 0FFH (h/w error)

              CALL      RANDEXT                        ; publish EX/S2/CR after success

              ; The WRITE succeeded: ask ProDOS for its new EOF, then publish
              ; an extent-correct RC.  Never report a failed post-write GET_EOF
              ; as a failed WRITE (which could provoke a destructive retry).
              ; Internal raw ProDOS FCBs do not carry virtual CP/M extents.
              CALL      RCRANDWRITE                   ; compute RC without growing resident code
              XOR       A                              ; Zero for success
              JP        IO_END                         ; Restore application-owned S2
FWRBFCB       LD        A,9                            ; Invalid FCB return code
              JP        IO_END                         ; Close transient handle
FWRDF         LD        A,2                            ; Disk fill return code
              JP        IO_END                         ; Close transient handle
FWRERR        CP        04EH
              JR        Z,FWRRO
              LD        A,0FFH                         ; All other errors are 0FFH
              JP        IO_END                         ; Close transient handle
FWRRO         LD        A,0FFH
              CALL      IO_END
              JP        ROFILE


; Compute file size (BDOS function 35) from the exact ProDOS EOF.
; DE points to the caller's FCB.  On success, update FCB offsets
; 21H..23H with ceil(EOF/128), little endian (24-bit record count).
; A=L=0 on success, A=L=FFH on error.  Do not alter the FCB otherwise.
;
; GET_FILE_INFO does not return EOF, so temporarily OPEN the file,
; GET_EOF, then CLOSE it.  Reuse a free I/O buffer from the two usable slots,
; but do not claim a slot or alter the caller's S2 / open-file state.
; Only the randomly accessed file's FCB is updated; DMAADDR is untouched.
F_SIZE        PUSH      DE                             ; Keep FCB pointer across ProDOS calls
              LD        IX,PATHBUF                     ; FCB2PATH needs its destination in IX
              CALL      FCB2PATH
              CALL      CACHEFND
              OR        A
              JR        Z,FS_TEMP
              LD        (CMRU),A
              PUSH      AF
              LD        HL,CHITS
              CALL      CINC16
              POP       AF
              CALL      CACHEREF
              LD        (GEMLIN),A
              LD        HL,GEMLI
              CALL      PRODOS
              OR        A
              JP        NZ,FSERRPOP
              JP        FS_MATH
FS_TEMP       CALL      CACHEFREE                      ; Only open temporarily on a miss
              CP        0FFH
              JP        Z,FSERRPOP
              LD        BC,OFFSET                      ; Convert Z80 to 6502 buffer address
              ADD       HL,BC
              LD        (FOMLII),HL
              LD        HL,FOMLI                       ; ProDOS OPEN
              CALL      PRODOS
              OR        A
              JP        NZ,FSERRPOP                    ; No file opened: nothing to close

              LD        A,(FOMLIN)                     ; Temporary ProDOS reference number
              LD        (GEMLIN),A
              LD        (FCMLIN),A
              LD        HL,GEMLI                       ; ProDOS GET_EOF, 24-bit byte count
              CALL      PRODOS
              PUSH      AF                             ; Save GET_EOF result across CLOSE
              LD        HL,FCMLI                       ; Always CLOSE the temporary file
              CALL      PRODOS
              LD        B,A                            ; CLOSE error, if any
              POP       AF
              OR        A
              JP        NZ,FSERRPOP                    ; GET_EOF failed
              LD        A,B
              OR        A
              JP        NZ,FSERRPOP                    ; CLOSE failed

FS_MATH                     ; Shift 24-bit EOF right 7 to obtain 128-byte records.
              ; A:H:L is the 24-bit value (high:middle:low).
              ; E remembers whether the discarded low 7 bits are nonzero.
              LD        A,(GEMLIE1)
              LD        L,A
              AND       7FH
              LD        E,A
              LD        A,(GEMLIE2)
              LD        H,A
              LD        A,(GEMLIE3)
              LD        B,7
FS_SHIFT      SRL       A
              RR        H
              RR        L
              DJNZ      FS_SHIFT
              LD        C,A                            ; High byte of record count
              LD        A,E                            ; Round up partial final record
              OR        A
              JR        Z,FS_STORE
              INC       HL
              LD        A,H
              OR        L
              JR        NZ,FS_STORE
              INC       C                              ; Carry into 3rd record-count byte
FS_STORE      POP       DE                             ; Original caller's FCB
              PUSH      DE
              POP       IX
              LD        (IX+21H),L                     ; R0 (LSB)
              LD        (IX+22H),H                     ; R1
              LD        (IX+23H),C                     ; R2 (MSB)
              XOR       A
              LD        L,A
              RET
FSERRPOP      POP       DE                             ; Leave FCB unchanged on failure
              LD        A,0FFH
              LD        L,A
              RET

; BDOS 36: compute the NEXT sequential record position in R0..R2.
; Do not subtract one: applications wanting the previous record do so
; explicitly.  S2 belongs to the application outside ProDOS I/O.
F_RANDREC     JP        RNEXT36                       ; extent-aware BDOS 36 relocated

; Selectively reset disk drives
; DE contains bitmap of drives to reset (bit 0 of E if A:, bit 7 of D is P:)
; Returns A=00H if okay, A=FFH if error
; Resetting means removing the read-only status
DRV_RESET     LD        A,E
              CPL
              LD        B,A
              LD        A,(ROVEC)
              AND       B
              LD        (ROVEC),A
              LD        A,D
              CPL
              LD        B,A
              LD        A,(ROVEC+1)
              AND       B
              LD        (ROVEC+1),A
              ; A selective reset also invalidates the login bits.
              ; Preserve the requested DE mask (and other drive bits).
              LD        A,E
              CPL
              LD        B,A
              LD        A,(LOGVEC)
              AND       B
              LD        (LOGVEC),A
              LD        A,D
              CPL
              LD        B,A
              LD        A,(LOGVEC+1)
              AND       B
              LD        (LOGVEC+1),A
              CALL      S8INVAL                        ; reset invalidates this tab's search
              XOR       A
              LD        L,A
              RET

; Make a ProDOS MLI call
; Address of 6502 JSR instruction in front of ProDOS parameter list is
; passed in in register pair HL, in Z80 address space
; Return code is passed back in A
PRODOS        LD        BC,OFFSET                      ; Add offset to convert Z80->6502 address
              ADD       HL,BC                          ; ...
              LD        (ADDR),HL                      ; Store it for 6502
              LD        A,2                            ; CMD=2 means ProDOS MLI call
              LD        (CMD),A                        ; ...
              LD        (SOFTCARD),A                   ; Do it!
              LD        A,(AREG)                       ; Get return code from the MLI call
              RET

; Populate the PATH buffer (and PATHLEN) by copying from FCB
; If the FCB contains A:TEST____.TXT then the PATH buffer will be A/TEST.TXT
; Unrepresentable 8.3 names are escaped as Z.<13 base36 digits>
; DE contains a pointer to the FCB
; IX contains pointer to the path buffer into which to write
FCB2PATH      PUSH      IX
              POP       IY                             ; IY points to Pascal length
              INC       IX                             ; IX points to first pathname byte
              LD        A,(DE)
              OR        A
              JR        NZ,F2P_DRV
              LD        A,(CURDRV)
              AND       00FH
              INC       A
F2P_DRV       ADD       A,'A'-1
              LD        (IX+0),A
              INC       IX
              LD        C,1                            ; number of pathname prefix bytes
              CALL      F2P_USER                       ; A=bound user for open FCB; else current
              OR        A
              JR        Z,F2P_SLASH
              CP        10
              JR        C,F2P_ONED
              SUB       10
              PUSH      AF
              LD        (IX+0),'1'
              INC       IX
              INC       C
              POP       AF
F2P_ONED      ADD       A,'0'
              LD        (IX+0),A
              INC       IX
              INC       C
F2P_SLASH     LD        (IX+0),'/'
              INC       IX
              INC       C
              LD        H,D
              LD        L,E
              INC       HL                             ; FCB first name char
              LD        A,(HL)
              AND       07FH
              CP        ' '
              JP        Z,F2PS7                        ; open directory (blank filename)
              CALL      B69PTH
              OR        A
              RET       NZ                             ; escaped path, dynamic prefix included
              LD        B,8
F2PL1         LD        A,(HL)
              AND       07FH
              CP        ' '
              JR        Z,F2PS3
              LD        (IX+0),A
              INC       C
              INC       HL
              INC       IX
              DJNZ      F2PL1

F2PS3                       ; An empty extension has no dot (and never reads beyond FCB).
              PUSH      HL
              LD        HL,9
              ADD       HL,DE                          ; FCB first extension character
              LD        A,(HL)
              AND       07FH
              POP       HL
              CP        ' '
              JP        Z,F2PS7
F2PL2         LD        A,(HL)                         ; Read next character from FCB
              AND       07FH
              CP        ' '                            ; Is it space?
              JR        NZ,F2PS4                       ; If not, we are done eating!
              INC       HL                             ; Otherwise advance to next char
              JR        F2PL2                          ; And loop

F2PS4         LD        A,'.'                          ; Separator is a period
              LD        (IX+0),A                       ; Write to buffer
              INC       C                              ; Count the character!
              INC       IX                             ; Advance to next character in buffer
              LD        B,0                            ; Use B to track num chars in extension

              ; Handle the extension - up to 3 characters
F2PL3         LD        A,B                            ; Number of extension chars copied
              CP        3                              ; Maximum of three
              JR        Z,F2PS7
              LD        A,(HL)                         ; Obtain extension character
              AND       07FH
              CP        ' '                            ; End of extension?
              JR        Z,F2PS7
              LD        (IX+0),A                       ; Copy to PATH buffer (no lossy $/8 swap)
              INC       C                              ; Overall character count
              INC       B                              ; Extension character count
              INC       HL                             ; Next byte of filename in FCB
              INC       IX                             ; Next byte of PATH buffer
              JR        F2PL3

F2PS7         LD        A,C                            ; Store length of string
              LD        (IY+0),A                       ; We kept size byte in IY at start
              RET                                      ;

; Clear FCB pointed to by DMAADDR
CLRFCB        LD        HL,(DMAADDR)                   ; 16-byte CP/M FCB header to zero
              LD        C,16
              XOR       A
CFL1          LD        (HL),A
              INC       HL
              DEC       C
              JR        NZ,CFL1
              LD        HL,(DMAADDR)                   ; FCB name/extension padded with spaces
              INC       HL
              LD        C,11
              LD        A,' '
CFL2          LD        (HL),A
              INC       HL
              DEC       C
              JR        NZ,CFL2
              RET

; This operation is almost the inverse of FCB2PATH.  It takes a pointer to the
; beginning of the ProDOS dirent and converts it to FCB format (8.3 with
; spaces for any unused characters.)
; Z.<13 base36> ProDOS escapes are decoded into exact CP/M 8.3 fields.
; Handles '*' wildcard character
; HL points to the file entry in the ProDOS directory
; B contains the drive number (1 for A:, 2 for B: etc)
; C controls whether file size is populated in FCB (C=0 disables file size)
; The FCB is written to the buffer pointed to by DMAADDR
; Trashes pretty much all registers (except IX, IY)
NAME2FCB      XOR       A
              LD        (B69BAD),A                     ; only directory search cares about BAD
              PUSH      BC                             ; We will need C later
              PUSH      HL                             ; Remember source ProDOS dir entry for EOF
              EX        DE,HL                          ; Stash HL in DE for call to CLRFCB
              CALL      CLRFCB                         ; Clear FCB at DMAADDR
              EX        DE,HL                          ; Get file entry pointer back in HL

              LD        A,(HL)                         ; Obtain first char of ProDOS dirent
              AND       0FH                            ; Mask to obtain length of the name
              LD        C,A                            ; Stash source character count in C
              LD        DE,(DMAADDR)                   ; Initialize DE as write pointer
              LD        A,B                            ; Move drive number to A
              LD        (DE),A                         ; Write drive number
              LD        B,0                            ; Use B to count chars written

              ; Only 15-character names may use the Z.<13> escape.
              LD        A,C
              CP        15
              JR        NZ,N2FL1
              PUSH      BC
              PUSH      HL
              PUSH      DE
              CALL      B69TRY
              POP       DE
              POP       HL
              POP       BC
              OR        A
              JP        Z,N2FS6                        ; decoded a valid CP/M FCB
              CP        1
              JP        NZ,N2FS6                       ; malformed alias (B69BAD set)
N2FL1         INC       HL                             ; Advance source pointer
              INC       DE                             ; Advance destination pointer
              LD        A,C                            ; Get count of chars remaining
              CP        0                              ; If none left ...
              JP        Z,N2FS6                        ; We are done
              LD        A,B                            ; Get count of chars written
              CP        8+3                            ; If 8+3 chars have been written ...
              JP        Z,N2FS6                        ; We are done
              LD        A,(HL)                         ; Read character
              CP        ':'                            ; See if it is a colon - terminates filename
              JR        Z,N2FS6                        ; Prepare to copy the extension
              CP        '.'                            ; See if it is a period
              JR        Z,N2FS2                        ; Prepare to copy the extension
              CP        '*'                            ; See if it is an asterix
              JR        Z,N2FS3                        ; Handle asterix wildcard
              LD        (DE),A                         ; Write character verbatim
              INC       B                              ; Increment count of chars written
N2FS1         DEC       C                              ; Decrement count of chars remaining
              JP        N2FL1                          ; Loop

              ; Initialize DE, B to start processing the extension
N2FS2         LD        DE,(DMAADDR)                   ; Destination is start of extension
              INC       DE                             ;
              INC       DE                             ;
              INC       DE                             ;
              INC       DE                             ;
              INC       DE                             ;
              INC       DE                             ;
              INC       DE                             ;
              INC       DE                             ;
              LD        B,8                            ; 8 chars have been written
              JR        N2FS1                          ; Jump back into the read-write loop

              ; Handle asterix wildcard character
N2FS3         LD        A,B                            ; See how many chars have been written
              CP        8                              ; >=8? If so we are in the extension
              JR        C,N2FS4                        ; If in main filename (not extension)

              ; Asterix in extension
N2FL2         LD        A,'?'                          ; We will write '?' to rest of extension
              LD        (DE),A                         ; Write character
              INC       DE                             ; Increment write pointer
              INC       B                              ; Increment character count
              LD        A,B                            ; See if we are done
              CP        8+3                            ; Filename+extension
              JR        Z,N2FS6                        ; We are done
              JR        N2FL2                          ; Loop

N2FS4                       ; Asterix in main filename
N2FL3         LD        A,'?'                          ; We will write '?' to rest of filename
              LD        (DE),A                         ; Write character
              INC       DE                             ; Increment write pointer
              INC       B                              ; Increment character count
              LD        A,B                            ; See if we are done
              CP        8                              ; Filename+extension
              JR        Z,N2FS5                        ; We are done - eat chars up until '.'
              JR        N2FL3                          ; Loop

N2FS5                       ; Eat rest of chars up until '.'
N2FL4         LD        A,(HL)                         ; Get character
              CP        '.'                            ; See if it is a period
              JP        Z,N2FS2                        ; If so, go process the extension
              INC       HL                             ; Increment source pointer
              DEC       C                              ; Decrement count of chars remaining
              LD        A,C                            ; Get count of chars remaining
              CP        0                              ; If none left ...
              JR        Z,N2FS6                        ; We are done
              JR        N2FL4                          ; Loop

              ; Handle file size info
N2FS6         POP       HL                             ; Source ProDOS file entry
              POP       BC                             ; Original size-request flag in C
              LD        A,C
              OR        A
              RET       Z                              ; FCB for parsing only; don't touch allocation bytes

              ; ProDOS dir entry +$1E is access; bit 1 permits writing.
              ; Reflect a locked file in the high bit of FCB+9 (T1').
              PUSH      HL
              LD        DE,01EH
              ADD       HL,DE
              LD        A,(HL)
              AND       02H
              JR        NZ,N2FADON
              LD        HL,(DMAADDR)
              LD        DE,9
              ADD       HL,DE
              LD        A,(HL)
              OR        080H
              LD        (HL),A
N2FADON
              POP       HL

              ; ProDOS file entry EOF is a 24-bit little-endian byte count
              ; at offsets 21..23. blocks_used includes sapling/tree
              ; index blocks and is *not* the logical length.
              LD        DE,21
              ADD       HL,DE
              LD        E,(HL)                         ; EOF low byte
              INC       HL
              LD        D,(HL)                         ; EOF middle byte
              INC       HL
              LD        B,(HL)                         ; EOF high byte

              ; ProDOS EOF is 24-bit. For nonempty files, EOF-1 identifies
              ; the final occupied 128-byte record and its logical extent.
              ;   extent = (EOF-1) >> 14          (0..1023)
              ;   EX = extent & 31, S2 = extent >> 5
              ;   RC = (((EOF-1) & $3FFF) >> 7) + 1
              ; Subtracting one handles exact 16K boundaries (RC=128).
              ; At EOF=0 return the single empty extent (EX=S2=RC=0).
              LD        HL,(DMAADDR)
              PUSH      HL
              POP       IX
              LD        A,B
              OR        D
              OR        E
              JR        Z,N2FZERO
              LD        A,E
              OR        A
              JR        NZ,N2FDECLO
              LD        A,D
              OR        A
              JR        NZ,N2FDECMID
              DEC       B
N2FDECMID     DEC       D
N2FDECLO      DEC       E
              ; low five bits of extent = (B[2:0]<<2) | D[7:6]
              LD        A,D
              RLCA
              RLCA
              AND       03H
              LD        C,A
              LD        A,B
              AND       07H
              ADD       A,A
              ADD       A,A
              OR        C
              LD        (IX+0CH),A
              ; high five bits of extent = B[7:3]
              LD        A,B
              SRL       A
              SRL       A
              SRL       A
              LD        (IX+0EH),A
              ; records in last extent = ((D[5:0]<<1) | E[7]) + 1
              LD        A,D
              ADD       A,A
              AND       07EH
              LD        C,A
              LD        A,E
              RLCA
              AND       01H
              OR        C
              INC       A
              JR        N2FPUTRC
N2FZERO       LD        (IX+0CH),0
              LD        (IX+0EH),0
              XOR       A
N2FPUTRC      LD        (IX+0FH),A
              CALL      N2FMAP                        ; eight 16-bit fake blocks max
              RET

; Generate a synthetic CP/M 2.2 allocation map in the directory FCB.
; A = records in THIS extent (0..128), DMAADDR = returned FCB.
; DPB has 2 KB allocation blocks, 2-byte block numbers (DSM=511).
; Thus 16 records per block, 8 entries per extent.
; Fake block IDs 1..8 are intentionally reused for each file/extent:
; sufficient for STAT's per-file size column, NOT a filesystem allocator.
; Overwrites ALL 16 map bytes, so no separate clearing pass is needed.
; Trashes AF, BC, DE, HL; preserves IX and IY.
; N2FMAP relocated to spare MAIN space after SEARCH_EOF.


; Read 512 byte block of directory
; Used by F_SFIRST and F_SNEXT
; Trashes HL + registers trashed by F_READ (best to assume all of them!)
; Returns A=0 for success, A=0FFH on error
RDDIRBLK      LD        HL,(DMAADDR)                   ; Preserve caller's DMA address
              PUSH      HL
              LD        HL,DIRBUF1                     ; Four consecutive 128-byte record buffers
              LD        B,4
RDBREAD       PUSH      BC                             ; F_READ may destroy registers
              PUSH      HL
              LD        (DMAADDR),HL
              LD        DE,DFCB
              CALL      F_READ
              POP       HL
              POP       BC
              OR        A                              ; 0=success, any other status=error
              JR        NZ,RDBS1
              LD        DE,128
              ADD       HL,DE
              DJNZ      RDBREAD

              ; Every directory block starts with two link pointers ($00-$03).
              ; A zero previous-block pointer identifies the key block, whose
              ; first 39-byte entry ($04-$2A) is the directory header.
              ; Count that header as entry 1 of 13; scan 12 actual files.
              ; Other blocks contain 13 files beginning at offset $04.
              LD        HL,DIRBUF+4
              XOR       A
              LD        (CDBCOUNT),A
              LD        A,(DIRBUF)
              LD        B,A
              LD        A,(DIRBUF+1)
              OR        B
              JR        NZ,RDBPTR
              LD        HL,DIRBUF+DIRHDSZ
              LD        A,1
              LD        (CDBCOUNT),A
RDBPTR        LD        (CDBPTR),HL
              XOR       A                              ; Return code for success
              JR        RDBS2                          ; Successful return

RDBS1         LD        A,0FFH                         ; Error return code

RDBS2         POP       HL                             ; Reset DMA address as we found it
              LD        (DMAADDR),HL                   ; ...
              RET

; Match FCBs
; Used by CHKDIRENT
; DE is the address of the FCB describing the file to look for
; Compare with FCB at DMAADDR already created by NAME2FCB
; Returns A=0 if entry matches, A=FFH if no match
; Trashes A,BC,DE,HL
MATCHFCB      INC       DE                             ; Skip drive byte
              LD        HL,(DMAADDR)
              INC       HL
              LD        B,11                           ; 8.3 filename bytes
MFL1          LD        A,(DE)
              AND       07FH                           ; Ignore CP/M attribute high bits
              CP        '?'                            ; Wildcard matches any byte
              JR        Z,MFS1
              LD        C,A
              LD        A,(HL)
              AND       07FH
              CP        C
              JR        NZ,MFS2
MFS1          INC       DE
              INC       HL
              DJNZ      MFL1
              XOR       A
              RET
MFS2          LD        A,0FFH
              RET

; Compare a ProDOS directory file entry to see if it matches
; Used by F_SFIRST and F_SNEXT
; DE is the address of the FCB describing the file to look for
; HL points to the first file entry in the ProDOS directory
; Returns A=0 if entry matches, A=FFH if no match
CHKDIRENT     LD        B,0                            ; Hardcode drive A: MATCHFCB ignores it
              LD        A,(HL)                         ; Get first byte of file entry
              AND       0FH                            ; Mask to get the filename length
              CP        0                              ; If zero ...
              JR        Z,CDES1                        ; File is deleted - no match
              PUSH      HL                             ; Preserve HL
              PUSH      DE                             ; Preserve DE
              LD        C,1                            ; Do check file sizes and put in FCB
              CALL      NAME2FCB                       ; Create FCB in DMA buffer
              POP       DE                             ; Recover DE
              POP       HL                             ; Recover HL
              LD        A,(B69BAD)                     ; malformed escaped entry cannot match
              OR        A
              JR        NZ,CDES1
              PUSH      HL                             ; Preserve HL
              PUSH      DE                             ; Preserve DE
              CALL      MATCHFCB                       ; Compare search FCB w/ FCB in DMA buffer
              POP       DE                             ; Recover DE
              POP       HL                             ; Recover HL
              RET                                      ; MATCHFCB returns 0 or $FF
CDES1         LD        A,0FFH                         ; Deleted entry
              RET

; Search a 512-byte ProDOS directory block, returning synthetic 32-byte
; CP/M 2.2 extents (EXM=0). The caller's search FCB remains untouched.
; A ProDOS file is one directory entry but may span 1024 logical CP/M
; extents; track the current extent index in CDBEXT (16 bits).
; FFFF means this dirent has not yet emitted its highest extent.
; Once extent zero has been returned, the next SEARCH NEXT advances to
; the following ProDOS dirent. This includes zero-length files.
; For a concrete search EX 0..31, return that exact (S2=0) extent once.
; For EX='?', enumerate EVERY extent, highest first, including zero.
CHKDIRBLK
CDBL1         LD        HL,(CDBPTR)
              CALL      CHKDIRENT                      ; fill DMA synthetic FCB
              OR        A
              JR        NZ,CDB_NEXT                    ; deleted/name mismatch
              PUSH      DE
              POP       IX                             ; search FCB
              LD        A,(IX+0CH)
              CP        '?'
              JR        Z,CDB_WILD
              CP        020H                           ; only EX 0..31 can match S2=0
              JR        NC,CDB_NEXT
              CALL      CDB_EXACT                      ; requested extent in A
              OR        A
              JR        NZ,CDB_NEXT
              CALL      CDB_ADV                        ; exact match: don't repeat forever
              JR        CDB_MATCH

CDB_WILD      LD        HL,(CDBEXT)
              LD        A,H
              AND       L
              CP        0FFH
              JR        Z,CDB_FIRST
              LD        A,H
              OR        L
              JR        Z,CDB_NEXT                    ; extent zero was already emitted
              DEC       HL
              LD        (CDBEXT),HL
              LD        DE,(DMAADDR)
              PUSH      DE
              POP       IY
              CALL      CDB_STOREFULL                  ; earlier extent is complete
              JR        CDB_MATCH

CDB_FIRST     LD        HL,(DMAADDR)
              PUSH      HL
              POP       IY
              CALL      CDB_GETEXT                    ; highest logical extent from EX/S2
              LD        (CDBEXT),HL
              JR        CDB_MATCH                     ; keep last-extent RC and block map

CDB_NEXT      CALL      CDB_ADV
              LD        A,(CDBCOUNT)
              CP        ENTPERBLK
              JP        C,CDBL1
              LD        A,0FFH
              RET
CDB_MATCH     XOR       A
              RET

; Advance the ProDOS pointer once; reset synthetic-extent enumeration.
; For an exact-extent match this must happen before returning the entry.
CDB_ADV       LD        HL,(CDBPTR)
              LD        BC,FILEENTSZ
              ADD       HL,BC
              LD        (CDBPTR),HL
              LD        A,(CDBCOUNT)
              INC       A
              LD        (CDBCOUNT),A
              LD        HL,0FFFFH
              LD        (CDBEXT),HL
              RET

; EX/S2 from current synthetic FCB -> HL logical extent number 0..1023.
; IY points to the synthetic entry at DMAADDR. May clobber DE.
CDB_GETEXT    LD        A,(IY+0EH)
              AND       01FH
              LD        L,A
              LD        H,0
              ADD       HL,HL
              ADD       HL,HL
              ADD       HL,HL
              ADD       HL,HL
              ADD       HL,HL
              LD        A,(IY+0CH)
              AND       01FH
              LD        E,A
              LD        D,0
              ADD       HL,DE
              RET

; For an earlier (always full) extent store EX/S2 and RC=128;
; its synthetic allocation map contains eight 2KB blocks.
; Input HL=index 0..1023, IY points to output FCB.
CDB_STOREFULL LD        A,L
              AND       01FH
              LD        (IY+0CH),A
              LD        A,H
              ADD       A,A
              ADD       A,A
              ADD       A,A
              LD        B,A
              LD        A,L
              SRL       A
              SRL       A
              SRL       A
              SRL       A
              SRL       A
              OR        B
              LD        (IY+0EH),A
              LD        A,080H
              LD        (IY+0FH),A
              JP        N2FMAP

; Non-wildcard EX 0..31: return exactly that extent in S2=0,
; unless the file is too short to have it. Never report the highest
; extent of an unrelated size: ordinary CP/M searches usually use EX=0.
; Input A=requested EX; output A=0 if present, FF if beyond EOF.
CDB_EXACT     LD        B,A
              LD        HL,(DMAADDR)
              PUSH      HL
              POP       IY
              LD        A,(IY+0EH)
              OR        A
              JR        NZ,CDB_EXFULL                  ; file extends past 512KB
              LD        A,(IY+0CH)
              CP        B
              JR        C,CDB_EXMISS
              JR        Z,CDB_EXLAST                   ; final extent: keep its RC/map
CDB_EXFULL    PUSH      BC
              LD        A,080H
              LD        (IY+0FH),A
              CALL      N2FMAP
              POP       BC
CDB_EXLAST    LD        (IY+0CH),B
              LD        (IY+0EH),0                     ; CP/M search S2 is zero
              XOR       A
              RET
CDB_EXMISS    LD        A,0FFH
              RET

CDBPTR        DEFW      0000H                          ; next ProDOS dir entry
CDBCOUNT      DEFB      0                              ; entries consumed in block
CDBEXT        DEFW      0FFFFH                         ; 10-bit logical extent or sentinel

; Find IOBUF address for a file reference number
; Scan only FRN1..FRN2: third 1K region is spare, fourth is stack.
; If found, return FRN slot# 1 or 2 in A, I/O buffer address in HL
; If not found, return A=0FFH
; Trashes BC
GETIOADDR     LD        B,A                            ; Requested FRN (0 = first free slot)
              LD        HL,FRN1                        ; FRN1 and FRN2 only
              LD        C,1                            ; One-based slot number
GIASCAN       LD        A,(HL)
              CP        B
              JR        Z,GIAFOUND
              INC       HL
              INC       C
              LD        A,C
              CP        3
              JR        NZ,GIASCAN
              LD        A,0FFH
              RET
GIAFOUND      LD        A,C                            ; Return slot 1 or 2 in A
              PUSH      AF
              DEC       A                              ; Buffer address = $9800 + (slot-1)*$400
              ADD       A,A
              ADD       A,A
              LD        HL,IOBUF1
              ADD       A,H
              LD        H,A
              POP       AF
              RET

; Form 24-bit ProDOS byte mark from random FCB record R0/R1/R2.
; ProDOS supports byte offsets < $1000000, hence record <= $1FFFF.
; Returns carry set for out-of-range random records.
RAND2MARK     LD        A,(IX+23H)
              CP        2
              JR        NC,RAND_MARK_BAD
              LD        B,A
              LD        A,(IX+21H)
              LD        C,A
              AND       1
              RRCA
              LD        (SMMLIP1),A
              LD        A,C
              SRL       A
              LD        C,A
              LD        A,(IX+22H)
              AND       1
              RRCA
              OR        C
              LD        (SMMLIP2),A
              LD        A,(IX+22H)
              SRL       A
              LD        C,A
              LD        A,B
              AND       1
              RRCA
              OR        C
              LD        (SMMLIP3),A
              OR        A                              ; Clear carry
              RET
RAND_MARK_BAD SCF
              RET

; Retired extent conversion routines removed in Stage 27.
; Stage 27: removed unused code/data (Unused extent-to-record converter).
; Stage 27: removed unused code/data (Unused record-to-extent converter).
; Compact diagnostic helper: print C as [XX] without a four-digit
; conversion buffer.  Preserve registers as the old PRHEX did.
PRHEX         PUSH      AF
              PUSH      BC
              PUSH      DE
              PUSH      HL
              LD        E,'['
              CALL      C_WRITE
              LD        A,C
              RRCA
              RRCA
              RRCA
              RRCA
              CALL      PHNYB
              LD        A,C
              CALL      PHNYB
              LD        E,']'
              CALL      C_WRITE
              POP       HL
              POP       DE
              POP       BC
              POP       AF
              RET
PHNYB         AND       0FH
              ADD       A,'0'
              CP        3AH                            ; One past ASCII '9'
              JR        C,PHOUT
              ADD       A,7
PHOUT         LD        E,A
              JP        C_WRITE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Compact CP/M 2.2-style CCP
;
; Commands:
; - d:           - Change default drive (A:, B: etc.)
; - DIR          - Show directory (DIR, DIR A:, DIR FOO.TXT, DIR *.COM)
; - ERA          - Erase file(s) (ERA FOO.TXT, ERA F*.TXT)
; - REN          - Rename file (REN BAR.TXT=FOO.TXT)
; - SAVE         - Save 256-byte pages of TPA (SAVE 7 FOO.COM)
; - TYPE         - Show text file on console (TYPE TEST.TXT)
; - BYE          - Confirm and exit to the ProDOS selector
; - TERM VT100/SOROC/H19/H89/VT52 - Set terminal personality (no .COM needed)
; - CACHE        - Show ProDOS handle-cache counters (CACHE RESET to zero)
; - CLS          - Reset video state, clear screen and home cursor
; - TAB          - [LIST|HELP|N [SUSPEND|RESUME|EXCLUSIVE|KILL]]
; - HELP         - List available CCP built-in commands
; - XSUB         - Enables app input redirection inside SUBMIT only
; - USER [n]     - Display/select user area (0..15)
; - FILENAME.COM - Load and run FILENAME.COM at 0100H
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Built-in argument counts and common filename mistakes are validated.
; Full CP/M filename grammar is not yet enforced.

; Get a line of text from the console & handle it
CCP
; MAIN no longer reads commands. All interactive command entry is AUX CCP.COM.
; Retain the scheduler loop: a task can be parked on console input, and
; hotkeys can select a different tab while it is suspended.
SHMAIN        CALL      SCHMAIN
              CALL      TBAUTOSW
              CALL      TSKACTIVE
              OR        A
              JR        NZ,SHMAIN
              CALL      SBWGET
              OR        A
              JP        NZ,BDOSWARM
              CALL      SHPTR
              LD        A,(HL)
              OR        A
              JR        NZ,SHMAIN                     ; shell/child is still under supervision
; Only a missing or exited CCP reaches here. Never automatically relaunch
; a missing program: allow the disk to be fixed or leave for ProDOS.
SHRECOVER     LD        DE,SHRECMSG
              CALL      C_WRITESTR
SHRECPROMPT   LD        DE,SHRECPR
              CALL      C_WRITESTR
SHRECINPUT    CALL      C_READ
              AND       0DFH
              CP        'R'
              JR        Z,SHRETRY
              CP        'B'
              JR        NZ,SHRECINPUT
              LD        E,13
              CALL      C_WRITE
              CALL      CCPBYE                        ; existing confirmed ProDOS exit
              JR        SHRECPROMPT                   ; user declined BYE
SHRETRY       LD        E,13
              CALL      C_WRITE
              CALL      SHNEW
              JP        SHMAIN
SHRECMSG      DEFB      13
              DEFM      'A:CCP.COM unavailable or exited'
              DEFB      13,'$'
SHRECPR       DEFM      '[R]etry or [B]YE to ProDOS? $'

; F8 ID 10: request the next SUBMIT command (if any) for AUX CCP.
; AXBUILT has already copied 80 bytes from BXTAIL into MAIN FILEBUF;
; its first two bytes are an AUX pointer to INBUF+1 (count and chars).
; We use the existing CCPSUB/SBNEXT routines, so XSUB stays linked
; to the submitted command rather than creating a second reader.
AXBEXTRA      CP        10
              JP        Z,AXBSUBMIT
              CP        11
              JP        Z,AXHSTORE
              CP        12
              JP        Z,AXHLOAD
              JP        CCPBAD
AXBSUBMIT     LD        HL,(FILEBUF)
              LD        (AXSUBDST),HL
              LD        DE,120                         ; count + max 120 chars
              ADD       HL,DE
              LD        A,H
              CP        0DEH
              JP        NC,AXBAD                       ; stay below AUX BDOS
              LD        A,(AXSUBDST+1)
              OR        A
              JP        Z,AXBAD                        ; no page-zero target
              CALL      CCPSUB                         ; A=1 if command was consumed
              OR        A
              RET       Z
              LD        HL,(AXSUBDST)
              PUSH      HL
              LD        HL,FILEBUF+1                   ; count followed by command text
              POP       DE
              LD        BC,121
              CALL      AXM2A                          ; MAIN -> active AUX session
              LD        A,1
              LD        L,A
              RET
AXSUBDST      DEFW      0

; Shared loader diagnostics remain: AUXRUN, SAVE and BDOS use these.
RCOERR        LD        DE,NFMSG
              CALL      C_WRITESTR
              RET
RCLERR        LD        DE,REMSG
              CALL      C_WRITESTR
              RET
AUXSIZEERR    LD        DE,AUXBIGMSG
              CALL      C_WRITESTR
              RET
AUXBIGMSG     DEFM      'COM exceeds AUX TPA'
              DEFB      13,'$'
AUXBADMSG     DEFM      'AUX BDOS unsupported '
              DEFB      '$'
BDOSMSG       DEFM      'BDOS unsupported '
              DEFB      '$'

NFMSG         DEFM      'Not found'
              DEFB      13,'$'

REMSG         DEFM      'I/O error'
              DEFB      13,'$'

BFMSG         DEFM      'Bad format'
              DEFB      13,'$'

; Stage 27: removed unused code/data (Unused rename error message).
; Four names per line, with their drive letters. No sorting is done.
; Stage 25: resident DIR/ERA/REN/TYPE code removed.
; ProDOS parameter blocks and all BDOS disk I/O remain below.
FMMLI         DEFB      20H,00H,0BFH                   ; JSR $BF00 in 6502 code
              DEFB      0C0H                           ; ProDOS CREATE call
              DEFW      FMMLIPL+OFFSET                 ; Pointer to parm list in 6502 addr space
              DEFB      60H                            ; RTS in 6502 code
FMMLIPL       DEFB      7                              ; ProDOS PL: Seven parameters
FMMLIP        DEFW      PATHBUF+OFFSET                 ; ProDOS PL: Pointer to path in 6502 addr
FMMLIA        DEFB      0C3H                           ; ProDOS PL: Access (0C3H full access)
FMMLIT        DEFB      0                              ; ProDOS PL: File type (0 means typeless)
FMMLIAT       DEFW      0000H                          ; ProDOS PL: Aux file type (always 0000H)
FMMLIS        DEFB      1                              ; ProDOS PL: Storage type (1 for file)
FMMLICD       DEFW      0000H                          ; ProDOS PL: Create date (always 0000H)
FMMLICT       DEFW      0000H                          ; ProDOS PL: Create time (always 0000H)

; Parameter list for ProDOS DESTROY call
FDMLI         DEFB      20H,00H,0BFH                   ; JSR $BF00 in 6502 code
              DEFB      0C1H                           ; ProDOS DESTROY call
              DEFW      FDMLIPL+OFFSET                 ; Pointer to parm list in 6502 addr space
              DEFB      60H                            ; RTS in 6502 code
FDMLIPL       DEFB      1                              ; ProDOS PL: Seven parameters
FDMLIP        DEFW      PATHBUF+OFFSET                 ; ProDOS PL: Pointer to path in 6502 addr

; Parameter list for ProDOS RENAME call
FRNMLI        DEFB      20H,00H,0BFH                   ; JSR $BF00 in 6502 code
              DEFB      0C2H                           ; ProDOS RENAME call
              DEFW      FRNMLIPL+OFFSET                ; Pointer to parm list in 6502 addr space
              DEFB      60H                            ; RTS in 6502 code
FRNMLIPL      DEFB      2                              ; ProDOS PL: Two parameters
FRNMLIP1      DEFW      PATHBUF+OFFSET                 ; ProDOS PL: Pointer to path in 6502 addr
FRNMLIP2      DEFW      PATHBUF2+OFFSET                ; ProDOS PL: Pointer to path in 6502 addr

; Parameter list for ProDOS GET_FILE_INFO call
GFIMLI        DEFB      20H,00H,0BFH                   ; JSR $BF00 in 6502 code
              DEFB      0C4H                           ; ProDOS GET_FILE_INFO call
              DEFW      GFIMLIPL+OFFSET                ; Pointer to parm list in 6502 addr space
              DEFB      60H                            ; RTS in 6502 code
GFIMLIPL      DEFB      0AH                            ; ProDOS PL: Ten parameters
GFIMLIP       DEFW      PATHBUF+OFFSET                 ; ProDOS PL: Pointer to path in 6502 addr
GFIMLIAC      DEFB      0                              ; ProDOS PL: Access
GFIMLIT       DEFB      0                              ; ProDOS PL: File type
GFIMLIAT      DEFW      0000H                          ; ProDOS PL: Aux type
GFIMLIS       DEFB      1                              ; ProDOS PL: Storage type
GFIMLIBU      DEFW      0000H                          ; ProDOS PL: Blocks used
GFIMLIMD      DEFW      0000H                          ; ProDOS PL: Modification date
GFIMLIMT      DEFW      0000H                          ; ProDOS PL: Modification time
GFIMLICD      DEFW      0000H                          ; ProDOS PL: Create date
GFIMLICT      DEFW      0000H                          ; ProDOS PL: Create time

; ProDOS $C3 SET_FILE_INFO uses the same fields as GET_FILE_INFO
; through modification time. F_ATTRIB sets count=7 temporarily.
SFIMLI        DEFB      20H,00H,0BFH
              DEFB      0C3H
              DEFW      GFIMLIPL+OFFSET
              DEFB      60H

; Parameter list for ProDOS OPEN call
FOMLI         DEFB      20H,00H,0BFH                   ; JSR $BF00 in 6502 code
              DEFB      0C8H                           ; ProDOS OPEN call
              DEFW      FOMLIPL+OFFSET                 ; Pointer to parm list in 6502 addr space
              DEFB      60H                            ; RTS in 6502 code
FOMLIPL       DEFB      3                              ; ProDOS PL: Three parameters
FOMLIP        DEFW      PATHBUF+OFFSET                 ; ProDOS PL: pointer to path in 6502 addr
FOMLII        DEFW      0000H                          ; ProDOS PL: pointer to IO buffer
FOMLIN        DEFB      0                              ; ProDOS PL: File reference number

; Parameter list for ProDOS READ call
FRMLI         DEFB      20H,00H,0BFH                   ; JSR $BF00 in 6502 code
              DEFB      0CAH                           ; ProDOS READ call
              DEFW      FRMLIPL+OFFSET                 ; Pointer to parm list in 6502 addr space
              DEFB      60H                            ; RTS in 6502 code
FRMLIPL       DEFB      4                              ; ProDOS PL: Four parameters
FRMLIN        DEFB      0                              ; ProDOS PL: File reference number
FRMLIDB       DEFW      0000H                          ; ProDOS PL: Data buffer
FRMLIRC       DEFW      128                            ; ProDOS PL: Request count (bytes to read)
FRMLITC       DEFW      0000H                          ; ProDOS PL: Number of bytes transferred

; Parameter list for ProDOS WRITE call
FWMLI         DEFB      20H,00H,0BFH                   ; JSR $BF00 in 6502 code
              DEFB      0CBH                           ; ProDOS WRITE call
              DEFW      FWMLIPL+OFFSET                 ; Pointer to parm list in 6502 addr space
              DEFB      60H                            ; RTS in 6502 code
FWMLIPL       DEFB      4                              ; ProDOS PL: Four parameters
FWMLIN        DEFB      0                              ; ProDOS PL: File reference number
FWMLIDB       DEFW      0000H                          ; ProDOS PL: Data buffer
FWMLIRC       DEFW      128                            ; ProDOS PL: Request count (bytes to read)
FWMLITC       DEFW      0000H                          ; ProDOS PL: Number of bytes transferred

; Parameter list for ProDOS CLOSE call
FCMLI         DEFB      20H,00H,0BFH                   ; JSR $BF00 in 6502 code
              DEFB      0CCH                           ; ProDOS CLOSE call
              DEFW      FCMLIPL+OFFSET                 ; Pointer to parm list in 6502 addr space
              DEFB      60H                            ; RTS in 6502 code
FCMLIPL       DEFB      1                              ; ProDOS PB: One parameter
FCMLIN        DEFB      0                              ; ProDOS PB: File reference number

; Parameter list for ProDOS FLUSH call
FLMLI         DEFB      20H,00H,0BFH                   ; JSR $BF00 in 6502 code
              DEFB      0CDH                           ; ProDOS FLUSH call
              DEFW      FLMLIPL+OFFSET                 ; Pointer to parm list in 6502 addr space
              DEFB      60H                            ; RTS in 6502 code
FLMLIPL       DEFB      1                              ; ProDOS PL: One parameter
FLMLIN        DEFB      0                              ; ProDOS PL: File ref num (0 = all files)

; Parameter list for ProDOS SET_MARK call
SMMLI         DEFB      20H,00H,0BFH                   ; JSR $BF00 in 6502 code
              DEFB      0CEH                           ; ProDOS SET_MARK call
              DEFW      SMMLIPL+OFFSET                 ; Pointer to parm list in 6502 addr space
              DEFB      60H                            ; RTS in 6502 code
SMMLIPL       DEFB      2                              ; ProDOS PL: Two parameters
SMMLIN        DEFB      0                              ; ProDOS PL: File reference number
SMMLIP1       DEFB      0                              ; ProDOS PL: Position (LSB)
SMMLIP2       DEFB      0                              ; ProDOS PL: Position
SMMLIP3       DEFB      0                              ; ProDOS PL: Position (MSB)

; Parameter list for ProDOS SET_EOF call
SEMLI         DEFB      20H,00H,0BFH                   ; JSR $BF00 in 6502 code
              DEFB      0D0H                           ; ProDOS SET_EOF call
              DEFW      SEMLIPL+OFFSET                 ; Pointer to parm list in 6502 addr space
              DEFB      60H                            ; RTS in 6502 code
SEMLIPL       DEFB      2                              ; ProDOS PL: Two parameters
SEMLIN        DEFB      0                              ; ProDOS PL: File reference number
SEMLIE1       DEFB      0                              ; ProDOS PL: EOF position (LS-byte)
SEMLIE2       DEFB      0                              ; ProDOS PL: EOF position
SEMLIE3       DEFB      0                              ; ProDOS PL: EOF position (MS-byte)

; Parameter list for ProDOS GET_EOF call
GEMLI         DEFB      20H,00H,0BFH                   ; JSR $BF00 in 6502 code
              DEFB      0D1H                           ; ProDOS GET_EOF call
              DEFW      GEMLIPL+OFFSET                 ; Pointer to parm list in 6502 addr space
              DEFB      60H                            ; RTS in 6502 code
GEMLIPL       DEFB      2                              ; ProDOS PL: Two parameters
GEMLIN        DEFB      0                              ; ProDOS PL: File reference number
GEMLIE1       DEFB      0                              ; ProDOS PL: EOF position (LS-byte)
GEMLIE2       DEFB      0                              ; ProDOS PL: EOF position
GEMLIE3       DEFB      0                              ; ProDOS PL: EOF position (MS-byte)

; FCB used for opening ProDOS directory corresponding to drive
DFCB                        ; File control block for directory
DFCBDRV       DEFB      00H                            ; FCB Drive (0 current, 1 A:, 2 B: etc)
DFCBNAM       DEFM      '           '                  ; FCB filename and extension (all spaces)
DFCBEX        DEFB      00H                            ; FCB extent field
DFCBS1        DEFB      00H                            ; FCB S1 field
DFCBS2        DEFB      00H                            ; FCB S2 field
DFCBRC        DEFB      00H                            ; FCB RC field
DFCBMAP       DEFS      16                             ; Map of blocks in file
DFCBSR        DEFB      0                              ; FCB seq record number
DFCBRR        DEFB      0,0,0                          ; FCB rand record number

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; End of ProDOS Parameter Lists
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Drive parameter block (CP/M 2.2 format)
; See Johnson-Laird Pg 33-34
DPB           DEFW      32                             ; # 128 byte records per track (for Disk II)
              DEFB      4                              ; Block shift (2048 byte allocation blocks)
              DEFB      15                             ; Block mask (2048 byte allocation blocks)
              DEFB      0                              ; Extent mask (16K extents)
DPBDSM        DEFW      511                            ; 2K DSM set by V_GETFREE (up to 16382)
              DEFW      255                            ; # directory entries
              DEFB      0                              ; Directory allocation bitmap byte 1
              DEFB      0                              ; Directory allocation bitmap byte 2
              DEFW      0                              ; Checksum vector size
              DEFW      0                              ; # of reserved tracks

; 2048-byte CP/M allocation vector supports up to 16384 x 2 KiB
; allocation blocks, i.e. ProDOS's 32 MiB maximum. This is synthetic
; accounting; no claim is made that these are unique physical blocks.
;
; Reuse 6502 MAIN $0800-$0FFF (Apple II text page 2 and spare RAM),
; mapped to Z80 $F800-$FFFF. The 6502 direct console uses text page 1.
; This avoids sacrificing another 2 KiB of precious Z80 TPA or colliding
; with the live ProDOS I/O buffers at Z80 $9800-$A7FF.
;
; $0800-$09FF is the temporary ProDOS block buffer and GET_PREFIX buffer;
; ON_LINE uses $0880. Consequently V_GETFREE builds the allocation map
; ONLY after the final READ_BLOCK completes. A later V_GETFREE refreshes it.
ALLOCVEC      EQU       0F800H
VOLBUF        EQU       0F800H
VLEFT         DEFW      0                              ; Volume blocks remaining in scan
VFREE         DEFW      0                              ; Number of actual free 512-byte blocks
VTOTAL        DEFW      0                              ; ProDOS header total blocks (800K => $0640)
VNBLOCKS      DEFW      0                              ; 2K blocks (800K => 400, 32MB => 16383)
VFEND         DEFW      0                              ; Bitmap byte for highest CP/M block
VFMASK        DEFB      0                              ; Bit mask at VFEND
VBUDGET       DEFW      0                              ; Maximum bits available (excl 0..8)
VERR          DEFB      0                              ; Last ProDOS error, $FE if header invalid

; GET_PREFIX (ProDOS $C7). Returns Pascal absolute path in $0800.
VPMLI         DEFB      20H,00H,0BFH
              DEFB      0C7H
              DEFW      VPPL+OFFSET
              DEFB      60H
VPPL          DEFB      1
              DEFW      0800H

; ON_LINE (ProDOS $C5), unit=0 enumerates mounted devices.
; 256-byte list at $0880, well away from the 64-byte prefix at $0800.
VOMLI         DEFB      20H,00H,0BFH
              DEFB      0C5H
              DEFW      VOPL+OFFSET
              DEFB      60H
VOPL          DEFB      2
              DEFB      0                              ; 0 = enumerate all units
              DEFW      0880H

; GET_FILE_INFO (ProDOS $C4), only for the no-prefix fallback.
; The temporary absolute pathname lives at $0800.
VFMLI         DEFB      20H,00H,0BFH
              DEFB      0C4H
              DEFW      VFPL+OFFSET
              DEFB      60H
VFPL          DEFB      0AH
              DEFW      0800H
              DEFB      0                              ; Access returned
VFTYPE        DEFB      0                              ; File type returned ($0F = DIR)
              DEFS      13                             ; Remaining GET_FILE_INFO fields

V_HASPFX      DEFB      0
V_NAMELEN     DEFB      0
; The unit in VRUNIT belongs to the one ProDOS volume backing BP/M.
VUCVALID      DEFB      0

; ProDOS READ_BLOCK call, read-only, used to inspect volume bitmap.
VRMLI         DEFB      20H,00H,0BFH                   ; JSR $BF00
              DEFB      080H                           ; ProDOS READ_BLOCK
              DEFW      VRPL+OFFSET
              DEFB      60H                            ; RTS
VRPL          DEFB      3
VRUNIT        DEFB      0                              ; Discovered once; reused for all CP/M drives
              DEFW      0800H                          ; physical 6502 address (NOT VOLBUF+OFFSET)
VRBLK         DEFW      0                              ; Requested ProDOS 512-byte block

 ; ProDOS path buffers and directory workspace have been relocated to MAIN
 ; $4500.., in the reclaimed (former AUX LC snapshot) space.

; Two 1024 byte ProDOS I/O buffers, 1K spare, then the 1K Z80 stack
; The two I/O buffers start on page boundaries
; ProDOS occupies the space from $BF00 up (in 6502 addresses)
; 6502 code is loaded at $B800 for now
; RAM $A400-$A7FF is reserved for Z80 stack, not file I/O.


              ;ORG        9000H   ; Try this - WORKS

; Phase 4A.3: $FB socket commands in MAIN $9400-$97FF.
; Existing $9400-$94FF socket code precedes $9500 packet I/O.
; Do not place this in $A168-$A1E7: that is AUXSTAGE (128 bytes).
              ORG       09400H
; Phase 4A corrected: compact $FB to preserve the $A800 stack boundary.
; D=socket 0..3, E=0 STATUS, otherwise E=W5100 command byte.
; Command carried in E, never B (BDOS/scheduler may modify B).
; Only the owning logical tab can access a socket. No special VEDRIVE case.
; A=L=status for STATUS, 0 for accepted command, FF for error.
NETIO         LD        A,D
              CP        4
              JP        NC,NETBAD
              PUSH      DE
              CALL      NETPTR
              POP       DE
              LD        A,(TABMODE)
              CP        (HL)
              JP        NZ,NETBAD
              LD        A,E
              OR        A
              JR        Z,NI_STAT
              ; Nonzero E is the W5100 command byte.
              LD        (YREG),A
              LD        A,D
              ADD       A,4
              LD        (AREG),A
              LD        A,1
              LD        (XREG),A
              LD        HL,0B827H
              LD        (ADDR),HL
              LD        A,1
              LD        (CMD),A
              LD        (SOFTCARD),A
              LD        BC,8000
NI_POLL       LD        A,1                         ; read Sn_CR
              CALL      NI_READ
              OR        A
              JR        Z,NI_OK
              DEC       BC
              LD        A,B
              OR        C
              JR        NZ,NI_POLL
              JP        NETBAD
NI_OK         XOR       A
              JP        NETRET
NI_STAT       LD        A,3                         ; read Sn_SR
              CALL      NI_READ
              JP        NETRET
; A=low register address, D=physical socket, reads byte via 6502 bridge.
; Preserve BC for command acceptance timeout.
NI_READ       LD        (XREG),A
              LD        A,D
              ADD       A,4
              LD        (AREG),A
              LD        HL,0B824H
              LD        (ADDR),HL
              LD        A,1
              LD        (CMD),A
              LD        (SOFTCARD),A
              LD        A,(AREG)
              RET


; Phase 6F Telnet option replies. Place AFTER NETIO and NI_READ in
; the existing $9400-$94FF page (unused space before $9500).
; Do NOT ORG into $93xx: the resident BDOS image occupies that area.
; A=option, C=4 WILL/5 WONT/6 DO/7 DONT.
; NETCCP offers WILL ECHO, WILL SGA, DO SGA at connect time.
; Corresponding positive replies are acknowledgements, not new requests.
; Decline every other incoming positive option request (LINEMODE incl.).
; Never re-acknowledge accepted options: avoids RFC 854 negotiation loops.
TNNEG         LD        (TNBYTES+2),A
              CP        1                             ; ECHO
              JR        Z,TNECHO
              CP        3                             ; SUPPRESS-GO-AHEAD
              JR        Z,TNSGA
TNOTHER       LD        A,C
              CP        4                             ; unsolicited WILL
              JR        Z,TNDONT
              CP        6                             ; unsolicited DO
              JR        Z,TNWONT
              RET                                     ; WONT/DONT: no answer
TNECHO        LD        A,C
              CP        6                             ; DO ECHO acks our WILL
              RET       Z
              JR        TNOTHER                        ; WILL ECHO not supported
TNSGA         LD        A,C
              CP        6                             ; DO SGA acks our WILL
              RET       Z
              CP        4                             ; WILL SGA acks our DO
              RET       Z
              JR        TNOTHER
TNDONT        LD        A,0FEH                         ; IAC DONT option
              JR        TNRESP
TNWONT        LD        A,0FCH                         ; IAC WONT option
TNRESP        LD        (TNBYTES+1),A
              LD        HL,TNBYTES
              LD        DE,NXBUF
              LD        BC,3
              LDIR                                    ; MAIN -> MAIN staging
              LD        A,3
              LD        (NXREQ),A
              LD        A,1
              LD        (UCFLAG),A                     ; already MAIN, no AUX copy
              LD        B,32                           ; bounded TX retries on disconnect
TNRETRY       PUSH      BC
              CALL      NXTX                          ; same W5100 path as UCOUT
              POP       BC
              OR        A
              JR        NZ,TNLEAVE
              DJNZ      TNRETRY
TNLEAVE       XOR       A
              LD        (UCFLAG),A
              RET
TNBYTES       DEFB      0FFH,0FCH,0

; Phase 4B: BDOS $FC - packetless W5100 TX/RX, max 16 bytes per call.
; DE -> AUX [socket, operation (0=TX,1=RX), requested length, ptr lo,ptr hi].
; Return A=L actual count (0=would block), FF=bad arguments / hardware failure.
; Unowned sockets are never touched. Single call executes on MAIN stack.
; In particular, do not call scheduling/BDOS routines while accessing
; hardware or copying between MAIN and AUX transient banks.
              ORG       09500H
NXIO          EX        DE,HL
              LD        DE,NXPAR
              LD        BC,5
              CALL      LCA2M                       ; AUX parameters -> MAIN
              LD        A,(NXPAR)
              CP        4
              JP        NC,NETBAD
              LD        (NXSOCK),A
              CALL      NETPTR
              LD        A,(TABMODE)
              CP        (HL)
              JP        NZ,NETBAD
              LD        A,(NXPAR+2)
              OR        A
              JP        Z,NXZERO
              CP        17                          ; 16-byte staging limit
              JP        NC,NETBAD
              LD        (NXREQ),A
              LD        A,(NXPAR+1)
              OR        A
              JP        Z,NXTX
              CP        1
              JP        Z,NXRX
              JP        NETBAD
NXZERO        XOR       A
              JP        NETRET

; Universal W5100 read/write: HL is full W5100 address.
; NXRD returns A, NXWR accepts A; both preserve HL.
NXRD          PUSH      HL
              LD        A,H
              LD        (AREG),A
              LD        A,L
              LD        (XREG),A
              LD        HL,0B824H
              LD        (ADDR),HL
              LD        A,1
              LD        (CMD),A
              LD        (SOFTCARD),A
              LD        A,(AREG)
              POP       HL
              RET
NXWR          PUSH      HL
              LD        (YREG),A
              LD        A,H
              LD        (AREG),A
              LD        A,L
              LD        (XREG),A
              LD        HL,0B827H
              LD        (ADDR),HL
              LD        A,1
              LD        (CMD),A
              LD        (SOFTCARD),A
              POP       HL
              RET
; A=socket register offset, returns HL=full W5100 socket address.
NXREG         LD        L,A
              LD        A,(NXSOCK)
              ADD       A,4
              LD        H,A
              RET
; Socket's TX/RX allocation from live W5100 TMSR/RMSR.
; A=allocation register, C=first buffer page (40h or 60h).
; Returns base high byte NXBASE, ring high-byte mask NXMASK.
NXRING        LD        B,A
              LD        A,C
              LD        (NXBASE),A
              LD        A,(NXSOCK)
              LD        C,A
NXRG1         LD        A,B
              AND       3
              LD        E,A
              LD        D,0
              LD        HL,NXSIZE
              ADD       HL,DE
              LD        E,(HL)                       ; buffer length in 256-byte pages
              LD        A,C
              OR        A
              JR        Z,NXRG2
              LD        A,(NXBASE)
              ADD       A,E
              LD        (NXBASE),A
              LD        A,B
              RRCA
              RRCA
              LD        B,A
              DEC       C
              JR        NXRG1
NXRG2         LD        A,(NXBASE)
              AND       01FH                         ; 40h and 60h begin on 8KB boundaries
              ADD       A,E
              CP        33                           ; must fit in 8KB hardware buffer
              JR        NC,NXRGERR
              LD        A,E
              DEC       A
              LD        (NXMASK),A
              OR        A
              RET
NXRGERR       SCF
              RET
NXSIZE        DEFB      4,8,16,32
; NXRPTR is the high byte's socket-register low address (24h/28h).
NXRDPTR       LD        A,(NXRPTR)
              CALL      NXREG
              CALL      NXRD
              LD        (NXHI),A
              INC       HL
              CALL      NXRD
              LD        (NXLO),A
              RET
NXWRPTR       LD        A,(NXRPTR)
              CALL      NXREG
              LD        A,(NXHI)
              CALL      NXWR
              INC       HL
              LD        A,(NXLO)
              CALL      NXWR
              RET
; Compute selected TX/RX ring address for the current pointer.
NXADDR        LD        A,(NXHI)
              LD        B,A
              LD        A,(NXMASK)
              AND       B
              LD        B,A
              LD        A,(NXBASE)
              ADD       A,B
              LD        H,A
              LD        A,(NXLO)
              LD        L,A
              RET
NXINC         LD        A,(NXLO)
              INC       A
              LD        (NXLO),A
              RET       NZ
              LD        A,(NXHI)
              INC       A
              LD        (NXHI),A
              RET
; A=command, call existing ownership-checked FB backend; return A=0/FF.
NXCMD         LD        E,A
              LD        A,(NXSOCK)
              LD        D,A
              CALL      NETIO
              RET
; Fill ring from 16-byte MAIN staging. FSR < length -> zero, no writes.
NXTX          LD        A,(UCFLAG)
              OR        A
              JR        NZ,NXTXBUF                      ; NET UC1 staged byte already in MAIN
              LD        HL,(NXPAR+3)
              LD        DE,NXBUF
              LD        A,(NXREQ)
              LD        C,A
              LD        B,0
              CALL      LCA2M
NXTXBUF       LD        HL,001BH                     ; TMSR
              CALL      NXRD
              LD        C,040H
              CALL      NXRING
              JP        C,NETBAD
              LD        A,020H                       ; Sn_TX_FSR high
              CALL      NXREG
              CALL      NXRD
              OR        A
              JR        NZ,NXTXOK
              INC       HL
              CALL      NXRD
              LD        B,A
              LD        A,(NXREQ)
              CP        B
              JP        NC,NXTXCHK
              JR        NXTXOK
NXTXCHK       JR        Z,NXTXOK
              JP        NXZERO                      ; transient buffer full
NXTXOK        LD        A,024H
              LD        (NXRPTR),A
              CALL      NXRDPTR
              XOR       A
              LD        (NXIDX),A
NXTXLP        LD        A,(NXIDX)
              LD        E,A
              LD        D,0
              LD        HL,NXBUF
              ADD       HL,DE
              LD        A,(HL)
              PUSH      AF
              CALL      NXADDR
              POP       AF
              CALL      NXWR
              CALL      NXINC
              LD        A,(NXIDX)
              INC       A
              LD        (NXIDX),A
              LD        B,A
              LD        A,(NXREQ)
              CP        B
              JR        NZ,NXTXLP
              CALL      NXWRPTR
              LD        A,020H                       ; SEND
              CALL      NXCMD
              CP        0FFH
              JP        Z,NETBAD
              LD        A,(NXREQ)
              JP        NETRET
; Nonblocking RX: return min(available, requested) into AUX buffer.
NXRX          LD        HL,001AH                     ; RMSR
              CALL      NXRD
              LD        C,060H
              CALL      NXRING
              JP        C,NETBAD
              LD        A,026H                       ; Sn_RX_RSR high
              CALL      NXREG
              CALL      NXRD
              OR        A
              JR        NZ,NXRXOK
              INC       HL
              CALL      NXRD
              OR        A
              JP        Z,NXZERO
              LD        B,A
              LD        A,(NXREQ)
              CP        B
              JR        C,NXRXOK
              JR        Z,NXRXOK
              LD        A,B
              LD        (NXREQ),A
NXRXOK        LD        A,028H
              LD        (NXRPTR),A
              CALL      NXRDPTR
              XOR       A
              LD        (NXIDX),A
NXRXLP        CALL      NXADDR
              CALL      NXRD
              PUSH      AF
              LD        A,(NXIDX)
              LD        E,A
              LD        D,0
              LD        HL,NXBUF
              ADD       HL,DE
              POP       AF
              LD        (HL),A
              CALL      NXINC
              LD        A,(NXIDX)
              INC       A
              LD        (NXIDX),A
              LD        B,A
              LD        A,(NXREQ)
              CP        B
              JR        NZ,NXRXLP
              CALL      NXWRPTR
              LD        A,040H                       ; RECV: acknowledge consumed data
              CALL      NXCMD
              CP        0FFH
              JP        Z,NETBAD
              LD        A,(UCFLAG)
              OR        A
              JR        NZ,NXRXMAIN                      ; UC1 gets byte from MAIN staging
              LD        HL,NXBUF
              LD        DE,(NXPAR+3)
              LD        A,(NXREQ)
              LD        C,A
              LD        B,0
              CALL      AXM2A                        ; MAIN -> calling AUX bank
NXRXMAIN      LD        A,(NXREQ)
              JP        NETRET
; Sole staging area; never retain caller AUX pointers across a task switch.
NXPAR         DEFS      5
NXSOCK        DEFB      0
NXREQ         DEFB      0
NXRPTR        DEFB      0
NXBASE        DEFB      0
NXMASK        DEFB      0
NXHI          DEFB      0
NXLO          DEFB      0
NXIDX         DEFB      0
NXBUF         DEFS      16
NXEND

; Phase 6F: per-tab TELNET receiver and negotiation replies in MAIN $9740..$97FF.
; Called ONLY by UCSTAT, after NXRX has finished. B/DE/HL may be
; clobbered: UCSTAT already saves these; A and carry are the interface.
; Carry set: A is one application input byte. Carry clear: consumed
; a TELNET control/subnegotiation byte, so UCSTAT checks TCP again.
; States: 0=data, 1=IAC, 2=SB, 3=SB-IAC, 4=WILL option,
; 5=WONT option, 6=DO option, 7=DONT option, 8=after CR.
; Keep all negotiation in MAIN after NXRX: do not call AUX BDOS here.
              ORG       09740H
TNTPTR        LD        A,(TABMODE)
              LD        E,A
              LD        D,0
              LD        HL,TNSTATE
              ADD       HL,DE
              RET
TNFEED        LD        B,A
              CALL      TNTPTR
              LD        A,(HL)
              OR        A
              JR        Z,TNDATA
              CP        1
              JR        Z,TNIAC
              CP        2
              JR        Z,TNSB
              CP        3
              JR        Z,TNSBI
              CP        8
              JR        Z,TNCR
              LD        C,A                           ; 4..7 identifies TELNET verb
              LD        (HL),0                         ; ready for next input byte
              LD        A,B                           ; TELNET option number
              CALL      TNNEG                          ; send reply if required
              JR        TNDROP
TNDATA        LD        A,B
              CP        0FFH
              JR        Z,TNISET
              CP        13
              JR        Z,TNCRST
TNBYTE        SCF
              RET
TNISET        LD        (HL),1
TNDROP        OR        A                             ; clear carry: protocol consumed
              RET
TNCRST        LD        (HL),8
              JR        TNBYTE                         ; deliver CR exactly once
TNCR          LD        (HL),0
              LD        A,B
              OR        A
              RET       Z                             ; CR NUL -> one CR
              CP        10
              RET       Z                             ; CR LF -> one CR
              JR        TNDATA                         ; unrelated byte is real data
TNIAC         LD        (HL),0
              LD        A,B
              CP        0FFH
              JR        Z,TNBYTE                       ; doubled IAC -> literal FF
              CP        0FAH
              JR        Z,TNSBS                        ; SB
              CP        0FBH
              JR        Z,TNOPT                        ; WILL
              CP        0FCH
              JR        Z,TNOPT                        ; WONT
              CP        0FDH
              JR        Z,TNOPT                        ; DO
              CP        0FEH
              JR        Z,TNOPT                        ; DONT
              CP        0F4H
              JR        Z,TNINT                        ; IP -> ^C
              CP        0F3H
              JR        Z,TNINT                        ; BRK -> ^C
              CP        0F7H
              JR        Z,TNEC                         ; EC -> backspace
              CP        0F8H
              JR        Z,TNEL                         ; EL -> ^U
              JR        TNDROP
TNINT         LD        A,3
              JR        TNBYTE
TNEC          LD        A,8
              JR        TNBYTE
TNEL          LD        A,15H
              JR        TNBYTE
TNSBS         LD        (HL),2
              JR        TNDROP
TNOPT         LD        A,B                           ; FB/FC/FD/FE
              SUB       0F7H                          ; map to state 4/5/6/7
              LD        (HL),A
              JR        TNDROP
TNSB          LD        A,B
              CP        0FFH
              JR        NZ,TNDROP
              LD        (HL),3
              JR        TNDROP
TNSBI         LD        A,B
              CP        0F0H                           ; IAC SE terminates SB
              JR        Z,TNSEND
              LD        (HL),2                         ; continue swallowing SB
              JR        TNDROP
TNSEND        LD        (HL),0
              JR        TNDROP
TNSTATE       DEFB      0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

              ORG       9800H                          ; Try this - WORKS
IOBUF1        DEFS      1024
IOBUF2        DEFS      1024
; Put the read completion shim in the otherwise spare $A000-$A3FF area.
; It cannot overlap ProDOS buffers or the dedicated $A400-$A7FF stack.
; Keeping it here actually saves 6 bytes in the crowded resident area.
IOFREE
; Both F_READ and F_READRAND use this helper after SET_MARK succeeds.
; ProDOS READ sets FRMLITC even if EOF is reached before 128 bytes.
; $4C is EOF only when the transfer count is zero; a short read returns
; success and must be padded in the CP/M DMA buffer, not on disk.
; Return ProDOS status unchanged for errors other than $4C;
; otherwise return 0 if 1..128 bytes were read and $4C if none.
READ128       XOR       A
              LD        (FRMLITC),A                    ; No stale transfer count on error
              LD        (FRMLITC+1),A
              LD        HL,FRMLI
              CALL      PRODOS
              OR        A
              JR        Z,R128_COUNT
              CP        04CH
              RET       NZ                             ; Preserve bad FRN / other error
R128_COUNT    LD        A,(FRMLITC+1)
              OR        A                              ; 128 requested: high byte must be 0
              JR        NZ,R128_BAD
              LD        A,(FRMLITC)
              OR        A
              JR        Z,R128_EOF
              CP        128
              JR        Z,R128_OK
              JR        NC,R128_BAD                    ; ProDOS cannot return >128 bytes
              LD        C,A                            ; Bytes read (1..127)
              LD        B,0
              LD        HL,(DMAADDR)
              ADD       HL,BC                          ; First unfilled byte
              LD        A,128
              SUB       C
              LD        B,A                            ; Number of bytes to pad (1..127)
              LD        A,01AH                         ; CP/M text EOF marker (^Z)
R128_FILL     LD        (HL),A
              INC       HL
              DJNZ      R128_FILL
R128_OK       XOR       A
              RET
R128_EOF      LD        A,04CH
              RET
R128_BAD      LD        A,0FFH
              RET

; ProDOS's F_SFIRST/F_SNEXT leave the directory open between matches.
; Once exhausted, release its physical ProDOS handle and associated 1K
; OPEN buffer. The caller's DMA address and wildcard FCB are unchanged.
; On an already-closed/failed OPEN, F_CLOSE is harmless (DFCB S2=0).
; Keep this helper in the spare region rather than crowding $9800.
SEARCH_EOF    LD        DE,DFCB
              CALL      F_CLOSE
              LD        A,0FFH                         ; CP/M search: no more entries
              LD        L,A                            ; Also return error in L
              RET


; =====================================================================
; AUX56 PHASE 1: restricted ordinary .COM loader / LC bank gateway.
; This is deliberately isolated from the working main-bank filesystem.
; Full aux FCB/DMA pointer translation is NOT implemented.
; Code and scratch storage reside in the spare $A000-$A3FF main bank.
; =====================================================================

; Size-to-allocation-map synthesis, relocated from resident BDOS.
; All internal JR/DJNZ targets remain within this block.
N2FMAP        ADD       A,15                           ; Round record count up to 16
              RRCA
              RRCA
              RRCA
              RRCA
              AND       0FH                            ; (records+15)/16 (0..8)
              LD        C,A
              LD        HL,(DMAADDR)
              LD        DE,16
              ADD       HL,DE                          ; Offset 16: start of allocation map
              LD        B,8                            ; Eight 16-bit block entries
              LD        D,1                            ; Fake block number, nonzero
N2FMLP        LD        A,C
              OR        A
              JR        Z,N2FMZERO
              LD        A,D                            ; Populated allocation entry
              DEC       C
              JR        N2FMSTORE
N2FMZERO      XOR       A                              ; Unused block entry
N2FMSTORE     LD        (HL),A                         ; Little endian, low byte
              INC       HL
              XOR       A
              LD        (HL),A                         ; High byte of block number
              INC       HL
              INC       D
              DJNZ      N2FMLP
              RET

              ORG       0A080H
; Auxiliary page zero: WBOOT -> LC DF03, BDOS -> LC DE00.
AUXPZERO      DEFB      0C3H,003H,0DFH,0,0,0C3H,000H,0DEH
AUXDEST       DEFW      0100H
AUXEXCD       DEFB      0

; AUX LC BIOS jump table at DF00. BDOS JP lives at DE00.
; Three-byte BDOS stub copied to AUX LC $DE00 before the BIOS image.
LCBDJP        JP        LCGATE
LCIMG
              JP        LCNOP
              JP        LCWBOOT
              JP        LCBCST
              JP        LCBCIN
              JP        LCBCOUT
              JP        LCBLST
              JP        LCBPUN
              JP        LCBRDR
              JP        LCNOP
              JP        LCBNULL
              JP        LCNOP
              JP        LCNOP
              JP        LCNOP
              JP        LCBERR
              JP        LCBERR
              JP        LCBZERO
              JP        LCBTRAN
              JP        LCGATE
LIENT         XOR       A
              LD        SP,LCBASE
              LD        (WRAUX),A
              LD        (RDAUX),A
              CALL      0100H
              JP        LCFIN
LIGATE        XOR       A
              LD        (WRMAIN),A
              LD        (RDMAIN),A
              JP        AXGATE
LIFIN         XOR       A
              LD        (WRMAIN),A
              LD        (RDMAIN),A
              JP        AXFIN
LIRES         LD        (WRAUX),A
              LD        (RDAUX),A
              RET
LIPEEK        XOR       A
              LD        (RDAUX),A
              LD        A,(HL)
              LD        (RDMAIN),A
              RET
LIA2M         XOR       A
              LD        (RDAUX),A
              LDIR
              LD        (RDMAIN),A
              RET
LINOP         RET
LIBCST        PUSH      BC
              PUSH      DE
              PUSH      HL
              LD        C,0F1H
              CALL      LCGATE
              POP       HL
              POP       DE
              POP       BC
              RET
LIBCIN        PUSH      BC
              PUSH      DE
              PUSH      HL
              LD        C,0F2H
              CALL      LCGATE
              POP       HL
              POP       DE
              POP       BC
              RET
LIBCOUT       PUSH      BC
              PUSH      DE
              PUSH      HL
              LD        E,C
              LD        C,0F3H
              CALL      LCGATE
              POP       HL
              POP       DE
              POP       BC
              RET
; AUX LC must preserve caller registers while switching via LCGATE.
LIBLST        PUSH      BC
              PUSH      DE
              PUSH      HL
              LD        E,C
              LD        C,0F4H
              CALL      LCGATE
              POP       HL
              POP       DE
              POP       BC
              RET
LIBPUN        PUSH      BC
              PUSH      DE
              PUSH      HL
              LD        E,C
              LD        C,0F5H
              CALL      LCGATE
              POP       HL
              POP       DE
              POP       BC
              RET
LIBRDR        PUSH      BC
              PUSH      DE
              PUSH      HL
              LD        C,0F6H
              CALL      LCGATE
              POP       HL
              POP       DE
              POP       BC
              RET
LIBNULL       LD        HL,0
              RET
LIBERR        LD        A,1
              RET
LIBZERO       XOR       A
              RET
LIBTRAN       LD        H,B
              LD        L,C
              RET
; Explicit AUX RST 0 / JP 0000H is WBOOT, not ordinary .COM RET.
; Select MAIN RAM before updating the MAIN-owned AXQUIT flag.
LIWBOOT       XOR       A
              LD        (WRMAIN),A
              LD        (RDMAIN),A
              INC       A
              LD        (AXQUIT),A
              JP        AXFIN
LIEND

; LC runtime addresses; only eight-character distinct symbol prefixes.
LCREN         EQU       LCBASE+(LIENT-LCIMG)
LCGATE        EQU       LCBASE+(LIGATE-LCIMG)
LCFIN         EQU       LCBASE+(LIFIN-LCIMG)
LCWBOOT       EQU       LCBASE+(LIWBOOT-LCIMG)
LCRES         EQU       LCBASE+(LIRES-LCIMG)
LCPEE0        EQU       LCBASE+(LIPEEK-LCIMG)
LCA2MR        EQU       LCBASE+(LIA2M-LCIMG)
LCNOP         EQU       LCBASE+(LINOP-LCIMG)
LCBCST        EQU       LCBASE+(LIBCST-LCIMG)
LCBCIN        EQU       LCBASE+(LIBCIN-LCIMG)
LCBCOUT       EQU       LCBASE+(LIBCOUT-LCIMG)
LCBLST        EQU       LCBASE+(LIBLST-LCIMG)
LCBPUN        EQU       LCBASE+(LIBPUN-LCIMG)
LCBRDR        EQU       LCBASE+(LIBRDR-LCIMG)
LCBNULL       EQU       LCBASE+(LIBNULL-LCIMG)
LCBERR        EQU       LCBASE+(LIBERR-LCIMG)
LCBZERO       EQU       LCBASE+(LIBZERO-LCIMG)
LCBTRAN       EQU       LCBASE+(LIBTRAN-LCIMG)
LCQUIT        EQU       AXQUIT
LCLEN         EQU       LIEND-LCIMG

; MAIN staging buffer for 128-byte ProDOS record reads.
AUXSTAGE      DEFS      128

 ; DCHKRO/RODENY relocated to MAIN $4800 with the I/O driver.




; =====================================================================
; Two-slot ProDOS handle cache. The existing $9800/$9C00 1K buffers
; remain the only OPEN buffers. The directory search and CCP loader
; use uncached, pinned FRNs: cache eviction only considers CSTAT1/2=1.
; All lookup keys are pathname length plus <=19 bytes (user/drive/name).
; CMRU=1/2 is last used slot; eviction prefers the other one.
; This code occupies the otherwise unused MAIN $A200-$A3FF region.
; =====================================================================
              ORG       0A200H
; Look up PATHBUF in cached slots. A=1/2 for a hit, A=0 for miss.
CACHEFND      LD        A,(CSTAT1)
              OR        A
              JR        Z,CF_TWO
              LD        DE,CNAME1
              CALL      CACHECMP
              JR        Z,CF_ONE
CF_TWO        LD        A,(CSTAT2)
              OR        A
              JR        Z,CF_MISS
              LD        DE,CNAME2
              CALL      CACHECMP
              JR        Z,CF_TWON
CF_MISS       XOR       A
              RET
CF_ONE        LD        A,1
              RET
CF_TWON       LD        A,2
              RET
; Compare Pascal-style paths, including length; ignore stale trailing data.
CACHECMP      LD        HL,PATHBUF
              LD        A,(HL)
              INC       A
              LD        B,A
CC_LOOP       LD        A,(DE)
              CP        (HL)
              RET       NZ
              INC       HL
              INC       DE
              DJNZ      CC_LOOP
              XOR       A
              RET

; A=1 or 2, return cached physical ProDOS reference (no register clobber).
CACHEREF      CP        1
              JR        Z,CR_ONE
              LD        A,(FRN2)
              RET
CR_ONE        LD        A,(FRN1)
              RET

; A=slot; register a successful _F_OPEN's pathname as cached.
CACHEPUT      LD        (CSLOT),A
              PUSH      AF
              LD        HL,COPENS
              CALL      CINC16
              POP       AF
              LD        HL,PATHBUF
              LD        DE,CNAME1
              CP        1
              JR        Z,CP_COPY
              LD        DE,CNAME2
CP_COPY       LD        BC,20
              LDIR
              LD        A,(CSLOT)
              LD        (CMRU),A
              CP        1
              JR        NZ,CP_TWO
              LD        (CSTAT1),A
              RET
CP_TWO        LD        A,1
              LD        (CSTAT2),A
              RET

; A=1/2; physically close slot, clear its FRN and cache flag on success.
CACHESLT      LD        (CSLOT),A
              CALL      CACHEREF
              LD        (FCMLIN),A
              LD        HL,FCMLI
              CALL      PRODOS
              OR        A
              RET       NZ
              LD        A,(CSLOT)
              CP        1
              JR        NZ,CS_TWO
              XOR       A
              LD        (FRN1),A
              LD        (CSTAT1),A
              RET
CS_TWO        XOR       A
              LD        (FRN2),A
              LD        (CSTAT2),A
              RET

; Close only a cached handle matching PATHBUF; leave raw directory FRNs.
CACHECLS      CALL      CACHEFND
              OR        A
              RET       Z
              JP        CACHESLT

; When both buffers are occupied, evict only cached files (never DFCB).
CACHEEV       LD        A,(CSTAT1)
              OR        A
              JR        Z,CE_SECOND
              LD        A,(CSTAT2)
              OR        A
              JR        Z,CE_FIRST
              LD        A,(CMRU)
              CP        1
              JR        Z,CE_SECOND
CE_FIRST      LD        A,1
              JP        CACHESLT
CE_SECOND     LD        A,(CSTAT2)
              OR        A
              JR        Z,CE_FAIL
              LD        A,2
              JP        CACHESLT
CE_FAIL       LD        A,0FFH
              RET

; Return an available IOBUF (A=slot, HL=buffer), evicting LRU if needed.
CACHEFREE     XOR       A
              CALL      GETIOADDR
              CP        0FFH
              RET       NZ
              CALL      CACHEEV
              OR        A
              JR        NZ,CE_FAIL
              LD        HL,CEVICTS
              CALL      CINC16
              XOR       A
              JP        GETIOADDR

; Warm boot / AUX termination: flush all ProDOS refs, clear slot metadata.
CACHEALL      XOR       A
              LD        (FCMLIN),A
              LD        HL,FCMLI
              CALL      PRODOS
              XOR       A
              LD        (FRN1),A
              LD        (FRN2),A
              LD        (FRN3),A
              LD        (FRN4),A
              LD        (DFCB+0EH),A                   ; No stale physical directory reference
              LD        (CSTAT1),A
              LD        (CSTAT2),A
              LD        (CMRU),A
              RET

CSTAT1        DEFB      0
CSTAT2        DEFB      0
CMRU          DEFB      0
CSLOT         DEFB      0
CNAME1        DEFS      20
CNAME2        DEFS      20

              ORG       0A340H
; B=logical tab; called on KILL and remote CCP shell termination.
NETKILL       PUSH      BC
              LD        E,B
              LD        D,0
              LD        HL,UCPERS
              ADD       HL,DE
              LD        (HL),0
              POP       BC
              JP        NETCLN
; Preserve binding only for the single registered remote socket.
; NETCLN's usual cleanup still closes every other child-owned socket.
NCKMATCH      CP        B
              RET       NZ
              PUSH      BC
              PUSH      DE
              PUSH      HL
              LD        E,B
              LD        D,0
              LD        HL,UCPERS
              ADD       HL,DE
              LD        A,(HL)
              OR        A
              JR        Z,NCKCLS
              LD        HL,UCBIND
              ADD       HL,DE
              LD        A,(HL)
              CP        C
              JR        NZ,NCKCLS
              LD        A,1                            ; NZ: keep this persistent socket
              JR        NCKRET
NCKCLS        XOR       A                              ; Z: ordinary cleanup
NCKRET        POP       HL
              POP       DE
              POP       BC
              OR        A
              RET
NCKCLN        PUSH      BC
              LD        E,B
              LD        D,0
              LD        HL,UCPERS
              ADD       HL,DE
              LD        A,(HL)
              OR        A
              POP       BC
              RET       NZ                             ; keep UC1 binding when armed
              JP        NCXCLN

; The AUX exit path originally printed a CR even on a forced disconnect.
; That could spin forever in UCOUT while the socket was closed.
NCEXCR        LD        A,(AUXEXCD)
              CP        5
              RET       Z
              LD        E,13
              CALL      C_WRITE
              LD        A,(IOBYTE)
              AND       3
              CP        3
              RET       NZ                             ; CRT retains its existing CR behaviour
              LD        E,10
              JP        C_WRITE                        ; kernel's own final CR needs LF on UC1

; AXQUIT=5 means the AUX application has FULLY unwound. Never
; redirect the live application to CRT on a socket hangup.
; Phase 6G: close the old socket and relaunch the listener in this tab.
NCABORT       JP        NC_REARM

              ORG       0A3D0H
; Executable base name (8 bytes) is in PATHBUF2+1 after PARSE.
TBEXE         LD        A,(TABMODE)
              CALL      TBNPTR
              EX        DE,HL
              LD        HL,PATHBUF2+1
              LD        BC,8
              LDIR
              RET
; Return HL -> first byte of tab B's 10-byte virtual video metadata.
TB_METAP      LD        HL,VSMETAS
              LD        DE,10
              LD        A,B
              OR        A
              RET       Z
TM_NEXT       ADD       HL,DE
              DEC       A
              JR        NZ,TM_NEXT
              RET

              ORG       0A400H
; Experimental base-69 codec lives at the bottom of the resident stack
; reservation. Z80 SP still starts at $A800. Check available stack!
; Zapple-II base-69/base-36 arithmetic prototype for Udo Munk Z80asm.
; ------------------------------------------------------------------
; This module is NOT installed into the resident BDOS. It is a standalone
; callable implementation to be placed in available Z80 RAM.
;
; B69ENC: HL = 11 FCB name/extension bytes (no drive byte).
;         DE = 15-byte output buffer.
;         Output is always 15 ASCII bytes: Z.<13 base36 chars>.
;         A = 0 success, FF invalid character.
;         Ignores the FCB attribute bits (high bit).
;
; B69DEC: HL = 15 ASCII bytes (already verified ProDOS name length = 15).
;         DE = 11-byte output FCB name/extension field.
;         A = 0 success, FF invalid prefix/base36 or number >=69^11.
;         Caller MUST also validate CP/M name format and reserve Z.<13>.
;
; Both entries clobber AF BC DE HL IX; preserve IY; use shared scratch.
; They are NOT reentrant. Name conversion is serialized inside BDOS.
;
; To include in source, place the routines/data in RAM without crossing an
; ORG boundary or the two ProDOS 1K buffers. Label names are <= 8 chars.
;
; Use without inserting a separate ORG here. Start with B69ENC label.

B69ENC        LD        (B69INT),HL
              LD        (B69OUT),DE
              CALL      B69CLR
              LD        HL,(B69INT)
              LD        B,11
E69LOOP       LD        A,(HL)
              AND       07FH                           ; ignore CP/M attribute flag
              CP        020H
              JP        C,B69ERR
              CP        07FH
              JP        NC,B69ERR
              CP        061H                           ; skip lowercase ASCII a-z
              JR        C,E69MAP
              CP        07BH
              JP        C,B69ERR
              SUB       26
E69MAP        SUB       020H                           ; 0..68 base69 digit
              PUSH      BC
              PUSH      HL
              CALL      B69M69
              POP       HL
              POP       BC
              INC       HL
              DJNZ      E69LOOP
              LD        HL,(B69OUT)
              LD        (HL),'Z'
              INC       HL
              LD        (HL),'.'
              INC       HL
              LD        (B69OUT),HL                    ; 13-byte payload beginning
              LD        DE,12
              ADD       HL,DE                          ; write digits from right to left
              LD        B,13
E69OUT        PUSH      BC
              PUSH      HL
              LD        A,36
              CALL      B69DIV                         ; A=number modulo 36; big /= 36
              POP       HL
              POP       BC
              CP        10
              JR        C,E69NUM
              ADD       A,'A'-10
              JR        E69PUT
E69NUM        ADD       A,'0'
E69PUT        LD        (HL),A
              DEC       HL
              DJNZ      E69OUT
              XOR       A
              RET

B69DEC        LD        (B69INT),HL
              LD        (B69OUT),DE
              LD        A,(HL)
              CP        'Z'
              JP        NZ,B69ERR
              INC       HL
              LD        A,(HL)
              CP        '.'
              JP        NZ,B69ERR
              INC       HL
              LD        (B69INT),HL                    ; first payload character
              CALL      B69CLR
              LD        HL,(B69INT)
              LD        B,13
D69LOOP       LD        A,(HL)
              CP        '0'
              JP        C,B69ERR
              CP        03AH
              JR        C,D69NUM
              CP        'A'
              JP        C,B69ERR
              CP        05BH
              JP        NC,B69ERR
              SUB       'A'-10
              JR        D69ADD
D69NUM        SUB       '0'
D69ADD        PUSH      BC
              PUSH      HL
              CALL      B69M36
              POP       HL
              POP       BC
              INC       HL
              DJNZ      D69LOOP
              LD        HL,(B69OUT)
              LD        DE,10
              ADD       HL,DE
              LD        B,11
D69OUT        PUSH      BC
              PUSH      HL
              LD        A,69
              CALL      B69DIV                         ; A=number modulo 69; big /=69
              POP       HL
              POP       BC
              CP        65                             ; first 65 chars map to ASCII 32..96
              JR        C,D69LOW
              ADD       A,26                           ; last 4 chars map to {|}~
D69LOW        ADD       A,020H
              LD        (HL),A
              DEC       HL
              DJNZ      D69OUT
              ; Reject input >= 69^11 by ensuring quotient becomes zero.
              LD        HL,B69BIG
              LD        B,9
D69CHK        LD        A,(HL)
              OR        A
              JP        NZ,B69ERR
              INC       HL
              DJNZ      D69CHK
              XOR       A
              RET

B69ERR        LD        A,0FFH
              RET

; Clear 9-byte big-endian intermediate integer.
B69CLR        LD        HL,B69BIG
              LD        B,9
              XOR       A
C69LOOP       LD        (HL),A
              INC       HL
              DJNZ      C69LOOP
              RET

; BIGNUM = BIGNUM*69 + A (0..68).
; Carry flows from least-significant (highest-address) byte upwards.
B69M69        LD        C,A
              LD        HL,B69BIG+8
              LD        B,9
M69LOOP       PUSH      HL
              LD        L,(HL)
              LD        H,0
              LD        D,H
              LD        E,L                            ; DE=old byte
              ADD       HL,HL                          ; 2x
              ADD       HL,HL                          ; 4x
              ADD       HL,HL                          ; 8x
              ADD       HL,HL                          ; 16x
              ADD       HL,HL                          ; 32x
              ADD       HL,HL                          ; 64x
              ADD       HL,DE                          ; 65x
              SLA       E
              RL        D
              SLA       E
              RL        D                              ; DE=4x
              ADD       HL,DE                          ; 69x
              LD        E,C
              LD        D,0
              ADD       HL,DE                          ; plus incoming carry
              LD        C,H                            ; outgoing carry
              LD        A,L                            ; new byte
              POP       HL
              LD        (HL),A
              DEC       HL
              DJNZ      M69LOOP
              RET

; BIGNUM = BIGNUM*36 + A (0..35).
B69M36        LD        C,A
              LD        HL,B69BIG+8
              LD        B,9
M36LOOP       PUSH      HL
              LD        L,(HL)
              LD        H,0
              ADD       HL,HL
              ADD       HL,HL                          ; 4x
              LD        D,H
              LD        E,L                            ; DE=4x
              ADD       HL,HL
              ADD       HL,HL
              ADD       HL,HL                          ; 32x
              ADD       HL,DE                          ; 36x
              LD        E,C
              LD        D,0
              ADD       HL,DE
              LD        C,H
              LD        A,L
              POP       HL
              LD        (HL),A
              DEC       HL
              DJNZ      M36LOOP
              RET

; BIGNUM /= A (base 36 or 69); return remainder in A.
; Eight quotient bits per byte, MSB first, using shift-and-subtract.
B69DIV        LD        (B69BASE),A
              PUSH      IX
              LD        IX,B69BASE
              LD        HL,B69BIG
              LD        B,9
              LD        C,0                            ; remainder so far
V69BYTE       PUSH      BC                             ; save byte count
              LD        E,(HL)                         ; original dividend byte
              LD        D,0                            ; new quotient byte
              LD        B,8
V69BIT        SLA       E                              ; incoming dividend bit -> carry
              LD        A,C
              ADC       A,A                            ; rem*2 + incoming bit, 0..137
              CP        (IX+0)                         ; compare to divisor
              JR        C,V69ZERO
              SUB       (IX+0)
              LD        C,A                            ; updated remainder
              SCF                                      ; quotient bit 1
              JR        V69Q
V69ZERO       LD        C,A
              OR        A                              ; quotient bit 0 (clear carry)
V69Q          RL        D                              ; append quotient bit
              DJNZ      V69BIT
              LD        (HL),D
              INC       HL
              LD        A,C                            ; preserve remainder while popping counter
              POP       BC
              LD        C,A
              DJNZ      V69BYTE
              POP       IX
              LD        A,C
              RET

B69INT        DEFW      0
B69OUT        DEFW      0
B69BASE       DEFB      0
B69BIG        DEFS      9

; Check whether an FCB name can be represented *unchanged* on ProDOS.
; HL-> eleven FCB name bytes. A=0 normal; FF requires base69 escape.
; B,C,DE,HL clobbered.  Name and extension must be canonical
; (spaces only at the end of each field), no lower-case or punctuation.
B69NEED       LD        A,(HL)
              AND       07FH
              CP        'A'
              JR        C,B69REQ
              CP        'Z'+1
              JR        NC,B69REQ
              LD        B,8
              CALL      B69DIR
              RET       NZ
              LD        B,3
              CALL      B69DIR
              RET
B69DIR        LD        E,0                            ; seen-padding marker
B69DL         LD        A,(HL)
              AND       07FH
              CP        ' '
              JR        Z,B69PAD
              LD        D,A
              LD        A,E
              OR        A
              JR        NZ,B69REQ
              LD        A,D
              CP        '0'
              JR        C,B69REQ
              CP        '9'+1
              JR        C,B69DG
              CP        'A'
              JR        C,B69REQ
              CP        'Z'+1
              JR        NC,B69REQ
              JR        B69DG
B69PAD        LD        E,1
B69DG         INC       HL
              DJNZ      B69DL
              XOR       A
              RET
B69REQ        LD        A,0FFH
              RET

; Validate a decoded name: printable uppercase canonical FCB, no CP/M
; directory metacharacters, must actually require escaping.
; HL -> 11 decoded bytes; A=0 valid, FF invalid; trashes BC/DE/HL.
B69ILGL       DEFB      03CH,03EH,02CH,02EH,03BH,03AH,03DH,03FH,02AH,05BH,05DH
B69BAD        DEFB      0
; Bridge from FCB2PATH; keep IX/IY and source DE unchanged.
; Returns A=0 for ordinary name, FF if encoded; DE preserved.
B69PTH        PUSH      BC
              PUSH      DE
              PUSH      HL
              CALL      B69NEED
              POP       HL
              POP       DE
              POP       BC
              OR        A
              RET       Z
              ; Only canonical CP/M 8.3 names can round-trip through DIR.
              PUSH      BC
              PUSH      DE
              PUSH      HL
              CALL      B69CAN
              POP       HL
              POP       DE
              POP       BC
              OR        A
              JR        NZ,B69PFAL
              PUSH      BC                             ; preserve variable user-directory prefix length
              PUSH      DE
              PUSH      IX
              POP       DE
              CALL      B69ENC
              POP       DE
              POP       BC
              OR        A
              JR        NZ,B69PFAL
              LD        A,C                            ; prefix length (2..4)
              ADD       A,15                           ; encoded ProDOS component
              LD        (IY+0),A
              LD        A,0FFH
              RET
B69PFAL       XOR       A                              ; invalid input: safe empty pathname
              LD        (IY+0),A
              DEC       A
              RET

; Decode a 15-character Z.<13> alias, or decline if not our prefix.
; HL=dirent, DE=DMA FCB drive byte; clobbers BC/DE/HL and IX.
; Return A=0 valid, A=1 not an alias, A=FF invalid alias (skip entry).
B69TRY        INC       HL
              LD        A,(HL)
              CP        'Z'
              JR        NZ,B69TNOT
              INC       HL
              LD        A,(HL)
              CP        '.'
              JR        NZ,B69TNOT
              DEC       HL
              INC       DE
              CALL      B69DEC
              OR        A
              JR        NZ,B69TBAD
              LD        HL,(DMAADDR)
              INC       HL
              CALL      B69CAN
              OR        A
              RET       Z
B69TBAD       LD        A,0FFH
              LD        (B69BAD),A
              RET
B69TNOT       LD        A,1
              RET
B69CAN        PUSH      HL
              LD        A,(HL)
              CP        ' '
              JR        Z,B69CERR
              LD        B,8
              CALL      B69PART
              OR        A
              JR        NZ,B69CERR
              LD        B,3
              CALL      B69PART
              OR        A
              JR        NZ,B69CERR
              POP       HL
              CALL      B69NEED
              OR        A
              JP        Z,B69REQ                       ; only non-native CP/M names are escaped
              XOR       A
              RET
B69CERR       POP       HL
              JP        B69REQ
B69PART       LD        C,0                            ; seen spaces
B69PLP        LD        A,(HL)
              CP        ' '
              JR        Z,B69PSP
              CP        021H
              JP        C,B69REQ
              CP        07FH
              JP        NC,B69REQ
              LD        D,A
              LD        A,C
              OR        A
              JP        NZ,B69REQ
              LD        A,D
              CP        061H
              JR        C,B69PCK
              CP        07BH
              JP        C,B69REQ
B69PCK        PUSH      HL
              PUSH      BC
              LD        HL,B69ILGL
              LD        B,11
B69PCL        CP        (HL)
              JR        Z,B69PERR
              INC       HL
              DJNZ      B69PCL
              POP       BC
              POP       HL
              JR        B69POK
B69PERR       POP       BC
              POP       HL
              JP        B69REQ
B69PSP        LD        C,1
B69POK        INC       HL
              DJNZ      B69PLP
              XOR       A
              RET


B69END

; Phase 3: W5100 socket ownership. Private AUX BDOS $FA.
; E=0 ALLOC -> A=L=socket 0..3 or FF; E=1 FREE D=socket,
; E=2 INFO -> A=L=managed allocations bitmask. No AUX pointers.
; The W5100 hardware state remains authoritative for external users:
; a socket may be allocated only when SR==SOCK_CLOSED (00h).
; Ownership is separately tracked so a just-allocated CLOSED socket
; cannot be claimed by another task before its OPEN command.
; This code runs in MAIN, serially inside AXGATE. The bridge is slot 5.
; NETCLN receives B=logical task, used on normal child exit and KILL.
NETAPI        LD        A,E
              OR        A
              JP        Z,NETALLOC
              CP        1
              JP        Z,NETFREE
              CP        2
              JP        Z,NETINFO
              JP        NETBAD
NETALLOC      LD        B,1                            ; preferred 1,2,3,0
NETTRY        LD        A,B
              CALL      NETPTR
              LD        A,(HL)
              CP        0FFH
              JR        NZ,NETNEXT
              ; Check actual W5100 SR without changing anything.
              PUSH      BC
              LD        A,B
              ADD       A,4
              LD        (AREG),A
              LD        A,3
              LD        (XREG),A
              LD        HL,0B824H
              LD        (ADDR),HL
              LD        A,1
              LD        (CMD),A
              LD        (SOFTCARD),A
              POP       BC
              LD        A,(AREG)
              OR        A
              JR        NZ,NETNEXT
              LD        A,B
              CALL      NETPTR
              LD        A,(TABMODE)
              LD        (HL),A
              LD        A,B
              JR        NETRET
NETNEXT       INC       B
              LD        A,B
              AND       3
              LD        B,A
              CP        1
              JR        NZ,NETTRY
              JR        NETBAD
NETFREE       LD        A,D
              CP        4
              JR        NC,NETBAD
              LD        C,A                            ; preserve socket number
              CALL      NETPTR
              LD        A,(TABMODE)
              CP        (HL)
              JR        NZ,NETBAD
              PUSH      HL                             ; ownership entry
              LD        A,C
              CALL      NETCLOSE                       ; CLOSE and verify SOCK_CLOSED
              POP       HL
              JR        C,NETBAD                       ; retain ownership on failure
              LD        (HL),0FFH
              LD        A,C
              CALL      NCSFRE                        ; remove stale UC1 binding for freed socket
              XOR       A
              JR        NETRET
NETINFO       LD        HL,NETOWN
              LD        B,4
              LD        C,0
              LD        D,1
NETILP        LD        A,(HL)
              CP        0FFH
              JR        Z,NETISK
              LD        A,C
              OR        D
              LD        C,A
NETISK        SLA       D
              INC       HL
              DJNZ      NETILP
              LD        A,C
              JR        NETRET
NETBAD        LD        A,0FFH
NETRET        LD        L,A
              RET
; A=socket, returns HL->owner entry, preserves B.
NETPTR        LD        E,A
              LD        D,0
              LD        HL,NETOWN
              ADD       HL,DE
              RET
; B=owner task. Only close sockets allocated through this API.
; Close a specific physical socket, verifying it reaches CLOSED.
; A=socket 0..3. Carry clear if closed, set if timeout.
; Preserves BC, DE, HL. W5100 CR=01, SR=03, socket base=0400+0100*n.
; Never touches external sockets: caller must check ownership first.
NETCLOSE      PUSH      BC
              PUSH      DE
              PUSH      HL
              LD        E,A                            ; socket number
              ADD       A,4
              LD        D,A                            ; address high
              LD        (AREG),A
              LD        A,1
              LD        (XREG),A                        ; socket command register
              LD        A,010H
              LD        (YREG),A                        ; CLOSE command
              LD        HL,0B827H                       ; 6502 W5WRITE
              LD        (ADDR),HL
              LD        A,1
              LD        (CMD),A
              LD        (SOFTCARD),A
              LD        B,128                          ; bounded confirmation polling
NCLPOLL       LD        A,D
              LD        (AREG),A
              LD        A,3
              LD        (XREG),A                        ; Sn_SR
              LD        HL,0B824H                       ; 6502 W5READ
              LD        (ADDR),HL
              LD        A,1
              LD        (CMD),A
              LD        (SOFTCARD),A
              LD        A,(AREG)
              OR        A
              JR        Z,NCLOK
              DJNZ      NCLPOLL
              SCF                                      ; still not CLOSED
              JR        NCLDONE
NCLOK         OR        A                              ; clear carry
NCLDONE       POP       HL
              POP       DE
              POP       BC
              RET

; B=owner task. Close only sockets owned by that task.
; Keep ownership if hardware closure cannot be confirmed.
NETCLN        CALL      NCKCLN                        ; keep armed UC1 across child exit
              LD        C,0
NETCLP        LD        A,C
              CALL      NETPTR
              LD        A,(HL)
              CALL      NCKMATCH                      ; Z: owned and not persistent
              JR        NZ,NETCLNEXT
              PUSH      BC
              PUSH      HL
              LD        A,C
              CALL      NETCLOSE
              POP       HL
              POP       BC
              JR        C,NETCLNEXT
              LD        (HL),0FFH
NETCLNEXT     INC       C
              LD        A,C
              CP        4
              JR        NZ,NETCLP
              RET
NETOWN        DEFB      0FFH,0FFH,0FFH,0FFH

; Phase 4A.3: $FB moved to $9400 (see above). Keep stack headroom
; and all W5100 socket ownership data here unchanged.
NETEND

; Stack grows from $A800 down to NETEND.
; Compile guard: negative DEFS if the codec doesn't fit.
Z80STACK      DEFS      STCKTOP-NETEND

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


