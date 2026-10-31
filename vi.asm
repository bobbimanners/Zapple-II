; VI.COM 0.4a - small modal editor for Zapple-II / CP/M 2.2
; Soroc default; -V option (after filename) selects VT100.
; Udo Munk z80asm 1.1, ORG 0100H (strip FF 00 01 header).
; No kernel changes; text-only, 80x24, up to 14000 bytes in buffer.
;
; Source is intended for the user's Zapple-II kernel with CP/M BIOS
; CONST/CONIN and standard BDOS sequential file operations.
;
BDOS    EQU     0005H
MAXTXT  EQU     14000
ROWS    EQU     23

        ORG     0100H
START:  LD      (OLDSP),SP
        LD      SP,STKTOP
        CALL    INKEYS
        CALL    INITFCB
        CALL    ARGOPT
        CALL    LOADF
        XOR     A
        LD      (MODE),A
        LD      (MODFLG),A
        LD      (UNDOK),A
        LD      (PEND),A
        LD      HL,0
        LD      (CURIDX),HL
        LD      (TOPLIN),HL
        CALL    REFRESH
        LD      A,(TOOBIG)
        OR      A
        JR      Z,MAIN
        LD      DE,MSGTRUNC
        CALL    MESSAGE
MAIN:   CALL    READKEY
        LD      B,A
        LD      A,(MODE)
        OR      A
        LD      A,B
        JP      NZ,INSMOD
        JP      NORMOD

; Input uses BIOS rather than echoing BDOS 1; this works on physical
; console and on Zapple-II's redirected NETCCP console.
INKEYS: LD      HL,(0001H)    ; WBOOT entry of BIOS jump table
        LD      DE,3
        ADD     HL,DE
        LD      (KEYST+1),HL
        ADD     HL,DE
        LD      (KEYIN+1),HL
        RET
KEYST:  CALL    0000H
        RET
KEYIN:  CALL    0000H
        AND     07FH
        RET
READKEY:
        CALL    KEYIN
        CP      27
        RET     NZ
        LD      A,(TERM)
        OR      A
        LD      A,27
        RET     Z
        ; A bare ESC must be distinguishable from VT100 cursor sequences.
        LD      BC,7500
RKWAIT: PUSH    BC
        CALL    KEYST
        POP     BC
        OR      A
        JR      NZ,RKSEQ
        DEC     BC
        LD      A,B
        OR      C
        JR      NZ,RKWAIT
        LD      A,27
        RET
RKSEQ:  CALL    KEYIN
        CP      '['
        JR      Z,RKFIN
        CP      'O'
        JR      Z,RKFIN
        LD      A,27
        RET
RKFIN:  CALL    KEYIN
        CP      'A'
        JR      Z,RKUP
        CP      'B'
        JR      Z,RKDN
        CP      'C'
        JR      Z,RKRT
        CP      'D'
        JR      Z,RKLT
        ; Ignore unsupported CSI sequence (up to its final character).
        LD      A,0
        RET
RKUP:   LD      A,0BH
        RET
RKDN:   LD      A,0AH
        RET
RKRT:   LD      A,15H
        RET
RKLT:   LD      A,08H
        RET

; BDOS output. A character -> CPUT. DE '$' string -> PRT.
CPUT:   PUSH    HL
        PUSH    BC
        PUSH    DE
        LD      E,A
        LD      C,2
        CALL    BDOS
        POP     DE
        POP     BC
        POP     HL
        RET
PRT:    PUSH    HL
        PUSH    BC
        PUSH    DE
        LD      C,9
        CALL    BDOS
        POP     DE
        POP     BC
        POP     HL
        RET
BELL:   LD      A,7
        JP      CPUT

; Position 0-based B=row, C=column. Both terminals are 80x24.
ATPOS:  PUSH    AF
        PUSH    BC
        LD      A,(TERM)
        OR      A
        JR      NZ,ATVT
        LD      A,27
        CALL    CPUT
        LD      A,'='
        CALL    CPUT
        LD      A,B
        ADD     A,32
        CALL    CPUT
        LD      A,C
        ADD     A,32
        CALL    CPUT
        JR      ATEND
ATVT:   LD      A,27
        CALL    CPUT
        LD      A,'['
        CALL    CPUT
        LD      A,B
        INC     A
        CALL    DECOUT
        LD      A,3BH
        CALL    CPUT
        LD      A,C
        INC     A
        CALL    DECOUT
        LD      A,'H'
        CALL    CPUT
ATEND:  POP     BC
        POP     AF
        RET
; A=1..99, write decimal digits.
DECOUT: PUSH    BC
        LD      B,0
DCLOOP: CP      10
        JR      C,DCLAST
        SUB     10
        INC     B
        JR      DCLOOP
DCLAST: LD      C,A
        LD      A,B
        OR      A
        JR      Z,DCDIG
        ADD     A,'0'
        CALL    CPUT
DCDIG:  LD      A,C
        ADD     A,'0'
        CALL    CPUT
        POP     BC
        RET
CLRSCR: LD      A,(TERM)
        OR      A
        JR      Z,CLRSOR
        LD      DE,VTCLR
        JP      PRT
CLRSOR: LD      DE,SOCLR
        JP      PRT

; Offset-based text helpers. The range is [0,TEXLEN].
; CMPEND compares HL with TEXLEN; carry if HL is before EOF, Z if equal.
CMPEND: PUSH    HL
        LD      DE,(TEXLEN)
        OR      A
        SBC     HL,DE
        POP     HL
        RET
; GETBYTE reads TXTBUF[HL] without changing HL or DE.
GETBYTE:
        PUSH    HL
        PUSH    DE
        LD      DE,TXTBUF
        ADD     HL,DE
        LD      A,(HL)
        POP     DE
        POP     HL
        RET
LINEBEG:
LBLOOP: LD      A,H
        OR      L
        RET     Z
        DEC     HL
        CALL    GETBYTE
        CP      10
        JR      NZ,LBLOOP
        INC     HL
        RET
LINEEND:
LELOOP: CALL    CMPEND
        RET     NC
        CALL    GETBYTE
        CP      10
        RET     Z
        INC     HL
        JR      LELOOP
; CALCPOS derives logical line and column of CURIDX.
CALCPOS:
        LD      HL,0
        LD      (ROWNUM),HL
        XOR     A
        LD      (COLNUM),A
        LD      HL,TXTBUF
        LD      BC,(CURIDX)
CPLOOP: LD      A,B
        OR      C
        RET     Z
        LD      A,(HL)
        CP      10
        JR      NZ,CPCOL
        PUSH    HL
        LD      HL,(ROWNUM)
        INC     HL
        LD      (ROWNUM),HL
        POP     HL
        XOR     A
        LD      (COLNUM),A
        JR      CPNEXT
CPCOL:  LD      A,(COLNUM)
        CP      79
        JR      NC,CPNEXT
        INC     A
        LD      (COLNUM),A
CPNEXT: INC     HL
        DEC     BC
        JR      CPLOOP
; ENSURE: A=1 if viewport changed, else A=0. Uses ROWNUM.
ENSURE: CALL    CALCPOS
        LD      HL,(ROWNUM)
        LD      DE,(TOPLIN)
        OR      A
        SBC     HL,DE
        JR      C,ENABOV
        LD      A,H
        OR      A
        JR      NZ,ENBELO
        LD      A,L
        CP      ROWS
        JR      NC,ENBELO
        XOR     A
        RET
ENABOV: LD      HL,(ROWNUM)
        LD      DE,3
        OR      A
        SBC     HL,DE
        JR      NC,ENASET
        LD      HL,0
ENASET: LD      (TOPLIN),HL
        LD      A,1
        RET
ENBELO: LD      HL,(ROWNUM)
        LD      DE,19
        OR      A
        SBC     HL,DE
        LD      (TOPLIN),HL
        LD      A,1
        RET
; Screen rendering. Refresh fully on scrolling/newline changes, but
; on ordinary cursor movement move only the cursor. Editing a line
; redraws just that line, not all 23 lines.
REFRESH:
        CALL    ENSURE
        JP      FULLSCR
REFCUR: LD      HL,(TOPLIN)
        LD      (OLDTOP),HL
        CALL    ENSURE
        OR      A
        JP      Z,DRAWCUR
        CALL    FASTSCR
        JP      C,FULLSCR
        JP      DRAWCUR
REFLINE:
        CALL    ENSURE
        OR      A
        JP      NZ,FULLSCR
        CALL    RENDERL
        JP      DRAWCUR
FULLSCR:
        CALL    CLRSCR
        ; Find the first byte of TOPLIN.
        LD      HL,0
        LD      BC,(TOPLIN)
FSFIND: LD      A,B
        OR      C
        JR      Z,FSSTART
        CALL    CMPEND
        JR      NC,FSSTART
        CALL    GETBYTE
        INC     HL
        CP      10
        JR      NZ,FSFIND
        DEC     BC
        JR      FSFIND
FSSTART:
        LD      (DRAWP),HL
        XOR     A
        LD      (EXHAUS),A
        LD      (DRAWROW),A
FSLP:   CALL    RENDER1
        LD      A,(DRAWROW)
        INC     A
        LD      (DRAWROW),A
        CP      ROWS
        JR      C,FSLP
        CALL    STATUS
        JP      DRAWCUR
; VT100 fast scroll: ESC D (index) / ESC M (reverse index) in
; a temporary 1..23 scroll region. Status line 24 is left intact.
; Falls back to full repaint for jumps larger than four lines.
FASTSCR:
        LD      HL,(TOPLIN)
        LD      DE,(OLDTOP)
        OR      A
        SBC     HL,DE
        LD      A,H
        OR      A
        JR      Z,FSFWD2
        LD      HL,(OLDTOP)
        LD      DE,(TOPLIN)
        OR      A
        SBC     HL,DE
        LD      A,H
        OR      A
        JP      NZ,FSBAD
        LD      A,L
        OR      A
        JP      Z,FSBAD
        CP      5
        JP      NC,FSBAD
        LD      (SHCNT),A
        LD      A,1
        LD      (SHDIR),A
        JR      FSSET
FSFWD2:LD      A,L
        OR      A
        JP      Z,FSBAD
        CP      5
        JP      NC,FSBAD
        LD      (SHCNT),A
        XOR     A
        LD      (SHDIR),A
FSSET:  LD      A,(TERM)
        OR      A
        JR      NZ,FSVT
        LD      A,(SHDIR)
        OR      A
        JP      NZ,FSBAD       ; Soroc reverse scroll falls back
        LD      B,23          ; LF at bottom scrolls entire screen
        LD      C,0
        CALL    ATPOS
        LD      A,(SHCNT)
        LD      B,A
FSSOR:  PUSH    BC
        LD      A,10
        CALL    CPUT
        POP     BC
        DJNZ    FSSOR
        JR      FSPOST
FSVT:   LD      DE,VTREG
        CALL    PRT
        LD      A,(SHDIR)
        OR      A
        JR      NZ,FSUP2
        LD      B,22
        JR      FSPOS
FSUP2:  LD      B,0
FSPOS:  LD      C,0
        CALL    ATPOS
        LD      A,(SHCNT)
        LD      B,A
FSROLL: PUSH    BC
        LD      A,27
        CALL    CPUT
        LD      A,(SHDIR)
        OR      A
        LD      A,'D'           ; VT index, screen contents move up
        JR      Z,FSRCHAR
        LD      A,'M'           ; reverse index, contents move down
FSRCHAR:CALL    CPUT
        POP     BC
        DJNZ    FSROLL
        LD      DE,VTREST
        CALL    PRT
FSPOST: ; Paint exposed rows with the normal line renderer.
        LD      A,(SHDIR)
        OR      A
        JR      NZ,FSBEGIN
        LD      A,23
        LD      B,A
        LD      A,(SHCNT)
        LD      C,A
        LD      A,B
        SUB     C
        LD      (DRAWROW),A
        JR      FSFIND2
FSBEGIN:XOR     A
        LD      (DRAWROW),A
FSFIND2:
        LD      HL,(TOPLIN)
        LD      A,(DRAWROW)
        LD      E,A
        LD      D,0
        ADD     HL,DE
        LD      BC,0
        ADD     HL,BC
        LD      (SKIPLN),HL
        LD      HL,0
        LD      BC,(SKIPLN)
FSSEEK: LD      A,B
        OR      C
        JR      Z,FSREADY
        CALL    CMPEND
        JR      NC,FSREADY
        CALL    GETBYTE
        INC     HL
        CP      10
        JR      NZ,FSSEEK
        DEC     BC
        JR      FSSEEK
FSREADY:LD      (DRAWP),HL
        XOR     A
        LD      (EXHAUS),A
FSRPAINT:
        LD      A,(DRAWROW)
        LD      B,A
        LD      C,0
        CALL    ATPOS
        LD      DE,BLANKS
        CALL    PRT
        CALL    RENDER1
        LD      A,(DRAWROW)
        INC     A
        LD      (DRAWROW),A
        LD      B,A
        LD      A,(SHDIR)
        OR      A
        JR      NZ,FSRUP
        LD      A,B
        CP      23
        JR      C,FSRPAINT
        JR      FSOK
FSRUP:  LD      A,(SHCNT)
        CP      B
        JR      NZ,FSRPAINT
FSOK:   LD      A,(TERM)
        OR      A
        JR      NZ,FSVTOK
        CALL    STATUS        ; Soroc scrolled the status row away
FSVTOK: OR      A             ; clear carry
        RET
FSBAD:  SCF
        RET

; RENDER1 displays the next logical line, with draw pointer advancing.
RENDER1:
        LD      A,(DRAWROW)
        LD      B,A
        LD      C,0
        CALL    ATPOS
        LD      HL,(DRAWP)
        CALL    CMPEND
        JR      C,R1TEXT
        LD      A,(EXHAUS)
        OR      A
        JR      Z,R1EMPTY
        LD      A,'~'
        CALL    CPUT
        RET
R1EMPTY:
        LD      A,1
        LD      (EXHAUS),A
        RET
R1TEXT:
        XOR     A
        LD      (EXHAUS),A
        LD      B,0
R1LP:   CALL    CMPEND
        JR      NC,R1DONE
        CALL    GETBYTE
        CP      10
        JR      Z,R1NL
        LD      C,A
        LD      A,B
        CP      79
        JR      NC,R1SKIP
        LD      A,C
        CALL    DISPCHR
R1SKIP: LD      A,B
        CP      79
        JR      NC,R1STEP
        INC     B
R1STEP: INC     HL
        JR      R1LP
R1NL:   INC     HL
R1DONE: LD      (DRAWP),HL
        RET
; For control bytes render a single placeholder, do not mangle file.
DISPCHR:
        CP      32
        JR      C,DCQ
        CP      127
        JR      Z,DCQ
        JP      CPUT
DCQ:    LD      A,'.'
        JP      CPUT
; RENDERL: clear and repaint only the cursor's visible text line.
RENDERL:
        CALL    GETSCRR
        LD      B,A
        LD      C,0
        CALL    ATPOS
        LD      DE,BLANKS
        CALL    PRT
        CALL    GETSCRR
        LD      B,A
        LD      C,0
        CALL    ATPOS
        LD      HL,(CURIDX)
        CALL    LINEBEG
        LD      (DRAWP),HL
        LD      A,0
        LD      (EXHAUS),A
        LD      A,255
        LD      (DRAWROW),A       ; suppress possible '~' at empty EOF
        ; print directly using the same R1 scanning logic
        LD      HL,(DRAWP)
        LD      B,0
RLLOOP: CALL    CMPEND
        RET     NC
        CALL    GETBYTE
        CP      10
        RET     Z
        LD      C,A
        LD      A,B
        CP      79
        JR      NC,RLSTEP
        LD      A,C
        CALL    DISPCHR
RLSTEP: LD      A,B
        CP      79
        JR      NC,RLNEXT
        INC     B
RLNEXT: INC     HL
        JR      RLLOOP
GETSCRR:
        LD      HL,(ROWNUM)
        LD      DE,(TOPLIN)
        OR      A
        SBC     HL,DE
        LD      A,L
        RET
DRAWCUR:
        CALL    GETSCRR
        LD      B,A
        LD      A,(COLNUM)
        LD      C,A
        JP      ATPOS
STATUS: LD      B,23
        LD      C,0
        CALL    ATPOS
        LD      DE,BLANKS
        CALL    PRT
        LD      B,23
        LD      C,0
        CALL    ATPOS
        LD      DE,STNAME
        CALL    PRT
        CALL    PRFNAME
        LD      A,(TOOBIG)
        OR      A
        JR      Z,STSAFE
        LD      DE,STTRUNC
        CALL    PRT
STSAFE: LD      A,(MODFLG)
        OR      A
        JR      Z,STMODE
        LD      DE,STMOD
        CALL    PRT
STMODE: LD      A,(MODE)
        OR      A
        JR      Z,STNORM
        LD      DE,STINS
        JP      PRT
STNORM: LD      DE,STNOR
        JP      PRT
PRFNAME:
        LD      A,(HASFILE)
        OR      A
        JR      NZ,PFSET
        LD      DE,NONAME
        JP      PRT
PFSET:  LD      A,(FCB)
        OR      A
        JR      Z,PFBAS
        ADD     A,40H
        CALL    CPUT
        LD      A,':'
        CALL    CPUT
PFBAS:  LD      HL,FCB+1
        LD      B,8
PFLOOP: LD      A,(HL)
        CP      ' '
        JR      Z,PFSKIP
        CALL    CPUT
PFSKIP: INC     HL
        DJNZ    PFLOOP
        LD      A,(FCB+9)
        CP      ' '
        RET     Z
        LD      A,'.'
        CALL    CPUT
        LD      HL,FCB+9
        LD      B,3
        JR      PFEXT
PFEXT:  LD      A,(HL)
        CP      ' '
        JR      Z,PFXSK
        CALL    CPUT
PFXSK:  INC     HL
        DJNZ    PFEXT
        RET
MESSAGE:
        ; DE points to '$'-terminated status/error string.
        PUSH    DE
        LD      B,23
        LD      C,0
        CALL    ATPOS
        LD      DE,BLANKS
        CALL    PRT
        LD      B,23
        LD      C,0
        CALL    ATPOS
        POP     DE
        CALL    PRT
        JP      DRAWCUR

NCURSOR:
        CALL    REFCUR
        JP      MAIN
NREDRAW:
        CALL    REFRESH
        JP      MAIN
NLINE:
        CALL    REFLINE
        JP      MAIN

; vi-style normal mode, plus Apple II and VT100 arrow keys.
NORMOD:
        LD      B,A
        LD      A,(PEND)
        OR      A
        JR      Z,NMDIR
        LD      C,A
        XOR     A
        LD      (PEND),A
        LD      A,B
        CP      C
        JR      NZ,NMDIR
        CP      'd'
        JP      Z,DEL_LINE
        CP      'y'
        JR      Z,NMYY
        CP      'g'
        JP      Z,GOFIRST
        JR      NMDIR
NMYY:   CALL    YANKLINE
        JP      MAIN
NMDIR:  LD      A,B
  CP      'h'
        JP      Z,MOVELEFT
        CP      08H
        JP      Z,MOVELEFT
        CP      'l'
        JP      Z,MOVERIG
        CP      15H
        JP      Z,MOVERIG
        CP      'j'
        JP      Z,MOVEDN
        CP      0AH
        JP      Z,MOVEDN
        CP      0DH           ; Return
        JP      Z,MOVEDN
        CP      06H           ; ^F next page
        JP      Z,PAGEDN
        CP      02H           ; ^B previous page
        JP      Z,PAGEUP
        CP      '-'
        JP      Z,MOVEUP
        CP      'k'
        JP      Z,MOVEUP
        CP      0BH
        JP      Z,MOVEUP
        CP      '0'
        JP      Z,GOLBEG
        CP      '$'
        JP      Z,GOLEND
        CP      'G'
        JP      Z,GOLAST
        CP      'g'
        JR      Z,NMG
        CP      'd'
        JR      Z,NMD
        CP      'y'
        JR      Z,NMY
        CP      'x'
        JP      Z,DEL_CHAR
        CP      'p'
        JP      Z,PASTELN
        CP      'u'
        JP      Z,UNDOIT
        CP      'i'
        JP      Z,ENTERINS
        CP      'a'
        JP      Z,APPENDC
        CP      'I'
        JP      Z,INSBEG
        CP      'A'
        JP      Z,INSEND
        CP      'o'
        JP      Z,OPENLOW
        CP      'O'
        JP      Z,OPENUP
        CP      ':'
        JP      Z,COLON
        CP      '/'
        JP      Z,SRCHFW
        CP      '?'
        JP      Z,SRCHBW
        CP      'n'
        JP      Z,SRCHNX
        CP      'N'
        JP      Z,SRCHPR
        CP      12              ; ^L
        JP      Z,REFRESH
        JP      MAIN
NMG:    LD      A,'g'
        JR      NMPEND
NMD:    LD      A,'d'
        JR      NMPEND
NMY:    LD      A,'y'
NMPEND: LD      (PEND),A
        JP      MAIN
MOVELEFT:
        LD      HL,(CURIDX)
        PUSH    HL
        CALL    LINEBEG
        EX      DE,HL
        POP     HL
        OR      A
        SBC     HL,DE
        LD      A,H
        OR      L
        JP      Z,MAIN
        LD      HL,(CURIDX)
        DEC     HL
        LD      (CURIDX),HL
        JP      NCURSOR
MOVERIG:
        LD      HL,(CURIDX)
        CALL    CMPEND
        JP      NC,MAIN
        CALL    GETBYTE
        CP      10
        JP      Z,MAIN
        INC     HL
        LD      (CURIDX),HL
        JP      NCURSOR
GOLBEG: LD      HL,(CURIDX)
        CALL    LINEBEG
        LD      (CURIDX),HL
        JP      NCURSOR
GOLEND: LD      HL,(CURIDX)
        CALL    LINEEND
        LD      (CURIDX),HL
        JP      NCURSOR
GOFIRST:
        LD      HL,0
        LD      (CURIDX),HL
        JP      NCURSOR
GOLAST:
        LD      HL,(TEXLEN)
        CALL    LINEBEG
        LD      (CURIDX),HL
        JP      NCURSOR
; Vertical move retains target column, truncating at target line end.
MOVEDN: CALL    DOWNONE
        JP      NCURSOR
DOWNONE:CALL    CALCPOS
        LD      HL,(CURIDX)
        CALL    LINEEND
        CALL    CMPEND
        RET     NC
        INC     HL
        CALL    MATCHCOL
        LD      (CURIDX),HL
        RET
MOVEUP: CALL    UPONE
        JP      NCURSOR
UPONE:  CALL    CALCPOS
        LD      HL,(CURIDX)
        CALL    LINEBEG
        LD      A,H
        OR      L
        RET     Z
        DEC     HL
        CALL    LINEBEG
        CALL    MATCHCOL
        LD      (CURIDX),HL
        RET
PAGEDN: LD      B,22
PGDLOOP:PUSH    BC
        CALL    DOWNONE
        POP     BC
        DJNZ    PGDLOOP
        JP      NCURSOR
PAGEUP: LD      B,22
PGULOOP:PUSH    BC
        CALL    UPONE
        POP     BC
        DJNZ    PGULOOP
        JP      NCURSOR
MATCHCOL:
        LD      A,(COLNUM)
        LD      B,A
MCLOOP: LD      A,B
        OR      A
        RET     Z
        CALL    CMPEND
        RET     NC
        CALL    GETBYTE
        CP      10
        RET     Z
        INC     HL
        DJNZ    MCLOOP
        RET

; One-level undo, snapshot once per command or insert-mode session.
SAVEUNDO:
        LD      HL,(TEXLEN)
        LD      (UNDOLEN),HL
        LD      HL,(CURIDX)
        LD      (UNDOIDX),HL
        LD      BC,(TEXLEN)
        LD      A,B
        OR      C
        JR      Z,SUEMPTY
        LD      HL,TXTBUF
        LD      DE,UNDBUF
        LDIR
SUEMPTY:
        LD      A,1
        LD      (UNDOK),A
        RET
UNDOIT: LD      A,(UNDOK)
        OR      A
        JP      Z,MAIN
        LD      BC,(UNDOLEN)
        LD      A,B
        OR      C
        JR      Z,UNEMPTY
        LD      HL,UNDBUF
        LD      DE,TXTBUF
        LDIR
UNEMPTY:
        LD      HL,(UNDOLEN)
        LD      (TEXLEN),HL
        LD      HL,(UNDOIDX)
        LD      (CURIDX),HL
        LD      A,1
        LD      (MODFLG),A
        XOR     A
        LD      (UNDOK),A
        JP      NREDRAW
; Insert byte A at CURIDX. Carry set on overflow; preserves no registers.
INSBYTE:
        LD      (INCHAR),A
        LD      HL,(TEXLEN)
        LD      DE,MAXTXT
        OR      A
        SBC     HL,DE
        JR      C,IBROOM
        SCF
        RET
IBROOM: LD      HL,(TEXLEN)
        LD      DE,(CURIDX)
        OR      A
        SBC     HL,DE
        LD      B,H             ; BC = old length - cursor
        LD      C,L
        LD      HL,TXTBUF
        LD      DE,(TEXLEN)
        ADD     HL,DE           ; one past last byte
        LD      D,H
        LD      E,L             ; DE = last destination address
        DEC     HL              ; HL = last source address
        LD      A,B
        OR      C
        JR      Z,IBPLACE
        LDDR                    ; move tail backwards by one byte
IBPLACE:
        LD      HL,(CURIDX)
        LD      DE,TXTBUF
        ADD     HL,DE
        LD      A,(INCHAR)
        LD      (HL),A
        LD      HL,(TEXLEN)
        INC     HL
        LD      (TEXLEN),HL
        LD      HL,(CURIDX)
        INC     HL
        LD      (CURIDX),HL
        LD      A,1
        LD      (MODFLG),A
        OR      A               ; clear carry
        RET
; Delete byte at CURIDX; carry set if at EOF.
DELBYTE:
        LD      HL,(CURIDX)
        CALL    CMPEND
        JR      C,DBVALID
        SCF
        RET
DBVALID:
        LD      HL,(TEXLEN)
        LD      DE,(CURIDX)
        OR      A
        SBC     HL,DE
        DEC     HL
        LD      B,H
        LD      C,L
        LD      HL,(CURIDX)
        LD      DE,TXTBUF
        ADD     HL,DE          ; destination
        LD      D,H
        LD      E,L
        INC     HL              ; source
        LD      A,B
        OR      C
        JR      Z,DBNOMOV
        LDIR
DBNOMOV:
        LD      HL,(TEXLEN)
        DEC     HL
        LD      (TEXLEN),HL
        LD      A,1
        LD      (MODFLG),A
        OR      A
        RET
; Insert mode: ^[ exits, CR inserts newline, DEL/BS deletes left.
ENTERINS:
        CALL    SAVEUNDO
        CALL    ENTERI2
        JP      MAIN
ENTERI2:
        LD      A,1
        LD      (MODE),A
        CALL    STATUS
        CALL    REFCUR
        RET
APPENDC:
        LD      HL,(CURIDX)
        CALL    CMPEND
        JR      NC,APPNOW
        CALL    GETBYTE
        CP      10
        JR      Z,APPNOW
        INC     HL
        LD      (CURIDX),HL
APPNOW: JP      ENTERINS
INSBEG: LD      HL,(CURIDX)
        CALL    LINEBEG
        LD      (CURIDX),HL
        JP      ENTERINS
INSEND: LD      HL,(CURIDX)
        CALL    LINEEND
        LD      (CURIDX),HL
        JP      ENTERINS
INSMOD:
        CP      27
        JR      Z,INSEXIT
        CP      08H
        JR      Z,INSBACK
        CP      127
        JR      Z,INSBACK
        CP      13
        JR      Z,INSNEW
        CP      10
        JR      Z,INSNEW
        CP      32
        JP      C,MAIN
        CP      127
        JP      NC,MAIN
        LD      (INCHAR),A
        CALL    INSBYTE
        JR      C,INSFULL
        CALL    REFLINE
        JP      MAIN
INSNEW: LD      A,10
        CALL    INSBYTE
        JR      C,INSFULL
        CALL    REFRESH
        JP      MAIN
INSBACK:
        LD      HL,(CURIDX)
        LD      A,H
        OR      L
        JP      Z,MAIN
        DEC     HL
        LD      (CURIDX),HL
        CALL    GETBYTE
        LD      (DIDNL),A
        CALL    DELBYTE
        LD      A,(DIDNL)
        CP      10
        JR      Z,IBFULL
        CALL    REFLINE
        JP      MAIN
IBFULL: CALL    REFRESH
        JP      MAIN
INSFULL: CALL    BELL
        JP      MAIN
INSEXIT:
        XOR     A
        LD      (MODE),A
        CALL    STATUS
        JP      NCURSOR
; Delete current character, but never accidentally join lines with x.
DEL_CHAR:
        LD      HL,(CURIDX)
        CALL    CMPEND
        JP      NC,MAIN
        CALL    GETBYTE
        CP      10
        JP      Z,MAIN
        CALL    SAVEUNDO
        CALL    DELBYTE
        CALL    REFLINE
        JP      MAIN
; dd, yy and p use an independent single-line yank register (max 255).
; Cursor always remains within the text buffer.
YANKLINE:
        LD      HL,(CURIDX)
        CALL    LINEBEG
        LD      (YBEGIN),HL
        CALL    LINEEND
        CALL    CMPEND
        JR      NC,YLEND
        INC     HL              ; include newline
YLEND:  LD      DE,(YBEGIN)
        OR      A
        SBC     HL,DE
        LD      A,H
        OR      A
        JR      NZ,YLTOO
        LD      A,L
        LD      (YANKLEN),A
        OR      A
        JR      Z,YLEMPTY
        LD      B,0
        LD      C,A
        LD      HL,(YBEGIN)
        LD      DE,TXTBUF
        ADD     HL,DE
        LD      DE,YANKBUF
        LDIR
        ; A line without a final newline needs one in the yank register,
        ; otherwise p would concatenate it onto the following line.
        DEC     DE
        LD      A,(DE)
        CP      10
        JR      Z,YLEMPTY
        LD      A,(YANKLEN)
        CP      255
        JR      Z,YLEMPTY
        INC     DE
        LD      A,10
        LD      (DE),A
        LD      A,(YANKLEN)
        INC     A
        LD      (YANKLEN),A
YLEMPTY:
        RET
YLTOO:  LD      DE,MSGLONG
        CALL    MESSAGE
        RET
DEL_LINE:
        CALL    SAVEUNDO
        CALL    YANKLINE
        LD      HL,(CURIDX)
        CALL    LINEBEG
        LD      (CURIDX),HL
        LD      (YBEGIN),HL
        CALL    LINEEND
        CALL    CMPEND
        JR      NC,DLEND
        INC     HL
DLEND:  LD      (DELEND),HL
        LD      DE,(YBEGIN)
        OR      A
        SBC     HL,DE
        LD      (DELCNT),HL
        LD      HL,(TEXLEN)
        LD      DE,(DELEND)
        OR      A
        SBC     HL,DE
        LD      B,H
        LD      C,L
        LD      HL,(DELEND)
        LD      DE,TXTBUF
        ADD     HL,DE
        LD      DE,(YBEGIN)
        PUSH    HL
        LD      HL,TXTBUF
        ADD     HL,DE
        EX      DE,HL
        POP     HL
        LD      A,B
        OR      C
        JR      Z,DLNOMOV
        LDIR
DLNOMOV:
        LD      HL,(TEXLEN)
        LD      DE,(DELCNT)
        OR      A
        SBC     HL,DE
        LD      (TEXLEN),HL
        LD      HL,(CURIDX)
        CALL    CMPEND
        JR      C,DLDONE
        LD      HL,(TEXLEN)
        CALL    LINEBEG
        LD      (CURIDX),HL
DLDONE: LD      A,1
        LD      (MODFLG),A
        CALL    REFRESH
        JP      MAIN
PASTELN:
        LD      A,(YANKLEN)
        OR      A
        JP      Z,MAIN
        CALL    SAVEUNDO
        LD      HL,(CURIDX)
        CALL    LINEEND
        CALL    CMPEND
        JR      NC,PLATEND
        INC     HL
PLATEND:
        LD      (CURIDX),HL
        CALL    CMPEND
        JR      C,PLSTART
        ; Last line lacks LF: add separator before putting next line.
        LD      A,H
        OR      L
        JR      Z,PLSTART
        DEC     HL
        CALL    GETBYTE
        CP      10
        JR      Z,PLSTART
        LD      A,10
        CALL    INSBYTE
        JP      C,PLERR
PLSTART:
        LD      A,(YANKLEN)
        LD      B,A
        LD      HL,YANKBUF
PLLOOP: PUSH    BC
        PUSH    HL
        LD      A,(HL)
        CALL    INSBYTE
        POP     HL
        POP     BC
        JR      C,PLERR
        INC     HL
        DJNZ    PLLOOP
        CALL    REFRESH
        JP      MAIN
PLERR:  CALL    BELL
        CALL    REFRESH
        JP      MAIN
; o/O insert an empty line and switch to insert mode.
OPENLOW:
        CALL    SAVEUNDO
        LD      HL,(CURIDX)
        CALL    LINEEND
        CALL    CMPEND
        JR      NC,OLNEW
        INC     HL
        LD      (CURIDX),HL
        LD      A,10
        CALL    INSBYTE
        JR      C,OLFAIL
        LD      HL,(CURIDX)
        DEC     HL
        LD      (CURIDX),HL
        JR      OLENTER
OLNEW:  LD      (CURIDX),HL
        LD      A,10
        CALL    INSBYTE
        JR      C,OLFAIL
OLENTER:
        CALL    ENTERI2
        CALL    REFRESH
        JP      MAIN
OLFAIL: CALL    BELL
        JP      MAIN
OPENUP: CALL    SAVEUNDO
        LD      HL,(CURIDX)
        CALL    LINEBEG
        LD      (CURIDX),HL
        LD      A,10
        CALL    INSBYTE
        JR      C,OLFAIL
        LD      HL,(CURIDX)
        DEC     HL
        LD      (CURIDX),HL
        JR      OLENTER

; Colon command line on screen row 24; accepts w, q, q!, wq, h.
COLON:  LD      A,':'
        CALL    PROMPT
        JP      C,COLCANC
        JP      COLEXEC
PROMPT: LD      (PRCHAR),A
        LD      B,23
        LD      C,0
        CALL    ATPOS
        LD      DE,BLANKS
        CALL    PRT
        LD      B,23
        LD      C,0
        CALL    ATPOS
        LD      A,(PRCHAR)
        CALL    CPUT
        LD      HL,CMDTXT
        LD      (CMDPTR),HL
        XOR     A
        LD      (CMDLEN),A
COLIN:  CALL    READKEY
        CP      27
        JP      Z,PCANCEL
        CP      13
        JP      Z,PDONE
        CP      10
        JP      Z,PDONE
        CP      08H
        JR      Z,COLBACK
        CP      127
        JR      Z,COLBACK
        CP      32
        JR      C,COLIN
        LD      B,A
        LD      A,(CMDLEN)
        CP      78
        JR      NC,COLIN
        LD      HL,(CMDPTR)
        LD      (HL),B
        INC     HL
        LD      (CMDPTR),HL
        LD      A,(CMDLEN)
        INC     A
        LD      (CMDLEN),A
        LD      A,B
        CALL    CPUT
        JR      COLIN
COLBACK:
        LD      A,(CMDLEN)
        OR      A
        JR      Z,COLIN
        DEC     A
        LD      (CMDLEN),A
        LD      HL,(CMDPTR)
        DEC     HL
        LD      (CMDPTR),HL
        LD      A,8
        CALL    CPUT
        LD      A,' '
        CALL    CPUT
        LD      A,8
        CALL    CPUT
        JR      COLIN
PCANCEL:
        SCF
        RET
PDONE:  LD      HL,(CMDPTR)
        LD      (HL),0
        OR      A
        RET
COLEXEC:
        LD      HL,CMDTXT
        LD      A,(HL)
        CP      '%'
        JP      Z,SUBCMD
        CP      '.'
        JP      Z,ADDRESS
        CP      '$'
        JP      Z,ADDRESS
        CP      '0'
        JR      C,COLETTER
        CP      3AH
        JP      C,ADDRESS
        JP      COLETTER
ADDRESS:
        LD      HL,CMDTXT
ADRSKIP:LD      A,(HL)
        CP      '0'
        JR      C,ADRLOOK
        CP      3AH
        JR      NC,ADRLOOK
        INC     HL
        JR      ADRSKIP
ADRLOOK:CP      's'
        JP      Z,SUBCMD
        CP      ','
        JP      Z,SUBCMD
        LD      HL,CMDTXT
        LD      A,(HL)
        CP      '.'
        JP      Z,SUBCMD
        CP      '$'
        JP      Z,JUMPCMD
        JP      JUMPCMD
COLETTER:
        LD      HL,CMDTXT
        LD      A,(HL)
        OR      20H
        CP      'w'
        JR      Z,COW
        CP      'q'
        JR      Z,COQ
        CP      'h'
        JR      Z,COHELP
        CP      's'
        JP      Z,SUBCMD
        JR      COLBAD
COW:    INC     HL
        LD      A,(HL)
        OR      A
        JR      Z,COWONLY
        OR      20H
        CP      'q'
        JR      NZ,COLBAD
        INC     HL
        LD      A,(HL)
        OR      A
        JR      NZ,COLBAD
        CALL    SAVEF
        JP      C,MAIN
        JP      FINISH
COWONLY:
        CALL    SAVEF
        JP      MAIN
COQ:    INC     HL
        LD      A,(HL)
        OR      A
        JR      Z,CQQ
        CP      '!'
        JR      NZ,COLBAD
        INC     HL
        LD      A,(HL)
        OR      A
        JR      NZ,COLBAD
        JP      FINISH
CQQ:    LD      A,(MODFLG)
        OR      A
        JP      Z,FINISH
        LD      DE,MSGUNSV
        CALL    MESSAGE
        JP      MAIN
COHELP: LD      DE,MSGHELP
        CALL    MESSAGE
        JP      MAIN
COLBAD: LD      DE,MSGCMD
        CALL    MESSAGE
        JP      MAIN
COLCANC:
        CALL    STATUS
        JP      NCURSOR
FINISH: CALL    CLRSCR
        LD      SP,(OLDSP)
        RET

; Default CP/M CCP FCB at 005CH. A filename is required to save.
INITFCB:
        LD      HL,FCB
        LD      DE,FCB+1
        LD      BC,35
        LD      (HL),0
        LDIR
        LD      HL,005CH
        LD      DE,FCB
        LD      BC,12
        LDIR
        LD      A,(FCB+1)
        CP      ' '
        JR      Z,IFNONE
        LD      A,1
        LD      (HASFILE),A
        RET
IFNONE: XOR     A
        LD      (HASFILE),A
        RET
ARGOPT: LD      HL,0080H
        LD      B,(HL)
        INC     HL
AOLOOP: LD      A,B
        OR      A
        RET     Z
        LD      A,(HL)
        CP      '-'
        JR      NZ,AONEXT
        INC     HL
        DEC     B
        JR      Z,AONEXT
        LD      A,(HL)
        CP      'V'
        JR      NZ,AONEXT
        LD      A,1
        LD      (TERM),A
AONEXT: INC     HL
        DJNZ    AOLOOP
        RET
; BDOS helper: C=function, DE=FCB/DMA. Return A from BDOS.
CALLBD: CALL    BDOS
        RET
; LOADF sequentially reads 128-byte records, normalizes CRLF -> LF.
; Missing input creates a new buffer. ^Z stops input; binary files unsupported.
LOADF:  LD      HL,0
        LD      (TEXLEN),HL
        LD      A,(HASFILE)
        OR      A
        RET     Z
        LD      DE,FCB
        LD      C,15
        CALL    CALLBD
        CP      0FFH
        RET     Z
        LD      DE,RECBUF
        LD      C,26
        CALL    CALLBD
LFNEXT: LD      DE,FCB
        LD      C,20
        CALL    CALLBD
        CP      1
        JR      Z,LFCLOSE       ; normal CP/M EOF
        OR      A
        JR      Z,LFDATA
        LD      A,1
        LD      (TOOBIG),A     ; read error: never overwrite partial file
        JR      LFCLOSE
LFDATA: LD      HL,RECBUF
        LD      B,128
LFREC:  LD      A,(HL)
        CP      1AH
        JR      Z,LFCLOSE
        CP      13
        JR      Z,LFCR
        CP      10
        JR      Z,LFLF
        LD      (INCHAR),A
        CALL    APPBYTE
        JR      C,LFTOOB
        XOR     A
        LD      (PREVCR),A
        JR      LFADV
LFCR:   LD      A,10
        LD      (INCHAR),A
        CALL    APPBYTE
        JR      C,LFTOOB
        LD      A,1
        LD      (PREVCR),A
        JR      LFADV
LFLF:   LD      A,(PREVCR)
        OR      A
        JR      NZ,LFKEEP
        LD      A,10
        LD      (INCHAR),A
        CALL    APPBYTE
        JR      C,LFTOOB
LFKEEP: XOR     A
        LD      (PREVCR),A
LFADV:  INC     HL
        DJNZ    LFREC
        JR      LFNEXT
LFTOOB: LD      A,1
        LD      (TOOBIG),A
LFCLOSE:
        LD      DE,FCB
        LD      C,16
        CALL    CALLBD
        RET
; Append INCHAR to EOF, preserving HL and BC (used by record parser).
APPBYTE:
        PUSH    HL
        PUSH    DE
        PUSH    BC
        LD      HL,(TEXLEN)
        LD      DE,MAXTXT
        OR      A
        SBC     HL,DE
        JR      NC,ABFULL
        LD      HL,TXTBUF
        LD      DE,(TEXLEN)
        ADD     HL,DE
        LD      A,(INCHAR)
        LD      (HL),A
        LD      HL,(TEXLEN)
        INC     HL
        LD      (TEXLEN),HL
        OR      A
        JR      ABEND
ABFULL: SCF
ABEND: POP     BC
        POP     DE
        POP     HL
        RET
; SAVEF writes a temp <name>.VIT, then replaces original.
; A failed write/rename leaves the temp file for manual recovery.
; A successful replacement leaves a <name>.BAK backup.
; Carry clear success; carry set on failure.
SAVEF:  LD      A,(TOOBIG)
        OR      A
        JR      Z,SFOKLD
        LD      DE,MSGTRUNC
        CALL    MESSAGE
        SCF
        RET
SFOKLD: LD      A,(HASFILE)
        OR      A
        JR      NZ,SFNAME
        LD      DE,MSGNOFL
        CALL    MESSAGE
        SCF
        RET
SFNAME: LD      HL,FCB
        LD      DE,TMPFCB
        LD      BC,36
        LDIR
        LD      A,'V'
        LD      (TMPFCB+9),A
        LD      A,'I'
        LD      (TMPFCB+10),A
        LD      A,'T'
        LD      (TMPFCB+11),A
        ; Refuse to overwrite an existing recoverable temp file.
        LD      DE,TMPFCB
        LD      C,15
        CALL    CALLBD
        CP      0FFH
        JR      Z,SFMAKE
        LD      DE,TMPFCB
        LD      C,16
        CALL    CALLBD
        LD      DE,MSGTEMP
        CALL    MESSAGE
        SCF
        RET
SFMAKE: LD      DE,TMPFCB
        LD      C,22
        CALL    CALLBD
        CP      0FFH
        JR      NZ,SFWRITE
        JP      SFERROR
SFWRITE:
        LD      DE,RECBUF
        LD      C,26
        CALL    CALLBD
        LD      HL,0
        LD      (FILEIDX),HL
        XOR     A
        LD      (OUTCNT),A
        LD      (FAILWR),A
SFWLOOP:
        LD      HL,(FILEIDX)
        LD      DE,(TEXLEN)
        OR      A
        SBC     HL,DE
        JR      NC,SFWEND
        LD      HL,(FILEIDX)
        LD      DE,TXTBUF
        ADD     HL,DE
        LD      A,(HL)
        CP      10
        JR      NZ,SFWCHAR
        LD      A,13
        CALL    OPUT
        JP      C,SFWFAIL
        LD      A,10
SFWCHAR:
        CALL    OPUT
        JP      C,SFWFAIL
        LD      HL,(FILEIDX)
        INC     HL
        LD      (FILEIDX),HL
        JR      SFWLOOP
SFWEND: LD      A,1AH
        CALL    OPUT
        JP      C,SFWFAIL
        LD      A,(OUTCNT)
        OR      A
        JR      Z,SFWCLOSE
SFWPAD: LD      A,1AH
        CALL    OPUT
        JP      C,SFWFAIL
        LD      A,(OUTCNT)
        OR      A
        JR      NZ,SFWPAD
SFWCLOSE:
        LD      DE,TMPFCB
        LD      C,16
        CALL    CALLBD
        CP      0FFH
        JP      Z,SFERROR
        ; Rename old file -> .BAK, after removing prior backup.
        LD      HL,FCB
        LD      DE,BAKFCB
        LD      BC,36
        LDIR
        LD      A,'B'
        LD      (BAKFCB+9),A
        LD      A,'A'
        LD      (BAKFCB+10),A
        LD      A,'K'
        LD      (BAKFCB+11),A
        LD      DE,BAKFCB
        LD      C,19
        CALL    CALLBD
        LD      HL,FCB
        LD      DE,RENFCB
        LD      BC,16
        LDIR
        LD      HL,BAKFCB
        LD      DE,RENFCB+16
        LD      BC,12
        LDIR
        LD      DE,RENFCB
        LD      C,23
        CALL    CALLBD
        LD      (HADOLD),A     ; 0=renamed original; FF=no original
        ; Rename temp -> destination
        LD      HL,TMPFCB
        LD      DE,RENFCB
        LD      BC,16
        LDIR
        LD      HL,FCB
        LD      DE,RENFCB+16
        LD      BC,12
        LDIR
        LD      DE,RENFCB
        LD      C,23
        CALL    CALLBD
        CP      0FFH
        JR      Z,SFROLL
        XOR     A
        LD      (MODFLG),A
        LD      (UNDOK),A
        LD      DE,MSGSAVED
        CALL    MESSAGE
        OR      A
        RET
SFROLL: ; Best-effort restoration of .BAK to original name.
        LD      A,(HADOLD)
        CP      0FFH
        JP      Z,SFERROR
        LD      HL,BAKFCB
        LD      DE,RENFCB
        LD      BC,16
        LDIR
        LD      HL,FCB
        LD      DE,RENFCB+16
        LD      BC,12
        LDIR
        LD      DE,RENFCB
        LD      C,23
        CALL    CALLBD
        JP      SFERROR
SFWFAIL:
        LD      DE,TMPFCB
        LD      C,16
        CALL    CALLBD
SFERROR:
        LD      DE,MSGERROR
        CALL    MESSAGE
        SCF
        RET
; OPUT A to buffered 128-byte CP/M DMA; write on full.
; Carry set if write failed.
OPUT:   PUSH    HL
        PUSH    DE
        PUSH    BC
        LD      B,A
        LD      A,(OUTCNT)
        LD      E,A
        LD      D,0
        LD      HL,RECBUF
        ADD     HL,DE
        LD      (HL),B
        LD      A,(OUTCNT)
        INC     A
        AND     7FH
        LD      (OUTCNT),A
        JR      NZ,OPGOOD
        LD      DE,TMPFCB
        LD      C,21
        CALL    CALLBD
        OR      A
        JR      Z,OPGOOD
        SCF
        JR      OPDONE
OPGOOD: OR      A
OPDONE: POP     BC
        POP     DE
        POP     HL
        RET


; Search / and ?, with n/N repeat and file wrap.
SRCHFW: LD      A,1
        JP      SRCNEW
SRCHBW: LD      A,255
SRCNEW: LD      (SRDIR),A
        LD      A,1
        LD      (ISGOOD),A
        LD      A,(SRDIR)
        CP      1
        JP      Z,SPFWD
        LD      A,'?'
        JP      SPPROM
SPFWD:  LD      A,'/'
SPPROM: CALL    PROMPT
        JP      C,COLCANC
        LD      A,(CMDLEN)
        OR      A
        JP      Z,SRCHNX
        LD      (PATLEN),A
        LD      HL,CMDTXT
        LD      DE,PATBUF
        LD      C,A
        LD      B,0
        LDIR
SRCHNX: LD      A,(SRDIR)
        JP      SRCRUN
SRCHPR: LD      A,(SRDIR)
        NEG
SRCRUN: LD      (WORKDIR),A
        LD      A,(PATLEN)
        OR      A
        JP      Z,MAIN
        ; Scan exactly TEXLEN candidate offsets, beginning one
        ; byte beyond the cursor in the requested direction.
        LD      HL,(TEXLEN)
        LD      (SRLEFT),HL
        LD      HL,(CURIDX)
        LD      A,(WORKDIR)
        CP      1
        JR      NZ,SRINITB
        INC     HL
        JR      SRINIT2
SRINITB:
        LD      A,H
        OR      L
        JR      NZ,SRDECB
        LD      HL,(TEXLEN)
SRDECB: DEC     HL
SRINIT2:
        LD      (SRPOS),HL
SRLOOP: LD      HL,(SRLEFT)
        LD      A,H
        OR      L
        JP      Z,SRFAIL
        DEC     HL
        LD      (SRLEFT),HL
        LD      HL,(SRPOS)
        LD      DE,(TEXLEN)
        OR      A
        SBC     HL,DE
        JR      C,SRINRG
        ; Forward search can arrive at TEXLEN; wrap to zero.
        LD      HL,0
        LD      (SRPOS),HL
SRINRG:LD      HL,(SRPOS)
        LD      A,(PATLEN)
        LD      E,A
        LD      D,0
        ADD     HL,DE
        LD      DE,(TEXLEN)
        OR      A
        SBC     HL,DE
        JR      C,SRTEST
        JR      Z,SRTEST
        JP      SRSTEP
SRTEST: LD      HL,(SRPOS)
        LD      DE,TXTBUF
        ADD     HL,DE
        LD      DE,PATBUF
        LD      A,(PATLEN)
        LD      B,A
SRCMP:  LD      A,(DE)
        CP      (HL)
        JR      NZ,SRSTEP
        INC     DE
        INC     HL
        DJNZ    SRCMP
        LD      HL,(SRPOS)
        LD      (CURIDX),HL
        JP      NREDRAW
SRSTEP: LD      HL,(SRPOS)
        LD      A,(WORKDIR)
        CP      1
        JR      NZ,SRBACK
        INC     HL
        LD      (SRPOS),HL
        JP      SRLOOP
SRBACK: LD      A,H
        OR      L
        JR      NZ,SRBACK2
        LD      HL,(TEXLEN)
SRBACK2:DEC     HL
        LD      (SRPOS),HL
        JP      SRLOOP
SRFAIL: LD      DE,MSGNOTF
        CALL    MESSAGE
        JP      MAIN

; :[range]s/old/new/[g] -- literal, case-sensitive, no regex
; Range: current line by default, %, address, or address,address.
; Addresses are 1-based decimal, . and $.
SUBCMD: LD      HL,CMDTXT
        LD      A,(HL)
        CP      '%'
        JP      NZ,SBADR
        INC     HL
        LD      (SBPTR),HL
        LD      HL,1
        LD      (RSTART),HL
        LD      HL,65535
        LD      (REND),HL
        JP      SBOP
SBADR: CALL    CALCPOS
        LD      HL,(ROWNUM)
        INC     HL
        LD      (RSTART),HL
        LD      (REND),HL
        LD      HL,CMDTXT
        LD      (SBPTR),HL
        LD      A,(HL)
        CP      's'
        JP      Z,SBOP
        CALL    READADR
        JP      C,COLBAD
        LD      (RSTART),DE
        LD      (REND),DE
        LD      A,(HL)
        CP      ','
        JP      NZ,SBSET
        INC     HL
        LD      (SBPTR),HL
        CALL    READADR
        JP      C,COLBAD
        LD      (REND),DE
SBSET:  LD      (SBPTR),HL
SBOP:   LD      HL,(SBPTR)
        LD      A,(HL)
        CP      's'
        JP      NZ,COLBAD
        INC     HL
        LD      A,(HL)
        CP      '/'
        JP      NZ,COLBAD
        INC     HL
        LD      DE,SUBPAT
        LD      B,0
SBPAT:  LD      A,(HL)
        OR      A
        JP      Z,COLBAD
        CP      '/'
        JP      Z,SBPATD
        LD      (DE),A
        INC     DE
        INC     HL
        INC     B
        LD      A,B
        CP      70
        JP      NC,COLBAD
        JP      SBPAT
SBPATD:LD      A,B
        OR      A
        JP      Z,COLBAD
        LD      (SUBLEN),A
        INC     HL
        LD      DE,REPBUF
        LD      B,0
SBREP:  LD      A,(HL)
        OR      A
        JP      Z,SBREPD
        CP      '/'
        JP      Z,SBREPD
        LD      (DE),A
        INC     DE
        INC     HL
        INC     B
        LD      A,B
        CP      70
        JP      NC,COLBAD
        JP      SBREP
SBREPD:LD      A,B
        LD      (REPLEN),A
        XOR     A
        LD      (SUBG),A
        LD      A,(HL)
        OR      A
        JP      Z,SBGO
        INC     HL
        LD      A,(HL)
        OR      A
        JP      Z,SBGO
        CP      'g'
        JP      NZ,COLBAD
        INC     HL
        LD      A,(HL)
        OR      A
        JP      NZ,COLBAD
        LD      A,1
        LD      (SUBG),A
SBGO:   LD      HL,(RSTART)
        LD      DE,(REND)
        OR      A
        SBC     HL,DE
        JP      C,SBVALID
        JP      Z,SBVALID
        JP      COLBAD
SBVALID:CALL    SAVEUNDO
        ; Read from immutable undo snapshot, write new text to TXTBUF.
        LD      HL,0
        LD      (SRCIDX),HL
        LD      (DSTIDX),HL
        LD      HL,1
        LD      (SUBROW),HL
        XOR     A
        LD      (SUBFLG),A
        LD      (DIDROW),A
SBSLOOP:LD      HL,(SRCIDX)
        LD      DE,(UNDOLEN)
        OR      A
        SBC     HL,DE
        JP      NC,SBDONE
        LD      HL,(SUBROW)
        LD      DE,(RSTART)
        OR      A
        SBC     HL,DE
        JP      C,SBCOPY
        LD      HL,(SUBROW)
        LD      DE,(REND)
        OR      A
        SBC     HL,DE
        JP      C,SBTRY
        JP      Z,SBTRY
        JP      SBCOPY
SBTRY:  LD      HL,(SRCIDX)
        LD      A,(SUBLEN)
        LD      E,A
        LD      D,0
        ADD     HL,DE
        LD      DE,(UNDOLEN)
        OR      A
        SBC     HL,DE
        JP      C,SBTEST
        JP      Z,SBTEST
        JP      SBCOPY
SBTEST: LD      A,(SUBG)
        OR      A
        JP      NZ,SBTEST2
        LD      A,(DIDROW)
        OR      A
        JP      NZ,SBCOPY
SBTEST2:LD      HL,(SRCIDX)
        LD      DE,UNDBUF
        ADD     HL,DE
        LD      DE,SUBPAT
        LD      A,(SUBLEN)
        LD      B,A
SBMATCH:LD      A,B
        OR      A
        JP      Z,SBHIT
        LD      A,(HL)
        CP      10
        JP      Z,SBCOPY
        LD      C,A
        LD      A,(DE)
        CP      C
        JP      NZ,SBCOPY
        INC     HL
        INC     DE
        DJNZ    SBMATCH
SBHIT:  LD      HL,(SRCIDX)
        LD      A,(SUBLEN)
        LD      E,A
        LD      D,0
        ADD     HL,DE
        LD      DE,(UNDOLEN)
        OR      A
        SBC     HL,DE
        JP      C,SBHOK
        JP      Z,SBHOK
        JP      SBCOPY
SBHOK:  LD      A,1
        LD      (DIDROW),A
        LD      (SUBFLG),A
        LD      HL,(SRCIDX)
        LD      A,(SUBLEN)
        LD      E,A
        LD      D,0
        ADD     HL,DE
        LD      (SRCIDX),HL
        LD      HL,REPBUF
        LD      A,(REPLEN)
        LD      B,A
SBPUT:  LD      A,B
        OR      A
        JP      Z,SBSLOOP
        LD      A,(HL)
        PUSH    HL
        PUSH    BC
        CALL    SBOUT
        POP     BC
        POP     HL
        JP      C,SBOVER
        INC     HL
        DJNZ    SBPUT
        JP      SBSLOOP
SBCOPY: LD      HL,(SRCIDX)
        LD      DE,UNDBUF
        ADD     HL,DE
        LD      A,(HL)
        CP      10
        JP      NZ,SBCON
        PUSH    AF
        XOR     A
        LD      (DIDROW),A
        LD      HL,(SUBROW)
        INC     HL
        LD      (SUBROW),HL
        POP     AF
SBCON:  CALL    SBOUT
        JP      C,SBOVER
        LD      HL,(SRCIDX)
        INC     HL
        LD      (SRCIDX),HL
        JP      SBSLOOP
; Output A into output text at DSTIDX, carry on overflow.
SBOUT:  PUSH    AF
        LD      HL,(DSTIDX)
        LD      DE,MAXTXT
        OR      A
        SBC     HL,DE
        JP      NC,SBOUTF
        LD      HL,(DSTIDX)
        LD      DE,TXTBUF
        ADD     HL,DE
        POP     AF
        LD      (HL),A
        LD      HL,(DSTIDX)
        INC     HL
        LD      (DSTIDX),HL
        OR      A
        RET
SBOUTF:POP     AF
        SCF
        RET
SBDONE: LD      A,(SUBFLG)
        OR      A
        JP      Z,SBNONE
        LD      HL,(DSTIDX)
        LD      (TEXLEN),HL
        LD      HL,(UNDOIDX)
        LD      DE,(TEXLEN)
        OR      A
        SBC     HL,DE
        JP      C,SBCUR
        LD      HL,(TEXLEN)
        JP      SBCRSET
SBCUR:  LD      HL,(UNDOIDX)
SBCRSET:LD      (CURIDX),HL
        LD      A,1
        LD      (MODFLG),A
        JP      NREDRAW
SBNONE: LD      HL,(UNDOLEN)
        LD      (TEXLEN),HL
        LD      DE,MSGNOTF
        CALL    MESSAGE
        JP      MAIN
SBOVER:LD      BC,(UNDOLEN)
        LD      HL,UNDBUF
        LD      DE,TXTBUF
        LDIR
        LD      HL,(UNDOLEN)
        LD      (TEXLEN),HL
        LD      DE,MSGFULL
        CALL    MESSAGE
        JP      MAIN
; Parse an address at HL. Returns DE=line, HL advanced, CY on failure.
READADR:LD      A,(HL)
        CP      '.'
        JP      NZ,RADOLL
        CALL    CALCPOS
        LD      DE,(ROWNUM)
        INC     DE
        INC     HL
        OR      A
        RET
RADOLL: CP      '$'
        JP      NZ,RADNUM
        INC     HL
        LD      DE,65535
        OR      A
        RET
RADNUM: LD      DE,0
        LD      A,(HL)
        CP      '0'
        JP      C,RADFAIL
        CP      3AH
        JP      NC,RADFAIL
RADIG:  LD      A,(HL)
        CP      '0'
        JP      C,RADOK
        CP      3AH
        JP      NC,RADOK
        SUB     '0'
        LD      C,A
        PUSH    HL
        LD      H,D
        LD      L,E
        ADD     HL,HL
        LD      D,H
        LD      E,L
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,DE
        LD      E,C
        LD      D,0
        ADD     HL,DE
        EX      DE,HL
        POP     HL
        INC     HL
        JP      RADIG
RADOK: LD      A,D
        OR      E
        JP      Z,RADFAIL
        OR      A
        RET
RADFAIL:SCF
        RET

; :number jumps to line, and :$ jumps to EOF.
JUMPCMD:
        LD      HL,CMDTXT
        LD      A,(HL)
        CP      '$'
        JP      Z,GOLAST
        CALL    READADR
        JP      C,COLBAD
        LD      A,(HL)
        OR      A
        JP      NZ,COLBAD
        LD      HL,0
        LD      (CURIDX),HL
JMLOOP: DEC     DE
        LD      A,D
        OR      E
        JP      Z,NREDRAW
        LD      HL,(CURIDX)
        CALL    LINEEND
        CALL    CMPEND
        JP      NC,NREDRAW
        INC     HL
        LD      (CURIDX),HL
        JP      JMLOOP
WORKDIR:DEFB    0
SBPTR:  DEFW    0
MSGNOTF:DEFB    'Pattern not found','$'
MSGFULL:DEFB    'Replacement exceeds text buffer','$'

VTREG:  DEFB    27,'[1',59,'23r','$'
VTREST: DEFB    27,'[r','$'
VTCLR:  DEFB    27,'[2J',27,'[H','$'
SOCLR:  DEFB    27,'*','$'
STNAME: DEFB    'VI  ','$'
STTRUNC:DEFB  ' [TRUNCATED - READ ONLY]','$'
STMOD:  DEFB    ' [+]','$'
STINS:  DEFB    '  -- INSERT --','$'
STNOR:  DEFB    '  [NORMAL]','$'
NONAME: DEFB    '[No name]','$'
MSGLONG:DEFB   'Line too long for yank register','$'
MSGUNSV:DEFB   'Unsaved changes',59,' use :q! to abandon','$'
MSGHELP:DEFB   '/ ? n N :s/a/b/g :%s/a/b/g :1,9s/a/b/g','$'
MSGCMD: DEFB    'Unknown command (:h for help)','$'
MSGNOFL:DEFB   'No filename (use VI FILE.TXT)','$'
MSGTRUNC:DEFB  'WARNING: file truncated! Save disabled :q! to exit','$'
MSGTEMP:DEFB   'Existing .VIT temp: recover/remove first','$'
MSGERROR:DEFB  'Save error! Check .VIT and .BAK files','$'
MSGSAVED:DEFB  'Written (.BAK if file existed)','$'
BLANKS: DEFB    '                                                                               $'

OLDSP:  DEFW    0
TERM:   DEFB    0
MODE:   DEFB    0
MODFLG: DEFB    0
UNDOK:  DEFB    0
PEND:   DEFB    0
HASFILE:DEFB    0
TOOBIG: DEFB    0
PREVCR: DEFB    0
INCHAR: DEFB    0
DIDNL:  DEFB    0
OUTCNT: DEFB    0
FAILWR: DEFB    0
HADOLD: DEFB    0
DRAWROW:DEFB    0
EXHAUS: DEFB    0
COLNUM: DEFB    0
CMDLEN: DEFB    0
PRCHAR: DEFB    0
YANKLEN:DEFB    0
SRDIR:  DEFB    0
PATLEN: DEFB    0
SUBLEN: DEFB    0
REPLEN: DEFB    0
SUBG:   DEFB    0
SUBFLG: DEFB    0
DIDROW: DEFB    0
ISGOOD: DEFB    0
MCHEND: DEFW    0
CURROW: DEFW    0
RSTART: DEFW    0
REND:   DEFW    0
SRPOS:  DEFW    0
SRLEFT: DEFW    0
SRBEST: DEFW    0
SRCIDX: DEFW    0
DSTIDX: DEFW    0
SUBROW: DEFW    0
NUMACC: DEFW    0
OLDPOS: DEFW    0
PATBUF: DEFS    80
SUBPAT: DEFS    80
REPBUF: DEFS    80
CMDPTR: DEFW    0
CMDTXT: DEFS    80
TEXLEN: DEFW    0
CURIDX: DEFW    0
TOPLIN: DEFW    0
OLDTOP: DEFW    0
SKIPLN: DEFW    0
SHCNT:  DEFB    0
SHDIR:  DEFB    0
ROWNUM: DEFW    0
DRAWP:  DEFW    0
UNDOLEN:DEFW    0
UNDOIDX:DEFW    0
YBEGIN: DEFW    0
DELEND: DEFW    0
DELCNT: DEFW    0
FILEIDX:DEFW    0
FCB:    DEFS    36
TMPFCB: DEFS    36
BAKFCB: DEFS    36
RENFCB: DEFS    36
RECBUF: DEFS    128
YANKBUF:DEFS    256
TXTBUF: DEFS    MAXTXT
UNDBUF: DEFS    MAXTXT
STKBASE:DEFS    192
STKTOP:
