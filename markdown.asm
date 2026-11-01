; MARKDOWN.COM v0.1 - Zapple-II CP/M 2.2 Markdown to PostScript
; Udo Munk z80asm syntax. MARKDOWN INPUT.TXT OUTPUT.PS
; Minimal Markdown: # ## ### headings, paragraphs, **bold**, *italic*,
; _italic_, - / * bullets and blank lines.
; Courier/Helvetica standard PS fonts; ASCII only, 72-column hard wrap.
; Output is CP/M records padded with spaces (not ^Z).
BDOS    EQU 0005H
        ORG 0100H
START   LD SP,STKTOP
        CALL ARGS
        JP C,BADARG
        LD HL,(ARG1)
        CALL MAKEFC
        JP C,BADARG
        LD DE,INFCB
        LD HL,FCB
        LD BC,36
        LDIR
        LD HL,(ARG2)
        CALL MAKEFC
        JP C,BADARG
        LD DE,OUTFCB
        LD HL,FCB
        LD BC,36
        LDIR
        LD DE,INFCB
        LD C,15
        CALL BDOS
        CP 255
        JP Z,BADIN
        LD DE,OUTFCB
        LD C,19                 ; delete prior output, if present
        CALL BDOS
        LD DE,OUTFCB
        LD C,22                 ; make
        CALL BDOS
        CP 255
        JP Z,BADOUT
        LD A,1
        LD (OUTOPEN),A
        LD HL,0
        LD (IPOS),HL
        LD HL,OUTBUF
        LD (OPOS),HL
        LD A,128
        LD (IREM),A
        XOR A
        LD (HAVEIN),A
        LD (EOT),A
        LD (CODE),A
        LD (STYLE),A
        LD (PREVCR),A
        LD (COL),A
        LD (LINES),A
        LD HL,HEADER
        CALL PSTR
        CALL NEWPAGE
MAIN    CALL GETLINE
        JP C,FINISH
        CALL LINE
        JP MAIN
FINISH  LD HL,PGEND
        CALL PSTR
        LD HL,EOFPS
        CALL PSTR
        CALL FLUSHO
        JP C,WRITEER
        LD DE,OUTFCB
        LD C,16
        CALL BDOS
        LD DE,INFCB
        LD C,16
        CALL BDOS
        LD DE,DONE
        CALL PRINT
        LD C,0
        JP BDOS
BADARG  LD DE,USAGE
        JP ERROR
BADIN   LD DE,INERR
        JP ERROR
BADOUT  LD DE,OUTERR
        JP ERROR
WRITEER LD DE,WRERR
ERROR   CALL PRINT
        LD C,0
        JP BDOS
PRINT   LD C,9
        JP BDOS
; parse two words in CCP command tail, preserving the existing case.
ARGS    LD HL,0081H
        LD B,0
ARSKIP  LD A,(HL)
        CP ' '
        JP Z,ARADV
        CP 9
        JP NZ,ARWORD
ARADV   INC HL
        JP ARSKIP
ARWORD  CP 13
        JP Z,ARDONE
        CP 0
        JP Z,ARDONE
        LD A,B
        CP 2
        JP NC,ARFAIL
        LD A,B
        OR A
        JP NZ,ARW2
        LD (ARG1),HL
        JP ARSCAN
ARW2    LD (ARG2),HL
ARSCAN  LD A,(HL)
        CP 13
        JP Z,AREND
        CP 0
        JP Z,AREND
        CP ' '
        JP Z,ARTERM
        CP 9
        JP Z,ARTERM
        INC HL
        JP ARSCAN
ARTERM  LD (HL),0
        INC B
        INC HL
        JP ARSKIP
AREND   LD (HL),0
        INC B
ARDONE  LD A,B
        CP 2
        JP NZ,ARFAIL
        OR A
        RET
ARFAIL  SCF
        RET
; Input HL points to CP/M name. FCB may have drive prefix.
MAKEFC  PUSH HL
        LD HL,FCB
        LD B,36
        XOR A
MCLEAR  LD (HL),A
        INC HL
        DJNZ MCLEAR
        LD HL,FCB+1
        LD B,11
        LD A,' '
MSPACE  LD (HL),A
        INC HL
        DJNZ MSPACE
        POP HL
        LD A,(HL)
        OR A
        JP Z,MFERR
        PUSH HL
        INC HL
        LD A,(HL)
        CP ':'
        POP HL
        JP NZ,MFBASE
        LD A,(HL)
        CALL UPCASE
        SUB 'A'-1
        CP 1
        JP C,MFERR
        CP 17
        JP NC,MFERR
        LD (FCB),A
        INC HL
        INC HL
MFBASE  LD DE,FCB+1
        LD B,8
        LD C,0
MFNAM   LD A,(HL)
        OR A
        JP Z,MFEND
        CP '.'
        JP Z,MFEXT
        CALL UPCASE
        CALL FNCHAR
        JP C,MFERR
        LD A,B
        OR A
        JP Z,MFERR
        LD A,(HL)
        CALL UPCASE
        LD (DE),A
        INC DE
        INC HL
        DEC B
        INC C
        JP MFNAM
MFEXT   LD A,C
        OR A
        JP Z,MFERR
        INC HL
        LD DE,FCB+9
        LD B,3
MFEXLP  LD A,(HL)
        OR A
        JP Z,MFOK
        CP '.'
        JP Z,MFERR
        CALL UPCASE
        CALL FNCHAR
        JP C,MFERR
        LD A,B
        OR A
        JP Z,MFERR
        LD A,(HL)
        CALL UPCASE
        LD (DE),A
        INC DE
        INC HL
        DEC B
        JP MFEXLP
MFEND  LD A,C
        OR A
        JP Z,MFERR
MFOK    OR A
        RET
MFERR   SCF
        RET
FNCHAR CP 'A'
        JP C,FNCHK
        CP 'Z'+1
        JP C,FNGOOD
FNCHK  CP '0'
        JP C,FNFAIL
        CP '9'+1
        JP C,FNGOOD
FNFAIL CP '_'
        JP Z,FNGOOD
        CP '$'
        JP Z,FNGOOD
        CP '-'
        JP Z,FNGOOD
        SCF
        RET
FNGOOD  OR A
        RET
UPCASE  CP 'a'
        RET C
        CP 'z'+1
        RET NC
        SUB 32
        RET
; Sequential input using private 128-byte DMA buffer.
GETBYTE LD A,(HAVEIN)
        OR A
        JP NZ,GBHAS
        LD DE,INBUF
        LD C,26
        CALL BDOS
        LD DE,INFCB
        LD C,20
        CALL BDOS
        OR A
        JP NZ,GBEOF
        LD A,1
        LD (HAVEIN),A
        LD HL,INBUF
        LD (IPOS),HL
        LD A,128
        LD (IREM),A
GBHAS   LD HL,(IPOS)
        LD A,(HL)
        INC HL
        LD (IPOS),HL
        PUSH AF
        LD A,(IREM)
        DEC A
        LD (IREM),A
        JP NZ,GBRET
        XOR A
        LD (HAVEIN),A
GBRET   POP AF
        OR A
        RET
GBEOF   SCF
        RET
; Return one line in LINEBUF (<= 120 chars), carry on EOF.
; For very long lines, split into consecutive physical lines.
GETLINE LD HL,LINEBUF
        LD (LINPTR),HL
        XOR A
        LD (LINLEN),A
GLLOOP  LD A,(PEND)
        OR A
        JP Z,GLREAD
        XOR A
        LD (PEND),A
        LD A,(PENDCHR)
        JP GLCHAR
GLREAD  CALL GETBYTE
        JP C,GLEOF
        CP 26
        JP Z,GLEOF
GLCHAR  CP 13
        JP Z,GLCR
        CP 10
        JP Z,GLEND
        LD HL,(LINPTR)
        LD (HL),A
        INC HL
        LD (LINPTR),HL
        LD A,(LINLEN)
        INC A
        LD (LINLEN),A
        CP 119
        JP NC,GLEND
        JP GLLOOP
GLCR    CALL GETBYTE
        JP C,GLEND
        CP 10
        JP Z,GLEND
        ; Non-LF character after CR is lost on legacy CR files.
        ; Store it as first char of next physical line via PENDING.
        LD (PENDCHR),A
        LD A,1
        LD (PEND),A
        JP GLEND
GLEOF   LD A,(LINLEN)
        OR A
        SCF
        RET Z
GLEND   LD HL,(LINPTR)
        LD (HL),0
        OR A
        RET
; Handle pending char from bare CR (rewritten entry below).
; output writer: 128-byte records, space pad final record.
OUTBYTE PUSH AF
        LD HL,(OPOS)
        LD A,H
        OR L
        JP NZ,OBSET
        LD HL,OUTBUF
OBSET   POP AF
        LD (HL),A
        INC HL
        LD (OPOS),HL
        LD DE,OUTBUF+128
        OR A
        SBC HL,DE
        RET NZ
        LD DE,OUTBUF
        LD C,26
        CALL BDOS
        LD DE,OUTFCB
        LD C,21
        CALL BDOS
        OR A
        JP NZ,OBFAIL
        LD HL,OUTBUF
        LD (OPOS),HL
        OR A
        RET
OBFAIL SCF
        RET
FLUSHO  LD HL,(OPOS)
        LD DE,OUTBUF
        OR A
        SBC HL,DE
        RET Z
        LD HL,(OPOS)
FLUPAD  LD (HL),' '
        INC HL
        LD DE,OUTBUF+128
        PUSH HL
        OR A
        SBC HL,DE
        POP HL
        JP NZ,FLUPAD
        LD DE,OUTBUF
        LD C,26
        CALL BDOS
        LD DE,OUTFCB
        LD C,21
        CALL BDOS
        OR A
        RET Z
        SCF
        RET
PSTR    LD A,(HL)
        OR A
        RET Z
        PUSH HL
        CALL OUTBYTE
        POP HL
        INC HL
        JP PSTR
; Emit fixed macro commands. One physical text line = one PS row.
NEWPAGE LD HL,PGSTART
        CALL PSTR
        XOR A
        LD (LINES),A
        LD (COL),A
        RET
NEXTPG LD HL,PGEND
        CALL PSTR
        JP NEWPAGE
EOL     LD HL,EOLTXT
        CALL PSTR
        LD A,(LINES)
        INC A
        LD (LINES),A
        CP 51
        JP NC,NEXTPG
        RET
; Input line dispatch
LINE    LD A,(LINLEN)
        OR A
        JP NZ,NOTBL
        CALL EOL
        RET
NOTBL   LD HL,LINEBUF
        LD A,(HL)
        CP '#'
        JP Z,HEADING
        CP '-'
        JP Z,BULLET
        CP '*'
        JP Z,TESTBUL
        JP NORMAL
TESTBUL INC HL
        LD A,(HL)
        CP ' '
        JP Z,BULLET
        JP NORMAL
BULLET  LD HL,BULPS
        CALL PSTR
        LD HL,LINEBUF+2
        JP TEXTLN
HEADING LD HL,LINEBUF
        LD B,0
HCOUNT  LD A,(HL)
        CP '#'
        JP NZ,HTITLE
        INC HL
        INC B
        LD A,B
        CP 4
        JP C,HCOUNT
HTITLE  LD A,(HL)
        CP ' '
        JP NZ,NORMAL
        INC HL
        PUSH HL
        LD A,B
        CP 1
        JP NZ,HLEVEL2
        LD HL,H1PS
        JP HGO
HLEVEL2 CP 2
        JP NZ,HLEVEL3
        LD HL,H2PS
        JP HGO
HLEVEL3 LD HL,H3PS
HGO     CALL PSTR
        POP HL
        CALL TEXTLN
        LD HL,RESETPS
        CALL PSTR
        RET
NORMAL  LD HL,LINEBUF
        JP TEXTLN
; TEXTLN: HL string; inline styles apply. Hard wrap on column 72.
TEXTLN  XOR A
        LD (STYLE),A
        LD (COL),A
        PUSH HL
        LD HL,TSTART
        CALL PSTR
        POP HL
TXLOOP  LD A,(HL)
        OR A
        JP Z,TXEND
        CP '*'
        JP Z,TXSTAR
        CP '_'
        JP Z,TXITAL
        CP 05CH
        JP NZ,TXCHAR
        INC HL
        LD A,(HL)
        OR A
        JP Z,TXEND
        JP TXCHAR
TXSTAR  INC HL
        LD A,(HL)
        CP '*'
        JP NZ,TITONE
        INC HL
        PUSH HL
        LD A,(STYLE)
        XOR 2
        LD (STYLE),A
        CALL STYFONT
        POP HL
        JP TXLOOP
TITONE PUSH HL
        LD A,(STYLE)
        XOR 1
        LD (STYLE),A
        CALL STYFONT
        POP HL
        JP TXLOOP
TXITAL  INC HL
        PUSH HL
        LD A,(STYLE)
        XOR 1
        LD (STYLE),A
        CALL STYFONT
        POP HL
        JP TXLOOP
TXCHAR  PUSH HL
        CALL PSCHAR
        POP HL
        LD A,(COL)
        INC A
        LD (COL),A
        CP 72
        JP C,TXNEXT
        PUSH HL
        LD HL,TWRAP
        CALL PSTR
        CALL EOL
        LD HL,TSTART
        CALL PSTR
        XOR A
        LD (COL),A
        POP HL
TXNEXT  INC HL
        JP TXLOOP
TXEND   LD HL,TEND
        CALL PSTR
        CALL EOL
        LD A,(STYLE)
        OR A
        RET Z
        XOR A
        LD (STYLE),A
        LD HL,REGFONT
        JP PSTR
; styles close current PS string then select font and reopen.
STYFONT PUSH AF
        LD HL,TEND
        CALL PSTR
        LD A,(STYLE)
        OR A
        JP Z,SREG
        CP 1
        JP Z,SITAL
        CP 2
        JP Z,SBOLD
        LD HL,BIFONT
        JP SFGO
SITAL   LD HL,ITFONT
        JP SFGO
SBOLD   LD HL,BOFONT
        JP SFGO
SREG    LD HL,REGFONT
SFGO    CALL PSTR
        LD HL,TSTART
        CALL PSTR
        POP AF
        RET
PSCHAR  CP '('
        JP Z,ESCPS
        CP ')'
        JP Z,ESCPS
        CP 05CH
        JP Z,ESCPS
        CP 32
        JP C,PSPACE
        JP OUTBYTE
PSPACE  LD A,' '
        JP OUTBYTE
ESCPS   PUSH AF
        LD A,05CH
        CALL OUTBYTE
        POP AF
        JP OUTBYTE
; PostScript setup: moveto + show, newline through /nl, and automatic pages.
HEADER  DEFM '%!PS-Adobe-3.0'
        DEFB 10
        DEFM '%%Creator: Zapple-II MARKDOWN 0.1'
        DEFB 10
        DEFM '%%Pages: (atend)'
        DEFB 10
        DEFM '/R {/Courier findfont 11 scalefont setfont} def'
        DEFB 10
        DEFM '/B {/Courier-Bold findfont 11 scalefont setfont} def'
        DEFB 10
        DEFM '/I {/Courier-Oblique findfont 11 scalefont setfont} def'
        DEFB 10
        DEFM '/BI {/Courier-BoldOblique findfont 11 scalefont setfont} def'
        DEFB 10
        DEFM '/nl {/y y 14 sub def 65 y moveto} def'
        DEFB 10,0
PGSTART DEFM '/y 760 def R 65 y moveto'
        DEFB 10,0
EOFPS   DEFM '%%EOF'
        DEFB 10,0
PGEND   DEFM 'showpage'
        DEFB 10,0
TSTART  DEFM '('
        DEFB 0
TEND    DEFM ') show'
        DEFB 10,0
TWRAP   DEFM ') show'
        DEFB 10,0
EOLTXT  DEFM 'nl'
        DEFB 10,0
RESETPS DEFM 'R'
        DEFB 10,0
REGFONT DEFM 'R'
        DEFB 10,0
BOFONT  DEFM 'B'
        DEFB 10,0
ITFONT  DEFM 'I'
        DEFB 10,0
BIFONT  DEFM 'BI'
        DEFB 10,0
H1PS    DEFM '/Helvetica-Bold findfont 20 scalefont setfont'
        DEFB 10,0
H2PS    DEFM '/Helvetica-Bold findfont 16 scalefont setfont'
        DEFB 10,0
H3PS    DEFM '/Helvetica-Bold findfont 13 scalefont setfont'
        DEFB 10,0
BULPS   DEFM '(*) show '
        DEFB 0
USAGE   DEFM 'Usage: MARKDOWN INPUT.TXT OUTPUT.PS'
        DEFB 13,10,'$'
INERR   DEFM 'Cannot open input'
        DEFB 13,10,'$'
OUTERR  DEFM 'Cannot create output'
        DEFB 13,10,'$'
WRERR   DEFM 'Write error'
        DEFB 13,10,'$'
DONE    DEFM 'Done'
        DEFB 13,10,'$'
ARG1    DEFW 0
ARG2    DEFW 0
IPOS    DEFW 0
OPOS    DEFW 0
LINPTR  DEFW 0
HAVEIN  DEFB 0
IREM    DEFB 0
LINLEN  DEFB 0
OUTOPEN DEFB 0
EOT     DEFB 0
CODE    DEFB 0
STYLE   DEFB 0
PREVCR  DEFB 0
COL     DEFB 0
LINES   DEFB 0
PEND    DEFB 0
PENDCHR DEFB 0
FCB     DEFS 36
INFCB   DEFS 36
OUTFCB  DEFS 36
INBUF   DEFS 128
OUTBUF  DEFS 128
LINEBUF DEFS 128
STACK   DEFS 256
STKTOP
        END
