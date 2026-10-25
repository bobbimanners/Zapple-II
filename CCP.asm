; Zapple-II AUX CCP 1.1.1 (Stage 23.2; SAVE parser correction)
; Standard CP/M 2.2 BDOS for built-ins; private BDOS F7 for program chaining.
; Requires Stage 13 kernel: F7 copies launch FCB + FCB1 + FCB2 + command tail.
; Transient program memory is AUX; tab switches retain command and stack.
; F7 parameter block: 36-byte COM FCB, 16-byte default FCB1,
; 16-byte default FCB2, 128-byte command tail (CP/M 0080h format).
            ORG     0100H
START       LD      DE,BANNER
            CALL    PRINT
MAINLOOP    CALL    PROMPT
            CALL    READLINE
            LD      HL,LINE
            CALL    SKSP
            LD      (CMDPTR),HL
            LD      A,(HL)
            OR      A
            JP      Z,MAINLOOP
            LD      A,(HL)
            CP      'A'
            JR      C,CMDSCAN
            CP      'P'+1
            JR      NC,CMDSCAN
            INC     HL
            LD      A,(HL)
            CP      ':'
            JR      NZ,CMDSCAN
            INC     HL
            LD      A,(HL)
            OR      A
            JR      NZ,CMDSCAN
            LD      HL,(CMDPTR)
            LD      A,(HL)
            SUB     'A'
            LD      E,A
            LD      C,14
            CALL    0005H
            JP      MAINLOOP
CMDSCAN     LD      HL,(CMDPTR)
CSNEXT      LD      A,(HL)
            OR      A
            JR      Z,CSEOL
            CP      ' '
            JR      Z,CSSP
            INC     HL
            JR      CSNEXT
CSSP        LD      (HL),0
            INC     HL
            CALL    SKSP
CSEOL       LD      (ARGPTR),HL
            LD      HL,(CMDPTR)
            LD      DE,KDIR
            CALL    MATCH
            JP      Z,DODIR
            LD      HL,(CMDPTR)
            LD      DE,KTYPE
            CALL    MATCH
            JP      Z,DOTYPE
            LD      HL,(CMDPTR)
            LD      DE,KERA
            CALL    MATCH
            JP      Z,DOERA
            LD      HL,(CMDPTR)
            LD      DE,KREN
            CALL    MATCH
            JP      Z,DOREN
            LD      HL,(CMDPTR)
            LD      DE,KUSER
            CALL    MATCH
            JP      Z,DOUSER
            LD      HL,(CMDPTR)
            LD      DE,KHELP
            CALL    MATCH
            JP      Z,DOHELP
            LD      HL,(CMDPTR)
            LD      DE,KEXIT
            CALL    MATCH
            JP      Z,DOEXIT
            LD      HL,(CMDPTR)
            LD      DE,KCLS
            CALL    MATCH
            JP      Z,DOCLS
            LD      HL,(CMDPTR)
            LD      DE,KBANKS
            CALL    MATCH
            JP      Z,DOBANKS
            LD      HL,(CMDPTR)
            LD      DE,KCACHE
            CALL    MATCH
            JP      Z,DOCACHE
            LD      HL,(CMDPTR)
            LD      DE,KTERM
            CALL    MATCH
            JP      Z,DOTERM
            LD      HL,(CMDPTR)
            LD      DE,KTAB
            CALL    MATCH
            JP      Z,DOTAB
            LD      HL,(CMDPTR)
            LD      DE,KXSUB
            CALL    MATCH
            JP      Z,DOXSUB
            LD      HL,(CMDPTR)
            LD      DE,KBYE
            CALL    MATCH
            JP      Z,DOBYE
            LD      HL,(CMDPTR)
            LD      DE,KSAVE
            CALL    MATCH
            JP      Z,DOSAVE
            JP      DOEXEC

; Match the legacy CCP prompt exactly: [0]A:>, [1]A3:>, [F]B12:>.
; Private BDOS F8/id 8 returns the logical TABMODE session in A and L.
; MAIN owns TABMODE and it cannot be read directly from AUX TPA.
; BDOS 25 queries drive; BDOS 32/E=FFh queries the active USER.
PROMPT      LD      A,8
            LD      (BXID),A
            LD      DE,BXID
            LD      C,0F8H
            CALL    0005H
            AND     0FH
            CP      10
            JR      C,PRMDIG
            ADD     A,37H                       ; hex A..F
            JR      PRMCHAR
PRMDIG      ADD     A,30H                       ; hex 0..9
PRMCHAR     PUSH    AF
            LD      A,'['
            CALL    OUT
            POP     AF
            CALL    OUT
            LD      A,']'
            CALL    OUT
            LD      C,25
            CALL    0005H
            ADD     A,'A'
            CALL    OUT
            LD      E,0FFH
            LD      C,32
            CALL    0005H
            OR      A
            JR      Z,PRMEND
            CALL    PRINTNUM
PRMEND      LD      A,':'
            CALL    OUT
            LD      A,'>'
            JP      OUT

; Reuse the kernel's BDOS 10 editor (raw input, BS/DEL, no double echo).
; Convert the returned CP/M [max][count][characters][CR] buffer to
; the original NUL-terminated, uppercase LINE used by the parser.
READLINE    LD      DE,INBUF
            LD      A,78
            LD      (DE),A
            LD      C,10
            CALL    0005H
            LD      A,(INBUF+1)
            LD      B,A
            LD      HL,INBUF+2
            LD      DE,LINE
RLCOPY      LD      A,B
            OR      A
            JR      Z,RLDONE
            LD      A,(HL)
            CP      'a'
            JR      C,RLKEEP
            CP      'z'+1
            JR      NC,RLKEEP
            SUB     32
RLKEEP      LD      (DE),A
            INC     DE
            INC     HL
            DJNZ    RLCOPY
RLDONE      XOR     A
            LD      (DE),A
            RET
SKSP        LD      A,(HL)
            CP      ' '
            RET     NZ
            INC     HL
            JR      SKSP
MATCH       LD      A,(DE)
            OR      A
            JR      Z,MBOUND
            CP      (HL)
            JR      NZ,MBAD
            INC     DE
            INC     HL
            JR      MATCH
MBOUND      LD      A,(HL)
            OR      A
            RET     Z
MBAD        LD      A,1
            OR      A
            RET

; Poll ^C non-destructively to stop a listing.
POLLKEY     PUSH    BC
            PUSH    DE
            PUSH    HL
            LD      E,0FFH
            LD      C,6
            CALL    0005H
            CP      3
            POP     HL
            POP     DE
            POP     BC
            RET

; Stage 14: four tidy columns, directory heading, accurate file count.
; Keep everything in AUX: the kernel and F7 chain interface are unchanged.
DODIR       CALL    SETDMA
            LD      HL,(ARGPTR)
            LD      A,(HL)
            OR      A
            JR      Z,DIRALL
            ; Accept DIR B: as shorthand for DIR B:*.*.
            LD      B,A
            INC     HL
            LD      A,(HL)
            CP      ':'
            JR      NZ,DIRPAT
            INC     HL
            LD      A,(HL)
            OR      A
            JR      NZ,DIRPAT
            LD      A,B
            CP      'A'
            JP      C,SHOWBAD
            CP      'P'+1
            JP      NC,SHOWBAD
            SUB     'A'-1
            LD      (DIRDRIVE),A
            CALL    FCBWILD
            LD      A,(DIRDRIVE)
            LD      (FCB),A
            JR      DIRFIRST
DIRPAT      LD      HL,(ARGPTR)
            LD      A,1
            LD      (ALLOWW),A
            CALL    PARSENAME
            JP      NZ,SHOWBAD
            JR      DIRFIRST
DIRALL      CALL    FCBWILD
DIRFIRST    XOR     A
            LD      (DIRCOL),A
            LD      (DIGSTART),A
            LD      HL,0
            LD      (DIRCOUNT),HL
            LD      DE,DIRHDR
            CALL    PRINT
            LD      A,(FCB)
            OR      A
            JR      NZ,DHEXPL
            LD      C,25                         ; current drive for FCB drive=0
            CALL    0005H
            INC     A
DHEXPL      ADD     A,'A'-1
            CALL    OUT
            LD      DE,DIRHDR2
            CALL    PRINT
            LD      E,0FFH
            LD      C,32                         ; current USER
            CALL    0005H
            CALL    PRINTNUM
            LD      A,13
            CALL    OUT
            LD      DE,DIRRULE
            CALL    PRINT
            LD      DE,FCB
            LD      C,17
            CALL    0005H
            OR      A
            JP      NZ,DIRNONE
DIRLOOP     CALL    DIRFIELD
            LD      HL,(DIRCOUNT)
            INC     HL
            LD      (DIRCOUNT),HL
            LD      A,(DIRCOL)
            INC     A
            CP      4
            JR      NZ,DLCOL
            XOR     A
            LD      (DIRCOL),A
            LD      A,13
            CALL    OUT
            JR      DLNEXT
DLCOL       LD      (DIRCOL),A
DLNEXT      CALL    POLLKEY
            JP      Z,DIRABORT
            LD      DE,FCB
            LD      C,18
            CALL    0005H
            OR      A
            JP      Z,DIRLOOP
DIRFINISH   LD      A,(DIRCOL)
            OR      A
            JR      Z,DFCOUNT
            LD      A,13
            CALL    OUT
DFCOUNT     LD      DE,DIRTOTAL
            CALL    PRINT
            CALL    DIRDEC
            LD      DE,DIRTAIL
            CALL    PRINT
            JP      MAINLOOP
DIRABORT    LD      A,13
            CALL    OUT
            LD      DE,DIRSTOP
            CALL    PRINT
            JP      MAINLOOP
DIRNONE     LD      DE,EMPTYMSG
            CALL    PRINT
            JP      MAINLOOP

; Print one 19-column slot: NAME.EXT (unpadded) + spaces to 19.
; Four entries fit in 76 of the terminal's 80 columns.
DIRFIELD    LD      HL,DMA+1
            LD      B,8
            LD      C,0
DFBASE      LD      A,(HL)
            AND     07FH
            CP      ' '
            JR      Z,DFBSKIP
            CALL    OUT
            INC     C
DFBSKIP     INC     HL
            DJNZ    DFBASE
            LD      A,(DMA+9)
            AND     07FH
            CP      ' '
            JR      Z,DFPAD
            LD      A,'.'
            CALL    OUT
            INC     C
            LD      HL,DMA+9
            LD      B,3
DFEXT       LD      A,(HL)
            AND     07FH
            CP      ' '
            JR      Z,DFESKIP
            CALL    OUT
            INC     C
DFESKIP     INC     HL
            DJNZ    DFEXT
DFPAD       LD      A,19
            SUB     C
            LD      B,A
DFPLOOP     LD      A,' '
            CALL    OUT
            DJNZ    DFPLOOP
            RET

; Decimal count 0..65535 without an external run-time.
DIRDEC      LD      HL,(DIRCOUNT)
            XOR     A
            LD      (DIGSTART),A
            LD      DE,10000
            CALL    DECDIG
            LD      DE,1000
            CALL    DECDIG
            LD      DE,100
            CALL    DECDIG
            LD      DE,10
            CALL    DECDIG
            LD      A,L
            ADD     A,'0'
            JP      OUT
DECDIG      LD      B,0
DDLOOP      OR      A                          ; clear carry for 16-bit subtraction
            SBC     HL,DE
            JR      C,DDEND
            INC     B
            JR      DDLOOP
DDEND       ADD     HL,DE                       ; restore remainder
            LD      A,B
            OR      A
            JR      NZ,DDPRINT
            LD      A,(DIGSTART)
            OR      A
            RET     Z
            LD      A,'0'
            JP      OUT
DDPRINT     LD      A,1
            LD      (DIGSTART),A
            LD      A,B
            ADD     A,'0'
            JP      OUT
FCBWILD     CALL    FCBZERO
            LD      HL,FCB+1
            LD      B,11
            LD      A,'?'
FWLOOP      LD      (HL),A
            INC     HL
            DJNZ    FWLOOP
            RET
FCBZERO     LD      HL,FCB
            LD      B,36
            XOR     A
FZLOOP      LD      (HL),A
            INC     HL
            DJNZ    FZLOOP
            RET
SETDMA      LD      DE,DMA
            LD      C,26
            JP      0005H

DOTYPE      LD      HL,(ARGPTR)
            LD      A,(HL)
            OR      A
            JP      Z,SHOWBAD
            XOR     A
            LD      (ALLOWW),A
            CALL    PARSENAME
            JP      NZ,SHOWBAD
            CALL    SETDMA
            LD      DE,FCB
            LD      C,15
            CALL    0005H
            OR      A
            JP      NZ,SHOWNOTF
TYBLOCK     LD      DE,FCB
            LD      C,20
            CALL    0005H
            OR      A
            JR      NZ,TYCLOSE
            LD      HL,DMA
            LD      B,128
TYBYTE      LD      A,(HL)
            CP      1AH
            JR      Z,TYCLOSE
            OR      A
            JR      Z,TYSKIP
            CALL    OUT
TYSKIP      INC     HL
            PUSH    BC
            CALL    POLLKEY
            POP     BC
            JR      Z,TYCLOSE
            DJNZ    TYBYTE
            JR      TYBLOCK
TYCLOSE     LD      DE,FCB
            LD      C,16
            CALL    0005H
            LD      A,13
            CALL    OUT
            JP      MAINLOOP
SHOWNOTF    LD      DE,NOTFOUND
            CALL    PRINT
            JP      MAINLOOP
SHOWBAD     LD      DE,BADNAME
            CALL    PRINT
            JP      MAINLOOP
SHOWERR     LD      DE,FAILMSG
            CALL    PRINT
            JP      MAINLOOP

DOERA       LD      HL,(ARGPTR)
            LD      A,1
            LD      (ALLOWW),A
            CALL    PARSENAME
            JP      NZ,SHOWBAD
            CALL    HASWILD
            JR      Z,ERDELETE
            LD      DE,ERASK
            CALL    PRINT
            LD      C,1
            CALL    0005H
            CP      'Y'
            JP      NZ,MAINLOOP
ERDELETE    LD      DE,FCB
            LD      C,19
            CALL    0005H
            OR      A
            JP      NZ,SHOWERR
            JP      MAINLOOP
HASWILD     LD      HL,FCB+1
            LD      B,11
HWLOOP      LD      A,(HL)
            CP      '?'
            JR      Z,HWFND
            INC     HL
            DJNZ    HWLOOP
            XOR     A
            RET
HWFND       LD      A,1
            OR      A
            RET

; REN new.ext=old.ext. Source is first FCB, destination goes at +16.
DOREN       LD      HL,(ARGPTR)
            LD      (RENDST),HL
RNEQ        LD      A,(HL)
            OR      A
            JP      Z,SHOWBAD
            CP      '='
            JR      Z,RNGOT
            INC     HL
            JR      RNEQ
RNGOT       LD      (HL),0
            INC     HL
            LD      A,(HL)
            OR      A
            JP      Z,SHOWBAD
            XOR     A
            LD      (ALLOWW),A
            CALL    PARSENAME                  ; old name
            JP      NZ,SHOWBAD
            LD      HL,FCB
            LD      DE,RENFCB
            LD      BC,36
            LDIR
            LD      HL,(RENDST)
            CALL    PARSENAME                  ; new name
            JP      NZ,SHOWBAD
            LD      A,(FCB)
            LD      B,A
            LD      A,(RENFCB)
            OR      A
            JR      Z,RNCOPY
            LD      A,B
            OR      A
            JR      Z,RNCOPY
            LD      A,(RENFCB)
            CP      B
            JP      NZ,SHOWBAD
RNCOPY      LD      HL,FCB+1
            LD      DE,RENFCB+17
            LD      BC,11
            LDIR
            LD      DE,RENFCB
            LD      C,23
            CALL    0005H
            OR      A
            JP      NZ,SHOWERR
            JP      MAINLOOP

DOUSER      LD      HL,(ARGPTR)
            LD      A,(HL)
            OR      A
            JR      NZ,USERSET
            LD      E,0FFH
            LD      C,32
            CALL    0005H
            CALL    PRINTNUM
            LD      A,13
            CALL    OUT
            JP      MAINLOOP
USERSET     CALL    NUMPARSE
            JP      NZ,SHOWBAD
            LD      E,A
            LD      C,32
            CALL    0005H
            JP      MAINLOOP
; decimal 0..15, no other characters; return A=value and Z success.
NUMPARSE    LD      A,(HL)
            SUB     '0'
            JR      C,NUMBAD
            CP      10
            JR      NC,NUMBAD
            LD      B,A
            INC     HL
            LD      A,(HL)
            OR      A
            JR      Z,NUMONE
            SUB     '0'
            JR      C,NUMBAD
            CP      10
            JR      NC,NUMBAD
            LD      D,A
            INC     HL
            LD      A,(HL)
            OR      A
            JR      NZ,NUMBAD
            LD      A,B
            ADD     A,A
            LD      E,A
            ADD     A,A
            ADD     A,A
            ADD     A,E                     ; B*10
            ADD     A,D
            CP      16
            JR      NC,NUMBAD
            CP      A                      ; return Z on valid nonzero number
            RET
NUMONE      LD      A,B
            CP      A
            RET
NUMBAD      LD      A,0FFH
            OR      A
            RET
PRINTNUM    CP      10
            JR      C,NUMSINGLE
            SUB     10
            LD      B,A
            LD      A,'1'
            CALL    OUT
            LD      A,B
NUMSINGLE   ADD     A,'0'
            JP      OUT

DOHELP      LD      DE,HELPMSG
            CALL    PRINT
            JP      MAINLOOP
DOEXIT      LD      DE,GOODBYE
            CALL    PRINT
            RET

; Stage 19: private BDOS $F8 bridge to the MAIN-only CCP handlers.
; Record is 1-byte command ID followed by 80 bytes of normalized
; FILEBUF tail (length, leading space, argument(s), trailing space, NUL).
; MAIN dispatch checks that this request originates in an AUX shell.
DOCLS       LD      A,1
            JP      BXCMD
DOBANKS     LD      A,2
            JP      BXCMD
DOCACHE     LD      A,3
            JP      BXCMD
DOTERM      LD      A,4
            JP      BXCMD
; Stage 21: accept both TAB n ACTION and TAB ACTION n.
; Stage 19's private BDOS F8 already forwards the standard normalized
; tail to the native TBCMD parser; only action-first input needs reordering.
DOTAB       LD      HL,(ARGPTR)
            LD      DE,TBSWITCH
            CALL    TBHEAD
            JP      Z,TBVSWITCH
            LD      HL,(ARGPTR)
            LD      DE,TBSUSPEND
            CALL    TBHEAD
            JP      Z,TBVSUSPEND
            LD      HL,(ARGPTR)
            LD      DE,TBRESUME
            CALL    TBHEAD
            JP      Z,TBVRESUME
            LD      HL,(ARGPTR)
            LD      DE,TBEXCLUSIVE
            CALL    TBHEAD
            JP      Z,TBVEXCLUSIVE
            LD      HL,(ARGPTR)
            LD      DE,TBKILL
            CALL    TBHEAD
            JP      Z,TBVKILL
            LD      A,5
            JP      BXCMD
; On match HL points at the separating space before the argument.
TBHEAD      LD      A,(DE)
            OR      A
            JR      Z,TBHEND
            CP      (HL)
            RET     NZ
            INC     HL
            INC     DE
            JR      TBHEAD
TBHEND      LD      A,(HL)
            CP      ' '
            RET
TBVSWITCH   LD      DE,TBEMPTY
            JP      TBREORDER
TBVSUSPEND  LD      DE,TBSUSPEND
            JP      TBREORDER
TBVRESUME   LD      DE,TBRESUME
            JP      TBREORDER
TBVEXCLUSIVE LD     DE,TBEXCLUSIVE
            JP      TBREORDER
TBVKILL     LD      DE,TBKILL
; HL=space following action; DE=action string, or NUL for SWITCH.
; Numeric selector is a single 0..9/A..F character, range checked
; by the native TABDECODE routine in the kernel.
TBREORDER   INC     HL
            CALL    SKSP
            LD      A,(HL)
            OR      A
            JP      Z,SHOWBAD
            LD      (TABCAN),A
            INC     HL
            CALL    SKSP
            LD      A,(HL)
            OR      A
            JP      NZ,SHOWBAD
            LD      A,(DE)
            OR      A
            JR      NZ,TBRVERB
            LD      (TABCAN+1),A
            JR      TBRDONE
TBRVERB     LD      A,' '
            LD      (TABCAN+1),A
            LD      HL,TABCAN+2
TBRCOPY     LD      A,(DE)
            LD      (HL),A
            OR      A
            JR      Z,TBRDONE
            INC     HL
            INC     DE
            JR      TBRCOPY
TBRDONE     LD      HL,TABCAN
            LD      (ARGPTR),HL
            LD      A,5
            JP      BXCMD
DOXSUB      LD      A,6
            JP      BXCMD
DOBYE       LD      A,7
            JP      BXCMD
; SAVE pages filename -- preserves the previous transient image in a
; dedicated RamWorks screen bank before CCP.COM replaces low TPA.
; F8/9 receives the ordinary normalized command tail followed by FCB2.
; Check syntax before calling the native kernel SAVEFILE implementation.
DOSAVE      LD      HL,(ARGPTR)
            LD      B,0
SVNUMLOOP   LD      A,(HL)
            CP      ' '                         ; space ends the page count
            JR      Z,SVNUMEND                  ; don't reject it as < '0'
            CP      '0'
            JP      C,SHOWBAD
            CP      '9'+1
            JR      NC,SVNUMEND
            INC     B
            LD      A,B
            CP      4
            JP      NC,SHOWBAD                   ; maximum three digits
            INC     HL
            JR      SVNUMLOOP
SVNUMEND    LD      A,B
            OR      A
            JP      Z,SHOWBAD
            LD      A,(HL)
            CP      ' '
            JP      NZ,SHOWBAD
            CALL    SKSP
            LD      A,(HL)
            OR      A
            JP      Z,SHOWBAD
            LD      (SVFPTR),HL
            XOR     A
            LD      (ALLOWW),A
            CALL    PARSENAME
            JP      NZ,SHOWBAD
            LD      HL,(SVFPTR)
SVFEND      LD      A,(HL)
            OR      A
            JR      Z,SVFOK
            CP      ' '
            JR      Z,SVFTRAIL
            INC     HL
            JR      SVFEND
SVFTRAIL    CALL    SKSP
            LD      A,(HL)
            OR      A
            JP      NZ,SHOWBAD
SVFOK       LD      HL,FCB
            LD      DE,BXFCB
            LD      BC,36
            LDIR
            LD      A,9
            JP      BXCMD
BXCMD       LD      (BXID),A
            CALL    BXBUILD
            LD      DE,BXID
            LD      C,0F8H
            CALL    0005H
            JP      MAINLOOP
BXBUILD     LD      HL,BXTAIL
            LD      B,80
            XOR     A
BXZERO      LD      (HL),A
            INC     HL
            DJNZ    BXZERO
            LD      HL,(ARGPTR)
            LD      A,(HL)
            OR      A
            RET     Z
            LD      DE,BXTAIL+1
            LD      A,' '
            LD      (DE),A
            INC     DE
            LD      B,1
BXCOPY      LD      A,(HL)
            OR      A
            JR      Z,BXFIN
            LD      C,A
            LD      A,B
            CP      76
            JR      NC,BXFIN
            LD      A,C
            LD      (DE),A
            INC     HL
            INC     DE
            INC     B
            JR      BXCOPY
BXFIN       LD      A,' '
            LD      (DE),A
            INC     DE
            INC     B
            XOR     A
            LD      (DE),A
            LD      A,B
            LD      (BXTAIL),A
            RET

; Plain 8.3 filename parser with drive prefix and '?'/'*' wildcard support.
; Input HL: token (NUL, space or '=' terminates). Output FCB (36 bytes).
; ALLOWW=1 permits '?'/'*', 0 requires exact name. Z=success.
PARSENAME   PUSH    HL
            CALL    FCBZERO
            LD      HL,FCB+1
            LD      B,11
            LD      A,' '
PFFILL      LD      (HL),A
            INC     HL
            DJNZ    PFFILL
            POP     HL
            LD      A,(HL)
            OR      A
            JP      Z,PINVALID
            INC     HL
            LD      A,(HL)
            CP      ':'
            JR      NZ,PNODRV
            DEC     HL
            LD      A,(HL)
            SUB     'A'-1
            JP      C,PINVALID
            OR      A
            JP      Z,PINVALID
            CP      17
            JP      NC,PINVALID
            LD      (FCB),A
            INC     HL
            INC     HL
            JR      PSTART
PNODRV     DEC     HL
PSTART      LD      DE,FCB+1
            LD      B,8
PNAME       LD      A,(HL)
            OR      A
            JR      Z,PNAMEDONE
            CP      ' '
            JR      Z,PNAMEDONE
            CP      '='
            JR      Z,PNAMEDONE
            CP      '.'
            JR      Z,PEXTBEGIN
            CP      '*'
            JR      Z,PNSTAR
            CP      '?'
            JR      NZ,PNCHAR
            LD      A,(ALLOWW)
            OR      A
            JP      Z,PINVALID
            LD      A,'?'
            JR      PNSTORE
PNCHAR      CALL    VALIDCHAR
            JP      NZ,PINVALID
            LD      A,(HL)
PNSTORE     LD      C,A
            LD      A,B
            OR      A
            JP      Z,PINVALID
            LD      A,C
            LD      (DE),A
            INC     DE
            INC     HL
            DEC     B
            JR      PNAME
PNSTAR      LD      A,(ALLOWW)
            OR      A
            JP      Z,PINVALID
            INC     HL
            LD      A,(HL)
            OR      A
            JR      Z,PNSTA0
            CP      ' '
            JR      Z,PNSTA0
            CP      '='
            JR      Z,PNSTA0
            CP      '.'
            JP      NZ,PINVALID
PNSTA0      LD      A,B
            OR      A
            JP      Z,PINVALID
            LD      A,'?'
PNSTA1      LD      (DE),A
            INC     DE
            DJNZ    PNSTA1
            LD      A,(HL)
            CP      '.'
            JR      Z,PEXTBEGIN
            LD      DE,FCB+9
            LD      B,3
            LD      A,'?'
PNSTA2      LD      (DE),A
            INC     DE
            DJNZ    PNSTA2
            JR      PVALID
PNAMEDONE  LD      A,B
            CP      8
            JR      Z,PINVALID
            JR      PENDCHECK
PEXTBEGIN   LD      A,B
            CP      8
            JR      Z,PINVALID
            INC     HL
            LD      DE,FCB+9
            LD      B,3
PEXTL       LD      A,(HL)
            OR      A
            JR      Z,PENDCHECK
            CP      ' '
            JR      Z,PENDCHECK
            CP      '='
            JR      Z,PENDCHECK
            CP      '*'
            JR      Z,PXSTAR
            CP      '.'
            JR      Z,PINVALID
            CP      '?'
            JR      NZ,PXCHAR
            LD      A,(ALLOWW)
            OR      A
            JR      Z,PINVALID
            LD      A,'?'
            JR      PXSTORE
PXCHAR      CALL    VALIDCHAR
            JR      NZ,PINVALID
            LD      A,(HL)
PXSTORE     LD      C,A
            LD      A,B
            OR      A
            JR      Z,PINVALID
            LD      A,C
            LD      (DE),A
            INC     DE
            INC     HL
            DEC     B
            JR      PEXTL
PXSTAR      LD      A,(ALLOWW)
            OR      A
            JR      Z,PINVALID
            INC     HL
            LD      A,(HL)
            OR      A
            JR      Z,PXSFILL
            CP      ' '
            JR      Z,PXSFILL
            CP      '='
            JR      NZ,PINVALID
PXSFILL     LD      A,B
            OR      A
            JP      Z,PINVALID
            LD      A,'?'
PXS1        LD      (DE),A
            INC     DE
            DJNZ    PXS1
PENDCHECK   LD      A,(HL)
            OR      A
            JR      Z,PVALID
            CP      ' '
            JR      Z,PVALID
            CP      '='
            JR      Z,PVALID
PINVALID    LD      A,1
            OR      A
            RET
PVALID      XOR     A
            RET
; accept letters/digits and CP/M filename punctuation except separators
VALIDCHAR   CP      '!'
            JR      C,VINVALID
            CP      07FH
            JR      NC,VINVALID
            CP      '/'
            JR      Z,VINVALID
            CP      ':'
            JR      Z,VINVALID
            CP      03BH                    ; semicolon literal (Udo Munk Z80ASM-safe)
            JR      Z,VINVALID
            CP      '<'
            JR      Z,VINVALID
            CP      '>'
            JR      Z,VINVALID
            CP      '['
            JR      Z,VINVALID
            CP      ']'
            JR      Z,VINVALID
            CP      ','
            JR      Z,VINVALID
            CP      '='
            JR      Z,VINVALID
            CP      '.'
            JR      Z,VINVALID
            XOR     A
            RET
VINVALID    LD      A,1
            OR      A
            RET

; Execute .COM. Build CP/M tail + two default FCBs and hand them to F7.
DOEXEC      XOR     A
            LD      (ALLOWW),A
            LD      HL,(CMDPTR)
            CALL    PARSENAME
            JP      NZ,SHOWBAD
            LD      A,(FCB+9)
            CP      ' '
            JR      NZ,EXEXT
            LD      A,'C'
            LD      (FCB+9),A
            LD      A,'O'
            LD      (FCB+10),A
            LD      A,'M'
            LD      (FCB+11),A
EXEXT       LD      A,(FCB+9)
            CP      'C'
            JP      NZ,SHOWBAD
            LD      A,(FCB+10)
            CP      'O'
            JP      NZ,SHOWBAD
            LD      A,(FCB+11)
            CP      'M'
            JP      NZ,SHOWBAD
            LD      HL,FCB
            LD      DE,EXPAR
            LD      BC,36
            LDIR
            LD      HL,EXF1
            LD      B,32
            XOR     A
EXFCLEAR    LD      (HL),A
            INC     HL
            DJNZ    EXFCLEAR
            LD      HL,EXF1+1
            LD      B,11
            LD      A,' '
EXFBL1      LD      (HL),A
            INC     HL
            DJNZ    EXFBL1
            LD      HL,EXF2+1
            LD      B,11
EXFBL2      LD      (HL),A
            INC     HL
            DJNZ    EXFBL2
            LD      HL,EXTAIL
            LD      B,128
            XOR     A
EXTCLEAR    LD      (HL),A
            INC     HL
            DJNZ    EXTCLEAR
            LD      HL,(ARGPTR)
            LD      A,(HL)
            OR      A
            JR      Z,EXNOTAIL
            LD      DE,EXTAIL+1
            LD      A,' '
            LD      (DE),A
            INC     DE
            LD      B,1
EXTCOPY     LD      A,(HL)
            OR      A
            JR      Z,EXTDONE
            LD      C,A
            LD      A,B
            CP      126
            JR      NC,EXTDONE
            LD      A,C
            LD      (DE),A
            INC     HL
            INC     DE
            INC     B
            JR      EXTCOPY
EXTDONE     LD      A,' '                    ; match MAIN CCP's trailing delimiter
            LD      (DE),A
            INC     DE
            INC     B
            XOR     A                             ; matching MAIN CCP's NUL terminator
            LD      (DE),A
            LD      A,B
            LD      (EXTAIL),A
            ; Prepare default FCBs; preserve EXPAR so child name survives.
            LD      HL,(ARGPTR)
            LD      A,1
            LD      (ALLOWW),A
            CALL    PARSENAME
            JR      NZ,EXNOF1
            LD      HL,FCB
            LD      DE,EXF1
            LD      BC,16
            LDIR
EXNOF1      LD      HL,(ARGPTR)
EXFINDSP    LD      A,(HL)
            OR      A
            JR      Z,EXNOTAIL
            CP      ' '
            JR      Z,EXF2START
            INC     HL
            JR      EXFINDSP
EXF2START   CALL    SKSP
            LD      A,(HL)
            OR      A
            JR      Z,EXNOTAIL
            CALL    PARSENAME
            JR      NZ,EXNOTAIL
            LD      HL,FCB
            LD      DE,EXF2
            LD      BC,16
            LDIR
EXNOTAIL    LD      A,0
            LD      (EXTAIL+1),A               ; NUL when no args
            LD      A,(EXTAIL)
            OR      A
            JR      Z,EXGO
            ; restore first tail character (no modification to the buffer)
            LD      A,' '
            LD      (EXTAIL+1),A
EXGO        LD      DE,EXPAR
            LD      C,0F7H
            CALL    0005H                    ; success never returns to AUX CCP
            LD      DE,EXFAIL
            CALL    PRINT
            JP      MAINLOOP

PRINT       LD      C,9
            JP      0005H
OUT         PUSH    AF
            PUSH    BC
            PUSH    DE
            PUSH    HL
            LD      E,A
            LD      C,2
            CALL    0005H
            POP     HL
            POP     DE
            POP     BC
            POP     AF
            RET

BANNER      DEFM    'Zapple-II AUX CCP 1.1.1 (Stage 23.2)'
            DEFB    13,'$'
KDIR        DEFM    'DIR'
            DEFB    0
KTYPE       DEFM    'TYPE'
            DEFB    0
KERA        DEFM    'ERA'
            DEFB    0
KREN        DEFM    'REN'
            DEFB    0
KUSER       DEFM    'USER'
            DEFB    0
KHELP       DEFM    'HELP'
            DEFB    0
KEXIT       DEFM    'EXIT'
            DEFB    0
KCLS        DEFM    'CLS'
            DEFB    0
KBANKS      DEFM    'BANKS'
            DEFB    0
KCACHE      DEFM    'CACHE'
            DEFB    0
KTERM       DEFM    'TERM'
            DEFB    0
KTAB        DEFM    'TAB'
            DEFB    0
TBSWITCH    DEFM    'SWITCH'
            DEFB    0
TBSUSPEND   DEFM    'SUSPEND'
            DEFB    0
TBRESUME    DEFM    'RESUME'
            DEFB    0
TBEXCLUSIVE DEFM    'EXCLUSIVE'
            DEFB    0
TBKILL      DEFM    'KILL'
            DEFB    0
TBEMPTY     DEFB    0
KXSUB       DEFM    'XSUB'
            DEFB    0
KBYE        DEFM    'BYE'
            DEFB    0
KSAVE       DEFM    'SAVE'
            DEFB    0
DIRHDR      DEFM    'Directory of '
            DEFB    '$'
DIRHDR2     DEFM    ':   USER '
            DEFB    '$'
DIRRULE     DEFM    '------------------------------------------------------------------------'
            DEFB    13,'$'
DIRTOTAL    DEFM    'Files: $'
DIRTAIL     DEFB    13,'$'
DIRSTOP     DEFM    '^C  Directory interrupted'
            DEFB    13,'$'
EMPTYMSG    DEFM    'No matching files'
            DEFB    13,'$'
NOTFOUND    DEFM    'File not found'
            DEFB    13,'$'
BADNAME     DEFM    'Bad command or filename'
            DEFB    13,'$'
FAILMSG     DEFM    'File operation failed'
            DEFB    13,'$'
ERASK       DEFM    'Erase wildcard matches (Y/N)? $'
GOODBYE     DEFM    'Returning to MAIN CCP'
            DEFB    13,'$'
EXFAIL      DEFM    'Program launch failed (requires Stage 13 kernel)'
            DEFB    13,'$'
HELPMSG     DEFM    'DIR ERA REN TYPE USER    CLS BANKS CACHE [RESET]'
            DEFB    13
            DEFM    'TERM VT100/SOROC/H19/H89/VT52   TAB LIST/HELP'
            DEFB    13
            DEFM    'TAB SWITCH n, SUSPEND n, RESUME n, EXCLUSIVE n, KILL n'
            DEFB    13
            DEFM    'Also: TAB n [SUSPEND/RESUME/EXCLUSIVE/KILL]'
            DEFB    13
            DEFM    'XSUB BYE EXIT  A:..P:  program [args]'
            DEFB    13
            DEFM    'SAVE n file.ext (after a transient)'
            DEFB    13,'$'
SAVEWARN    DEFM    'SAVE unavailable: AUX CCP overwrote transient RAM'
            DEFB    13,'$'
CMDPTR      DEFW    LINE
ARGPTR      DEFW    LINE
RENDST      DEFW    LINE
SVFPTR      DEFW    LINE
LNPTR       DEFW    LINE
LNCOUNT     DEFB    0
ALLOWW      DEFB    0
DIRCOL      DEFB    0
DIRDRIVE    DEFB    0
DIGSTART    DEFB    0
DIRCOUNT    DEFW    0
LINE        DEFS    80
FCB         DEFS    36
RENFCB      DEFS    36
DMA         DEFS    128
; Structure consumed by private F7: 36+16+16+128 = 196 bytes
EXPAR       DEFS    36
EXF1        DEFS    16
EXF2        DEFS    16
EXTAIL      DEFS    128

INBUF       DEFS    82                          ; dedicated BDOS 10 input buffer
BXID        DEFB    0
BXTAIL      DEFS    80                          ; private F8 MAIN command tail
BXFCB       DEFS    36                          ; F8/9 SAVE target, must follow BXTAIL
TABCAN      DEFS    20                          ; TAB action-first canonical arguments
