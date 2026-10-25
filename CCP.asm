; Zapple-II AUX CCP 0.3 (Stage 13)
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
            JP      DOEXEC

PROMPT      LD      C,25
            CALL    0005H
            ADD     A,'A'
            CALL    OUT
            LD      A,':'
            CALL    OUT
            LD      A,'>'
            JP      OUT

; A plain AUX line editor. The entire line and its stack remain per tab.
READLINE    LD      HL,LINE
            LD      (LNPTR),HL
            XOR     A
            LD      (LNCOUNT),A
RLNEXT      LD      C,1
            CALL    0005H
            AND     07FH
            CP      13
            JR      Z,RLDONE
            CP      8
            JR      Z,RLBS
            CP      127
            JR      Z,RLBS
            CP      32
            JR      C,RLNEXT
            PUSH    AF
            LD      A,(LNCOUNT)
            CP      78
            JR      NC,RLFULL
            POP     AF
            CP      'a'
            JR      C,RLKEEP
            CP      'z'+1
            JR      NC,RLKEEP
            SUB     32
RLKEEP      LD      HL,(LNPTR)
            LD      (HL),A
            INC     HL
            LD      (LNPTR),HL
            LD      A,(LNCOUNT)
            INC     A
            LD      (LNCOUNT),A
            JR      RLNEXT
RLFULL      POP     AF
            JR      RLNEXT
RLBS        LD      A,(LNCOUNT)
            OR      A
            JR      Z,RLNEXT
            DEC     A
            LD      (LNCOUNT),A
            LD      HL,(LNPTR)
            DEC     HL
            LD      (LNPTR),HL
            LD      A,' '
            CALL    OUT
            LD      A,8
            CALL    OUT
            JR      RLNEXT
RLDONE      LD      HL,(LNPTR)
            LD      (HL),0
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
            CP      ';'
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
EXTDONE     LD      A,13
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
EXNOTAIL    LD      A,13
            LD      (EXTAIL+1),A               ; overwritten only if no args? see below
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

BANNER      DEFM    'Zapple-II AUX CCP 0.4 (Stage 14)'
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
HELPMSG     DEFM    'DIR [d:][pattern]  TYPE file  ERA pattern  REN new=old'
            DEFB    13
            DEFM    'USER [0-15]  A:..P:  HELP  EXIT  program [args]'
            DEFB    13,'$'
CMDPTR      DEFW    LINE
ARGPTR      DEFW    LINE
RENDST      DEFW    LINE
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
