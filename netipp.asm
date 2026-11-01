; NETIPP.COM v0.2 - corrected printer-uri length for Zapple-II / CP/M 2.2
; Usage: NETIPP host queue filename (TCP port 631, DNS supported).
; CUPS IPP/1.1 Print-Job over HTTP, .TXT/.PS/.PDF auto-format, no TLS.
; Stop at first CP/M control-Z (1AH); no binary file support.
; CP/M file records are 128 bytes.
; Kernel owns network and sockets, W5100 is NOT reset.
; Udo Munk z80asm, labels <=8 significant characters.
BDOS    EQU 0005H
        ORG 0100H
START   LD SP,STKTOP
        LD HL,VARS0
        LD BC,VARS1-VARS0
ZINIT   XOR A
        LD (HL),A
        INC HL
        DEC BC
        LD A,B
        OR C
        JP NZ,ZINIT
        CALL GETARG
        JP C,USAGEE
        LD A,(TCOUNT)
        CP 3
        JP NZ,USAGEE
        LD HL,(TOKENS)
        LD DE,HOSTNAM
        LD B,63
NCCOPY  LD A,(HL)
        OR A
        JP Z,NCCEND
        LD (DE),A
        INC DE
        INC HL
        DJNZ NCCOPY
        JP IPERR
NCCEND  XOR A
        LD (DE),A
        LD HL,HOSTNAM
        LD DE,HOSTIP
        LD B,4
CIPLP   PUSH BC
        PUSH DE
        CALL OCTET
        POP DE
        POP BC
        JP C,NCDNS
        LD (DE),A
        INC DE
        DEC B
        JP Z,CIPEND
        LD A,(HL)
        CP '.'
        JP NZ,NCDNS
        INC HL
        JP CIPLP
CIPEND  LD A,(HL)
        OR A
        JP Z,NCDONE
NCDNS   CALL DNSINIT
        LD HL,HOSTNAM
        CALL DNRSLV
        JP C,DNSERR
        EX DE,HL
        LD DE,HOSTIP
        LD BC,4
        LDIR
NCDONE  LD A,02H          ; 631 = 0277H
        LD (PORT21),A
        LD A,077H
        LD (PORT21+1),A
        LD HL,(TOKENS+2)
        LD (QPTR),HL
        LD A,(HL)
        OR A
        JP Z,USAGEE
        LD HL,(TOKENS+4)
        LD (OUTPTR),HL
        CALL FPAR
        JP C,NAMEERR
        LD DE,FCB
        LD C,15
        CALL BDOS
        CP 0FFH
        JP Z,OPENERR
        LD A,1
        LD (FILEOP),A
        ; Determine Content-Length before opening TCP. This is
        ; required by HTTP/1.1 and avoids keeping a page in RAM.
        LD A,1
        LD (DRYRUN),A
        CALL IPPBODY
        JP C,PREERR
        CALL FLUSH
        JP C,PREERR
        CALL DOSEND
        JP C,READERR
        LD HL,(LENLO)
        LD (TOTLO),HL
        LD HL,(LENHI)
        LD (TOTHI),HL
        CALL CLOSEF
        LD DE,FCB
        LD C,15
        CALL BDOS
        CP 0FFH
        JP Z,REOPERR
        LD A,1
        LD (FILEOP),A
        XOR A
        LD (DRYRUN),A
        LD (LENLO),A
        LD (LENLO+1),A
        LD (LENHI),A
        LD (LENHI+1),A
        CALL ALLOC
        JP C,NETERR
        LD (CURSOCK),A
        LD (CSOCK),A
        LD A,1
        LD (CHELD),A
        LD HL,HOSTIP
        LD (DESTIP),HL
        LD HL,PORT21
        LD (DESTPRT),HL
        CALL SETTCP
        CALL CONNEC
        JP C,NETERR
        LD A,1
        LD (INHEADER),A
        CALL HTTPHDR
        JP C,NETERR
        XOR A
        LD (INHEADER),A
        CALL IPPBODY
        JP C,NETERR
        CALL FLUSH
        JP C,NETERR
        LD DE,SNDMSG
        CALL PRINT
        CALL DOSEND
        JP C,NETERR
        CALL RESPOND
        JP C,NETERR
        LD DE,DONEMSG
        CALL PRINT
        JP CLEAN
DNSERR  LD DE,DNSBAD
        JP FATAL
IPERR   LD DE,IPMSG
        JP FATAL
PORTERR LD DE,PRTMSG
        JP FATAL
NAMEERR LD DE,NAMMSG
        JP FATAL
USAGEE  LD DE,USAGE
        JP FATAL
OPENERR LD DE,OPENMSG
        JP FATAL
PREERR  LD DE,PREMSG
        JP FATAL
READERR LD DE,READMSG
        JP FATAL
REOPERR LD DE,REOPMSG
        JP FATAL
FILEERR LD DE,FILMSG
        JP FATAL
NETERR  LD DE,NETMSG
        CALL PRINT
        LD A,(CHELD)
        OR A
        JP Z,CLEAN
        LD DE,STATEMSG
        CALL PRINT
        CALL FBGET
        CALL HEXBYT
        LD DE,CRLF
        CALL PRINT
        JP CLEAN
FATAL   CALL PRINT
CLEAN   CALL CLOSEF
        LD A,(CHELD)
        OR A
        JP Z,QUIT
        LD A,(CSOCK)
        CALL FREEONE
QUIT    LD C,0
        JP BDOS
ARGBAD  SCF
        RET
CFERR   SCF
        RET
PRINT   LD C,9
        JP BDOS
PUTC    LD E,A
        LD C,2
        JP BDOS
HEXBYT  PUSH AF
        RRCA
        RRCA
        RRCA
        RRCA
        CALL HEXNIB
        POP AF
HEXNIB  AND 0FH
        ADD A,'0'
        CP '9'+1
        JP C,PUTC
        ADD A,7
        JP PUTC
; Tokenize the CCP command tail in private memory (up to 6 tokens).
GETARG  LD A,(0080H)
        CP 126
        JP NC,ARGERR
        LD B,A
        LD HL,0081H
        LD DE,CMDTXT
ARGCP   LD A,B
        OR A
        JP Z,ARGEND
        LD A,(HL)
        LD (DE),A
        INC HL
        INC DE
        DJNZ ARGCP
ARGEND  XOR A
        LD (DE),A
        LD HL,CMDTXT
        LD DE,TOKENS
ARGNEXT CALL SKIPSP
        LD A,(HL)
        OR A
        JP Z,ARGDONE
        LD A,(TCOUNT)
        CP 6
        JP NC,ARGERR
        LD A,L
        LD (DE),A
        INC DE
        LD A,H
        LD (DE),A
        INC DE
        LD A,(TCOUNT)
        INC A
        LD (TCOUNT),A
        CALL NEXTTK
        JP ARGNEXT
ARGDONE LD A,(TCOUNT)
        CP 1
        JP C,ARGERR
        OR A
        RET
ARGERR  SCF
        RET
SKIPSP  LD A,(HL)
        CP ' '
        JP Z,SKP1
        CP 9
        RET NZ
SKP1    INC HL
        JP SKIPSP
NEXTTK  LD A,(HL)
        OR A
        RET Z
        CP ' '
        JP Z,TKEND
        CP 9
        JP Z,TKEND
        INC HL
        JP NEXTTK
TKEND   LD (HL),0
        INC HL
        RET
UPPER   CP 'a'
        RET C
        CP 'z'+1
        RET NC
        SUB 32
        RET
; HL string, DE uppercase string. Return Z on case-insensitive match.
STREQ   LD A,(DE)
        LD B,A
        LD A,(HL)
        CALL UPPER
        CP B
        RET NZ
        OR A
        RET Z
        INC HL
        INC DE
        JP STREQ

; HL decimal port. Return error on missing digits, overflow, trailing text.
GETPORT LD DE,0
        LD A,0
        LD (NDIG),A
PORTLP  LD A,(HL)
        OR A
        JP Z,PORTEND
        CP '0'
        JP C,ARGBAD
        CP '9'+1
        JP NC,ARGBAD
        SUB '0'
        LD (DIGIT),A
        PUSH HL
        EX DE,HL
        LD B,H
        LD C,L
        ADD HL,HL
        JP C,PORTOV
        ADD HL,HL
        JP C,PORTOV
        ADD HL,HL
        JP C,PORTOV
        ADD HL,BC
        JP C,PORTOV
        ADD HL,BC
        JP C,PORTOV
        LD A,(DIGIT)
        LD C,A
        LD B,0
        ADD HL,BC
        JP C,PORTOV
        EX DE,HL
        POP HL
        INC HL
        LD A,(NDIG)
        INC A
        LD (NDIG),A
        JP PORTLP
PORTOV  POP HL
        SCF
        RET
PORTEND LD A,(NDIG)
        OR A
        JP Z,ARGBAD
        LD A,D
        OR E
        JP Z,ARGBAD
        LD A,D
        LD (PORT21),A
        LD A,E
        LD (PORT21+1),A
        OR A
        RET
; A=0..255 decimal, HL advances to separator.
OCTET   LD B,0
        LD C,0
OCTLP   LD A,(HL)
        CP '0'
        JP C,OCTEND
        CP '9'+1
        JP NC,OCTEND
        SUB '0'
        LD D,A
        LD A,B
        ADD A,A
        JP C,OCTBAD
        LD E,A
        ADD A,A
        JP C,OCTBAD
        ADD A,A
        JP C,OCTBAD
        ADD A,E
        JP C,OCTBAD
        ADD A,D
        JP C,OCTBAD
        LD B,A
        INC C
        INC HL
        JP OCTLP
OCTEND  LD A,C
        OR A
        JP Z,OCTBAD
        LD A,B
        OR A
        RET
OCTBAD  SCF
        RET
FPAR    LD HL,FCB
        LD B,36
        XOR A
FZERO   LD (HL),A
        INC HL
        DJNZ FZERO
        LD HL,FCB+1
        LD B,11
FILLSP  LD (HL),' '
        INC HL
        DJNZ FILLSP
        LD HL,(OUTPTR)
        ; Optional CP/M drive spec A: through P:.
        ; Set FCB drive byte 1..16, or zero for default drive.
        LD A,(HL)
        CALL UPPER
        CP 'A'
        JP C,FPDRDON
        CP 'P'+1
        JP NC,FPDRDON
        INC HL
        LD A,(HL)
        DEC HL
        CP ':'
        JP NZ,FPDRDON
        LD A,(HL)
        CALL UPPER
        SUB 'A'-1
        LD (FCB),A
        INC HL
        INC HL
FPDRDON LD DE,FCB+1
        LD B,8
        LD C,0
FPNAME  LD A,(HL)
        OR A
        JP Z,FPNDONE
        CP '.'
        JP Z,FPEXT
        CALL FILCHR
        RET C
        LD A,B
        OR A
        JP Z,ARGBAD
        LD A,(HL)
        CALL UPPER
        LD (DE),A
        INC DE
        INC HL
        DEC B
        INC C
        JP FPNAME
FPEXT   LD A,C
        OR A
        JP Z,ARGBAD
        INC HL
        LD DE,FCB+9
        LD B,3
FPXLP   LD A,(HL)
        OR A
        JP Z,FPOK
        CP '.'
        JP Z,ARGBAD
        CALL FILCHR
        RET C
        LD A,B
        OR A
        JP Z,ARGBAD
        LD A,(HL)
        CALL UPPER
        LD (DE),A
        INC DE
        INC HL
        DEC B
        JP FPXLP
FPNDONE LD A,C
        OR A
        JP Z,ARGBAD
FPOK    OR A
        RET
FILCHR  CALL UPPER
        CP 'A'
        JP C,FCNUM
        CP 'Z'+1
        JP C,FCOK
FCNUM   CP '0'
        JP C,FCSP
        CP '9'+1
        JP C,FCOK
FCSP    CP '_'
        JP Z,FCOK
        CP '-'
        JP Z,FCOK
        CP '$'
        JP Z,FCOK
        SCF
        RET
FCOK    OR A
        RET
CHECKEX LD DE,FCB
        LD C,15
        CALL BDOS
        CP 0FFH
        JP Z,NEXIST
        LD DE,FCB
        LD C,16
        CALL BDOS
        LD A,2                ; GET destination already exists
        JP CFERR
NEXIST  OR A
        RET
CLOSEF  LD A,(FILEOP)
        OR A
        RET Z
        LD DE,FCB
        LD C,16
        CALL BDOS
        XOR A
        LD (FILEOP),A
        RET
FCREATE LD DE,FCB
        LD C,22
        CALL BDOS
        CP 0FFH
        JP Z,CRERR
        LD A,1
        LD (FILEOP),A
        LD DE,FILEBUF
        LD C,26
        CALL BDOS
        OR A
        RET
CRERR   LD A,4               ; local CREATE failed
        JP CFERR
WRREC   LD DE,FILEBUF
        LD C,26
        CALL BDOS
        LD DE,FCB
        LD C,21
        CALL BDOS
        OR A
        RET Z
        LD A,5               ; local WRITE failed
        JP CFERR
FINFILE LD A,(FIDX)
        OR A
        JP Z,FILCLOSE
        LD B,A
        LD HL,FILEBUF
        LD E,A
        LD D,0
        ADD HL,DE
FPADLP  LD (HL),01AH
        INC HL
        INC B
        LD A,B
        CP 128
        JP NZ,FPADLP
        CALL WRREC
        RET C
FILCLOSE CALL CLOSEF
        OR A
        RET
SAVECHR LD (SAVEB),A
        LD A,(FIDX)
        LD E,A
        LD D,0
        LD HL,FILEBUF
        ADD HL,DE
        LD A,(SAVEB)
        LD (HL),A
        LD A,(FIDX)
        INC A
        LD (FIDX),A
        CP 128
        JP NZ,SVOK
        CALL WRREC
        RET C
        XOR A
        LD (FIDX),A
SVOK    OR A
        RET

ALLOC   LD E,0
        LD C,0FAH
        CALL BDOS
        CP 4
        JP NC,ARGBAD
        OR A
        RET
FREEONE LD D,A
        LD E,1
        LD C,0FAH
        CALL BDOS
        RET
ALCCTL  CALL ALLOC
        RET C
        LD (CSOCK),A
        LD A,1
        LD (CHELD),A
        OR A
        RET
ALCDAT  CALL ALLOC
        RET C
        LD (DSOCK),A
        LD A,1
        LD (DHELD),A
        OR A
        RET
WSET    LD (WVAL),A
        LD A,(CURSOCK)
        ADD A,4
        LD (WPAR),A
        LD A,B
        LD (WPAR+1),A
        LD DE,WPAR
        LD C,0F9H
        CALL BDOS
        RET
SETTCP  LD B,0
        LD A,1
        CALL WSET
        LD B,4
        LD A,0C0H
        CALL WSET
        LD B,5
        LD A,(CURSOCK)
        ADD A,0E0H
        CALL WSET
        LD HL,(DESTIP)
        LD B,0CH
        LD A,(HL)
        PUSH HL
        CALL WSET
        POP HL
        INC HL
        LD B,0DH
        LD A,(HL)
        PUSH HL
        CALL WSET
        POP HL
        INC HL
        LD B,0EH
        LD A,(HL)
        PUSH HL
        CALL WSET
        POP HL
        INC HL
        LD B,0FH
        LD A,(HL)
        CALL WSET
        LD HL,(DESTPRT)
        LD B,10H
        LD A,(HL)
        PUSH HL
        CALL WSET
        POP HL
        INC HL
        LD B,11H
        LD A,(HL)
        CALL WSET
        LD B,0
        LD A,1
        CALL WSET
        OR A
        RET
FBGET   LD A,(CURSOCK)
        LD D,A
        LD E,0
        LD C,0FBH
        CALL BDOS
        RET
FBCMD   LD A,(CURSOCK)
        LD D,A
        LD C,0FBH
        CALL BDOS
        RET
CONNEC  LD E,1
        CALL FBCMD
        CP 0FFH
        JP Z,ARGBAD
        CALL FBGET
        CP 013H
        JP NZ,ARGBAD
        LD E,4
        CALL FBCMD
        CP 0FFH
        JP Z,ARGBAD
        LD HL,30000
CNWAIT  PUSH HL
        CALL FBGET
        POP HL
        CP 017H
        JP Z,CONOK
        CP 0
        JP Z,ARGBAD
        CP 01CH
        JP Z,ARGBAD
        DEC HL
        LD A,H
        OR L
        JP Z,ARGBAD
        LD A,L
        OR A
        JP NZ,CNWAIT
        PUSH HL
        LD C,11
        CALL BDOS
        POP HL
        JP CNWAIT
CONOK   OR A
        RET

; FC request: [socket, operation (0 send/1 recv), length, ptr lo, ptr hi].
; SENDRAW input HL=buffer, A=length 1..16. May perform partial writes.
SENDRAW LD (SPTR),HL
        LD (RLEFT),A
        LD HL,10000
        LD (SWAIT),HL
SRETRY  LD A,(CURSOCK)
        LD (NXP),A
        XOR A
        LD (NXP+1),A
        LD A,(RLEFT)
        LD (NXP+2),A
        LD HL,(SPTR)
        LD (NXP+3),HL
        LD DE,NXP
        LD C,0FCH
        CALL BDOS
        CP 0FFH
        JP Z,ARGBAD
        OR A
        JP Z,SWAIT0
        LD B,A
        LD HL,(SPTR)
        LD E,A
        LD D,0
        ADD HL,DE
        LD (SPTR),HL
        LD A,(RLEFT)
        SUB B
        LD (RLEFT),A
        JP NZ,SRETRY
        OR A
        RET
SWAIT0  LD HL,(SWAIT)
        DEC HL
        LD (SWAIT),HL
        LD A,H
        OR L
        JP Z,ARGBAD
        LD C,11
        CALL BDOS
        JP SRETRY

 ; Emit a byte through the 16-byte staging buffer (or count pass).
; LENHI:LENLO is the number of IPP body + document bytes.
COUNT1  PUSH HL
        LD HL,(LENLO)
        INC HL
        LD (LENLO),HL
        LD A,H
        OR L
        JP NZ,CTDONE
        LD HL,(LENHI)
        INC HL
        LD (LENHI),HL
CTDONE  POP HL
        RET

; IPP/1.1 Print-Job. All integer lengths are big-endian.
; Data that follows end-of-attributes is the text document.
IPPBODY LD HL,IPPFIX
        LD B,9
IPPF01  LD A,(HL)
        PUSH HL
        PUSH BC
        CALL OUTCHR
        POP BC
        POP HL
        RET C
        INC HL
        DJNZ IPPF01
        LD HL,ATTRCH
        LD B,28
        CALL IPPCOPY
        RET C
        LD HL,ATTRLN
        LD B,37
        CALL IPPCOPY
        RET C
        ; printer-uri = ipp://HOST:631/printers/QUEUE
        LD A,045H
        CALL OUTCHR
        RET C
        LD HL,URIKEY
        LD B,13
        CALL IPPCOPY
        RET C
        LD A,0
        CALL OUTCHR
        RET C
        LD A,(HOSTNAM)
        ; URI length is encoded big-endian (high byte already zero).
        ; STRLEN clobbers B: preserve the partial count in URLCNT.
        LD HL,URIPRE
        CALL STRLEN
        LD (URLCNT),A
        LD HL,HOSTNAM
        CALL STRLEN
        LD B,A
        LD A,(URLCNT)
        ADD A,B
        ADD A,14           ; :631/printers/ = 14 bytes
        LD (URLCNT),A      ; STRLEN overwrites B, save subtotal
        LD HL,(QPTR)
        CALL STRLEN
        LD B,A             ; queue length
        LD A,(URLCNT)      ; prefix + hostname + suffix
        ADD A,B
        CALL OUTCHR
        RET C
        LD HL,URIPRE
        CALL PUTSTR
        RET C
        LD HL,HOSTNAM
        CALL PUTSTR
        RET C
        LD HL,URISUF
        CALL PUTSTR
        RET C
        LD HL,(QPTR)
        CALL PUTSTR
        RET C
        ; Choose MIME type from parsed CP/M FCB extension.
        ; FCB bytes 9..11 are space-padded uppercase extension.
        LD HL,ATTRFM            ; default text/plain
        LD B,30
        LD A,(FCB+9)
        CP 'P'
        JP NZ,IPPFMT
        LD A,(FCB+10)
        CP 'S'
        JP NZ,IPFCHK
        LD A,(FCB+11)
        CP ' '
        JP NZ,IPPFMT
        LD HL,ATTRPS
        LD B,42
        JP IPPFMT
IPFCHK  CP 'D'
        JP NZ,IPPFMT
        LD A,(FCB+11)
        CP 'F'
        JP NZ,IPPFMT
        LD HL,ATTRPDF
        LD B,35
IPPFMT  CALL IPPCOPY
        RET C
        LD A,3
        CALL OUTCHR
        RET
IPPCOPY LD A,B
        OR A
        RET Z
IPPCLOP LD A,(HL)
        PUSH HL
        PUSH BC
        CALL OUTCHR
        POP BC
        POP HL
        RET C
        INC HL
        DJNZ IPPCLOP
        OR A
        RET
STRLEN  LD B,0
STRL01  LD A,(HL)
        OR A
        JP Z,STRLEND
        INC B
        INC HL
        JP STRL01
STRLEND LD A,B
        RET
PUTSTR  LD A,(HL)
        OR A
        RET Z
        PUSH HL
        CALL OUTCHR
        POP HL
        RET C
        INC HL
        JP PUTSTR

; Write HTTP request headers. POST targets /printers/QUEUE.
HTTPHDR LD HL,POST01
        CALL PUTSTR
        RET C
        LD HL,(QPTR)
        CALL PUTSTR
        RET C
        LD HL,POST02
        CALL PUTSTR
        RET C
        LD HL,HOSTNAM
        CALL PUTSTR
        RET C
        LD HL,POST03
        CALL PUTSTR
        RET C
        LD HL,(TOTLO)
        LD DE,(TOTHI)
        CALL DEC32
        RET C
        LD HL,POST04
        CALL PUTSTR
        RET C
        JP FLUSH
; Convert 32-bit DE:HL unsigned decimal, emitting through OUTCHR.
; repeated division by 10, no floating point.
DEC32   LD (DVAL0),HL
        LD (DVAL2),DE
        LD HL,DIGBUF+11
        XOR A
        LD (HL),A
        LD (DIGPTR),HL
D32LOOP LD B,32
        LD C,0
D32DIV  LD HL,DVAL0
        SLA (HL)
        INC HL
        RL (HL)
        INC HL
        RL (HL)
        INC HL
        RL (HL)
        LD A,C
        RLA
        CP 10
        JP C,D32SKIP
        SUB 10
        LD HL,DVAL0
        SET 0,(HL)
D32SKIP LD C,A
        DJNZ D32DIV
        LD A,C
        ADD A,'0'
        LD HL,(DIGPTR)
        DEC HL
        LD (HL),A
        LD (DIGPTR),HL
        LD HL,(DVAL0)
        LD DE,(DVAL2)
        LD A,H
        OR L
        OR D
        OR E
        JP NZ,D32LOOP
        LD HL,(DIGPTR)
        JP PUTSTR

; Read response header bytes until CRLFCRLF, note HTTP status.
; The first response bytes are kept for a short display.
RESPOND LD HL,0
        LD (RXCOUNT),HL
        LD A,0
        LD (CRSTATE),A
        LD (RESPIDX),A
        LD (HTTPSTS),A
        LD HL,30000
        LD (RXWAIT),HL
RXLOOP  LD A,(CURSOCK)
        LD (NXP),A
        LD A,1
        LD (NXP+1),A
        LD A,16
        LD (NXP+2),A
        LD HL,RXBUF
        LD (NXP+3),HL
        LD DE,NXP
        LD C,0FCH
        CALL BDOS
        CP 0FFH
        JP Z,ARGBAD
        OR A
        JP NZ,RXDATA
        CALL FBGET
        CP 017H
        JP Z,RXIDLE
        CP 01CH
        JP Z,RXIDLE
        JP ARGBAD
RXIDLE  LD HL,(RXWAIT)
        DEC HL
        LD (RXWAIT),HL
        LD A,H
        OR L
        JP Z,ARGBAD
        JP RXLOOP
RXDATA  LD B,A
        LD HL,RXBUF
RXBYTE  LD C,(HL)
        LD A,(RESPIDX)
        CP 9
        JP NZ,RXSAVE
        LD A,C
        LD (HTTPSTS),A
RXSAVE  LD A,(RESPIDX)
        CP 255
        JP Z,RXMARK
        INC A
        LD (RESPIDX),A
RXMARK  LD A,C
        CP 13
        JP NZ,RXLF
        LD A,(CRSTATE)
        CP 2
        JP NZ,RXCR1
        LD A,3
        LD (CRSTATE),A
        JP RXNEXT
RXCR1   LD A,1
        LD (CRSTATE),A
        JP RXNEXT
RXLF    CP 10
        JP NZ,RXRESET
        LD A,(CRSTATE)
        CP 3
        JP Z,RXOK
        CP 1
        JP NZ,RXRESET
        LD A,2
        LD (CRSTATE),A
        JP RXNEXT
RXRESET XOR A
        LD (CRSTATE),A
RXNEXT  INC HL
        DJNZ RXBYTE
        JP RXLOOP
RXOK    LD A,(HTTPSTS)
        CP '2'
        JP NZ,ARGBAD
        OR A
        RET

; Header strings do not go into content-length calculation.
; For fixed-length POST we switch count off while emitting headers.
; W5100 socket state CLOSED=00, INIT=13, LISTEN=14, ESTABLISHED=17.
; Listen on source port previously installed by SETTCP.
LISTEN  LD E,1
        CALL FBCMD
        CP 0FFH
        JP Z,ARGBAD
        CALL FBGET
        CP 013H
        JP NZ,ARGBAD
        LD E,2
        CALL FBCMD
        CP 0FFH
        JP Z,ARGBAD
LWAIT   CALL FBGET
        CP 017H
        JP Z,CONOK
        CP 014H
        JP NZ,ARGBAD
        JP LWAIT
 ; Plain-text printer transmitter. CR and LF are normalized to CRLF.
; Uses a 16-byte staging buffer; stops at first CP/M ^Z.
; On disk EOF appends CRLF as in print65.c.
DOSEND  LD DE,FILEBUF
        LD C,26
        CALL BDOS
        XOR A
        LD (OUTCNT),A
        LD (WASCR),A
SNDRD   LD DE,FCB
        LD C,20
        CALL BDOS
        OR A
        JP NZ,SNEOF
        LD HL,FILEBUF
        LD B,128
SNDBYT  LD A,(HL)
        CP 01AH
        JP Z,SNEOF
        PUSH BC
        PUSH HL
        CP 13
        JP Z,SNDCR
        CP 10
        JP Z,SNDLF
        LD C,A
        XOR A
        LD (WASCR),A
        LD A,C
        CALL OUTCHR
        JP SNDDON
SNDCR   LD A,1
        LD (WASCR),A
        LD A,13
        CALL OUTCHR
        JP C,SNDDON
        LD A,10
        CALL OUTCHR
        JP SNDDON
SNDLF   LD A,(WASCR)
        OR A
        JP NZ,SNDSKIP
        LD A,13
        CALL OUTCHR
        JP C,SNDDON
        LD A,10
        CALL OUTCHR
        JP SNDDON
SNDSKIP XOR A
        LD (WASCR),A
        OR A
SNDDON  POP HL
        POP BC
        RET C
        INC HL
        DJNZ SNDBYT
        LD A,(DRYRUN)
        OR A
        JP NZ,SNDRD
        LD A,128
        CALL PROGADD
        JP SNDRD
SNEOF   LD A,13
        CALL OUTCHR
        RET C
        LD A,10
        CALL OUTCHR
        RET C
        CALL FLUSH
        OR A
        RET
 ; Buffer up to 16 bytes. Prepass counts bytes without sending.
OUTCHR  PUSH HL
        PUSH DE
        PUSH BC
        LD C,A
        LD A,(DRYRUN)
        OR A
        JP NZ,OUTCOUNT
        LD A,(INHEADER)
        OR A
        JP NZ,OUTBUF0
OUTCOUNT CALL COUNT1
        LD A,(DRYRUN)
        OR A
        JP NZ,OUTOK
OUTBUF0 LD A,(OUTCNT)
        LD E,A
        LD D,0
        LD HL,OUTBUF
        ADD HL,DE
        LD (HL),C
        LD A,(OUTCNT)
        INC A
        LD (OUTCNT),A
        CP 16
        JP NZ,OUTOK
        CALL FLUSH
        JP OUTEND
OUTOK   OR A
OUTEND  POP BC
        POP DE
        POP HL
        RET
FLUSH   LD A,(DRYRUN)
        OR A
        RET NZ
        LD A,(OUTCNT)
        OR A
        RET Z
        LD HL,OUTBUF
        CALL SENDRAW
        RET C
        XOR A
        LD (OUTCNT),A
        RET
; Read TCP data into the 128-byte CP/M disk buffer.
DORECV  LD DE,FILEBUF
        LD C,26
        CALL BDOS
RCVLP   LD A,(CURSOCK)
        LD (NXP),A
        LD A,1
        LD (NXP+1),A
        LD A,16
        LD (NXP+2),A
        LD HL,RXBUF
        LD (NXP+3),HL
        LD DE,NXP
        LD C,0FCH
        CALL BDOS
        CP 0FFH
        JP Z,ARGBAD
        OR A
        JP NZ,HAVEDAT
        CALL FBGET
        CP 017H
        JP Z,RCVLP
        CP 01CH
        JP Z,ENDRCV
        CP 000H
        JP Z,ENDRCV
        JP ARGBAD
HAVEDAT LD (RCNT),A
        LD A,1
        LD (GOTDATA),A
        LD A,(RCNT)
        CALL PROGADD
        LD A,(RCNT)
        LD B,A
        LD HL,(BYTES)
        LD E,A
        LD D,0
        ADD HL,DE
        LD (BYTES),HL
        LD A,B
        LD HL,RXBUF
RCPLOOP LD A,(HL)
        PUSH HL
        CALL SAVECHR
        POP HL
        RET C
        INC HL
        LD A,(RCNT)
        DEC A
        LD (RCNT),A
        JP NZ,RCPLOOP
        JP RCVLP
ENDRCV  CALL FINFILE
        RET C
        LD A,(GOTDATA)
        OR A
        JP NZ,RCVDONE
        LD DE,EMPTYMSG
        CALL PRINT
RCVDONE
        OR A
        RET
; Progress dot per 1024 successfully transferred bytes.
; Input A = number of bytes (0..255). Preserve all caller registers.
PROGADD PUSH AF
        PUSH BC
        PUSH DE
        PUSH HL
        LD HL,(PROGBY)
        LD E,A
        LD D,0
        ADD HL,DE
        LD A,H
        CP 4
        JP C,PROGSV
        LD DE,0400H
        OR A
        SBC HL,DE
        PUSH HL
        LD A,'.'
        CALL PUTC
        POP HL
PROGSV  LD (PROGBY),HL
        POP HL
        POP DE
        POP BC
        POP AF
        RET

; Print unsigned 16-bit count. No dependence on BDOS preserving registers.
DEC16   LD B,0
DECLOOP LD DE,0
        ; divide HL by 10, quotient in DE, remainder in A.
        PUSH BC
        LD BC,10
D16SUB  OR A
        SBC HL,BC
        JP C,D16END
        INC DE
        JP D16SUB
D16END  ADD HL,BC
        LD A,L
        ADD A,'0'
        POP BC
        PUSH AF
        INC B
        EX DE,HL
        LD A,H
        OR L
        JP NZ,DECLOOP
D16PRT  POP AF
        PUSH BC
        CALL PUTC
        POP BC
        DJNZ D16PRT
        RET

ALCMSG  DEFM 'Allocating socket'
        DEFB 13,10,'$'
SETMSG  DEFM 'TCP socket configured'
        DEFB 13,10,'$'
CNMSG   DEFM 'Connecting...'
        DEFB 13,10,'$'
SNDMSG  DEFM 'Submitting: $'
STATEMSG DEFM 'Socket state: $'
CRLF    DEFB 13,10,'$' 
ARGMSG  DEFM 'Arguments OK'
        DEFB 13,10,'$'
DNSBAD  DEFM 'DNS lookup failed'
        DEFB 13,10,'$'
IPMSG   DEFM 'Bad IPv4 address'
        DEFB 13,10,'$'
PRTMSG  DEFM 'Bad TCP port'
        DEFB 13,10,'$'
NAMMSG  DEFM 'Bad CP/M filename'
        DEFB 13,10,'$'
WAITMSG DEFM 'Listening...'
        DEFB 13,10,'$'
BYTMSG  DEFM 'Received bytes (mod 65536): $'
FIRSTMSG DEFM 'First TCP payload received'
        DEFB 13,10,'$'
EMPTYMSG DEFM 'No TCP payload was received'
        DEFB 13,10,'$'
USAGE   DEFM 'NETIPP host queue file  (CUPS TCP 631)' 
        DEFB 13,10,'$'
OPENMSG DEFM 'Cannot open source file'
        DEFB 13,10,'$'
PREMSG  DEFM 'IPP preflight failed'
        DEFB 13,10,'$'
READMSG DEFM 'Cannot read source file'
        DEFB 13,10,'$'
REOPMSG DEFM 'Cannot reopen source file'
        DEFB 13,10,'$'
FILMSG  DEFM 'File error'
        DEFB 13,10,'$'
NETMSG  DEFM 'Network error'
        DEFB 13,10,'$'
EXISTS  DEFM 'Destination exists'
        DEFB 13,10,'$'
CONMSG  DEFM 'Connected'
        DEFB 13,10,'$'
LISMSG  DEFM 'Receiving: $'
DONEMSG DEFM 'HTTP accepted (check CUPS queue)'
        DEFB 13,10,'$'
; No PCL prefix or suffix: print65.c sends plain text.
 ; IPP header / attributes
IPPFIX  DEFB 1,1,0,2,0,0,0,1,1
; attribute: charset utf-8, 28 bytes
ATTRCH  DEFB 047H,0,18
        DEFM 'attributes-charset'
        DEFB 0,5
        DEFM 'utf-8'
; attribute: natural language en-us (39 bytes)
ATTRLN  DEFB 048H,0,27
        DEFM 'attributes-natural-language'
        DEFB 0,5
        DEFM 'en-us'
URIKEY  DEFB 0,11
        DEFM 'printer-uri'
URIPRE  DEFM 'ipp://'
        DEFB 0
URISUF  DEFM ':631/printers/'
        DEFB 0
; document-format text/plain, 39 bytes? computed below
ATTRFM  DEFB 049H,0,15
        DEFM 'document-format'
        DEFB 0,10
        DEFM 'text/plain'
; PDF and PostScript are MIME types in the IPP body, not HTTP headers.
ATTRPS  DEFB 049H,0,15
        DEFM 'document-format'
        DEFB 0,22
        DEFM 'application/postscript'
ATTRPDF DEFB 049H,0,15
        DEFM 'document-format'
        DEFB 0,15
        DEFM 'application/pdf'
POST01  DEFM 'POST /printers/'
        DEFB 0
POST02  DEFM ' HTTP/1.1'
        DEFB 13,10
        DEFM 'Host: '
        DEFB 0
POST03  DEFB 13,10
        DEFM 'Content-Type: application/ipp'
        DEFB 13,10
        DEFM 'Connection: close'
        DEFB 13,10
        DEFM 'Content-Length: '
        DEFB 0
POST04  DEFB 13,10,13,10,0
; ==== Hardware-proven DNSLIB embedded for single-source assembly ====
; DNSLIB.ASM - Zapple-II Phase 5A reusable DNS A-record resolver.
; Source derived from working NSLOOKUP.COM 0.1 UDP query/ring/parser.
; Public: DNRSLV: HL->NUL-terminated hostname; returns carry clear and
;         DE->DNSADDR (4-byte IPv4) on success, carry set on failure.
;         DNSIP = four-byte DNS server address (default 1.1.1.1).
; Uses BDOS FA (extra UDP socket), FB (W5100 commands), F9 (write bridge).
; All module labels <=8 chars. Slot 5, like existing kernel F9 bridge.
; Designed for direct insertion before application data / stack.
;
DNRSLV  LD (DNHOSTPT),HL
        XOR A
        LD (DNHELD),A
        LD (DNFOUND),A
        CALL DNMAKEQ
        JP C,DNRFAIL
        CALL DNSETPOR
        CALL DNPICK
        JP C,DNRFAIL
        CALL DNUDPOPE
        JP C,DNRFAIL
        CALL DNTXDNS
        JP C,DNRFAIL
        CALL DNRXDNS
        JP C,DNRFAIL
        CALL DNPARSE
        JP C,DNRFAIL
        LD A,(DNFOUND)
        OR A
        JP Z,DNRFAIL
        CALL DNRELEAS
        LD DE,DNSADDR
        OR A
        RET
DNRFAIL CALL DNRELEAS
        SCF
        RET

; DNS header 5AA5 flags 0100 (recursion desired), one A/IN question.
; DEFS is not necessarily zero! Every transmitted byte is written.
DNMAKEQ   LD HL,DNQHEAD
        LD DE,DNQBUF
        LD BC,12
        LDIR
        LD A,12
        LD (DNQCNT),A
        LD HL,(DNHOSTPT)
        LD (DNQSPTR),HL
        LD DE,DNQBUF+12
        CALL DNNEWLAB
DNQLOOP   LD HL,(DNQSPTR)
        LD A,(HL)
        OR A
        JR Z,DNQEND
        CP '.'
        JR Z,DNQDOT
        CP 'A'
        JR C,DNQLOW
        CP 'Z'+1
        JR NC,DNQLOW
        ADD A,32
DNQLOW    CP 'a'
        JR C,DNQDIG
        CP 'z'+1
        JR C,DNQCHAR
DNQDIG    CP '0'
        JR C,DNQDASH
        CP '9'+1
        JR C,DNQCHAR
DNQDASH   CP '-'
        JR NZ,DNQBAD
DNQCHAR   LD B,A
        LD A,(DNQLABL)
        INC A
        CP 64
        JR NC,DNQBAD
        LD (DNQLABL),A
        LD A,B
        CALL DNQPUT
        LD HL,(DNQSPTR)
        INC HL
        LD (DNQSPTR),HL
        JR DNQLOOP
DNQDOT    CALL DNENDLAB
        JR C,DNQBAD
        LD HL,(DNQSPTR)
        INC HL
        LD (DNQSPTR),HL
        LD A,(HL)
        OR A
        JR Z,DNQFIN
        CALL DNNEWLAB
        JR DNQLOOP
DNQEND    CALL DNENDLAB
        JR C,DNQBAD
DNQFIN    XOR A
        CALL DNQPUT
        XOR A
        CALL DNQPUT
        LD A,1
        CALL DNQPUT
        XOR A
        CALL DNQPUT
        LD A,1
        CALL DNQPUT
        OR A
        RET
DNQBAD    SCF
        RET
DNNEWLAB  LD (DNQLBPTR),DE
        XOR A
        LD (DNQLABL),A
        CALL DNQPUT
        RET
DNENDLAB  LD A,(DNQLABL)
        OR A
        JR Z,DNQBAD
        LD HL,(DNQLBPTR)
        LD (HL),A
        OR A
        RET
DNQPUT    LD (DE),A
        INC DE
        PUSH AF
        LD A,(DNQCNT)
        INC A
        LD (DNQCNT),A
        POP AF
        RET

; Slot 5 W5100 IO: verified Z80 native reads and kernel F9 writes.
DNSETPOR LD A,5
        ADD A,A
        ADD A,A
        ADD A,A
        ADD A,A
        ADD A,084H
        LD (DNMOD001+1),A
        INC A
        LD (DNADD003+1),A
        INC A
        LD (DNADD004+1),A
        INC A
        LD (DNDAT001+1),A
        RET
DNMOD001  LD A,(0E0B4H)
        RET
DNDAT001  LD A,(0E0B7H)
        RET
DNADD003  LD (0E0B5H),A
        RET
DNADD004  LD (0E0B6H),A
        RET
DNWSEL    PUSH AF
        LD A,H
        CALL DNADD003
        LD A,L
        CALL DNADD004
        POP AF
        RET
DNWREAD   CALL DNWSEL
        JP DNDAT001
DNWWRITE  PUSH AF
        PUSH BC
        PUSH DE
        PUSH HL
        LD (DNWVAL),A
        LD A,H
        LD (DNWADDR),A
        LD A,L
        LD (DNWADDR+1),A
        LD DE,DNWADDR
        LD C,0F9H
        CALL BDOS
        POP HL
        POP DE
        POP BC
        POP AF
        RET
; Write a selected socket register. B=offset, A=value.
DNWSET    PUSH HL
        PUSH AF
        LD A,(DNSOCKHI)
        LD H,A
        LD L,B
        POP AF
        CALL DNWWRITE
        POP HL
        RET
; Read a selected socket register. A=offset, return A=register.
DNWGET    PUSH HL
        LD L,A
        LD A,(DNSOCKHI)
        LD H,A
        CALL DNWREAD
        POP HL
        RET

DNPICK    LD E,0
        LD C,0FAH
        CALL BDOS
        CP 4
        JR NC,DNPICKER
        LD (DNSOCKNO),A
        ADD A,4
        LD (DNSOCKHI),A
        LD A,1
        LD (DNHELD),A
        OR A
        RET
DNPICKER SCF
        RET
DNRELEAS LD A,(DNHELD)
        OR A
        RET Z
        XOR A
        LD (DNHELD),A
        LD A,(DNSOCKNO)
        LD D,A
        LD E,1
        LD C,0FAH
        CALL BDOS
        RET
; FB: E=W5100 command, or 0 to read status. Ownership checked.
DNFBCMD   LD A,(DNSOCKNO)
        LD D,A
        LD C,0FBH
        CALL BDOS
        RET
DNFBGET   LD E,0
        CALL DNFBCMD
        RET

DNUDPOPE LD A,0
        CALL DNFBGET
        CP 0
        JR NZ,DNUDPBAD
        LD B,0
        LD A,2
        CALL DNWSET
        LD B,4
        LD A,0D3H
        CALL DNWSET
        LD B,5
        LD A,(DNSOCKNO)
        ADD A,051H
        CALL DNWSET
        LD B,0CH
        LD A,(DNSIP)
        CALL DNWSET
        LD B,0DH
        LD A,(DNSIP+1)
        CALL DNWSET
        LD B,0EH
        LD A,(DNSIP+2)
        CALL DNWSET
        LD B,0FH
        LD A,(DNSIP+3)
        CALL DNWSET
        LD B,10H
        XOR A
        CALL DNWSET
        LD B,11H
        LD A,35H
        CALL DNWSET
        LD B,0
        LD A,2
        CALL DNWSET
        LD E,1
        CALL DNFBCMD
        CP 0FFH
        JR Z,DNUDPBAD
        CALL DNFBGET
        CP 22H
        JR NZ,DNUDPBAD
        OR A
        RET
DNUDPBAD  SCF
        RET

; Compute TX or RX ring base and mask from live TMSR/RMSR.
; Input A=memory allocation register offset (1Bh TX, 1Ah RX).
; C=base page 40h (TX) or 60h (RX).
DNRINGSE LD (DNMEMREG),A
        LD A,C
        LD (DNRBASE),A
        LD A,(DNMEMREG)
        LD L,A
        LD H,0
        CALL DNWREAD
        LD B,A
        LD A,(DNSOCKNO)
        LD C,A
DNRINGLP  LD A,C
        OR A
        JR Z,DNRINGCU
        LD A,B
        AND 3
        CALL DNSIZPAG
        LD D,A
        LD A,(DNRBASE)
        ADD A,D
        LD (DNRBASE),A
        LD A,B
        RRCA
        RRCA
        LD B,A
        DEC C
        JR DNRINGLP
DNRINGCU LD A,B
        AND 3
        CALL DNSIZPAG
        DEC A
        LD (DNRMASK),A
        LD D,A
        LD A,(DNRBASE)
        AND 01FH
        ADD A,D
        CP 32
        JR NC,DNRINGBA
        OR A
        RET
DNRINGBA SCF
        RET
DNSIZPAG LD E,A
        LD D,0
        LD HL,DNSZTAB
        ADD HL,DE
        LD A,(HL)
        RET
; DNPTRHI/DNPTRLO are full 16-bit W5100 hardware ring pointers.
; Input A=socket register offset of pointer's high byte.
DNGETPTR  CALL DNWGET
        LD (DNPTRHI),A
        LD A,(DNREGPTR)
        INC A
        CALL DNWGET
        LD (DNPTRLO),A
        RET
DNSETPTR  LD A,(DNREGPTR)
        LD B,A
        LD A,(DNPTRHI)
        CALL DNWSET
        LD A,(DNREGPTR)
        INC A
        LD B,A
        LD A,(DNPTRLO)
        CALL DNWSET
        RET
DNRADDR   PUSH BC
        LD A,(DNPTRHI)
        LD B,A
        LD A,(DNRMASK)
        AND B
        LD B,A
        LD A,(DNRBASE)
        ADD A,B
        LD H,A
        LD A,(DNPTRLO)
        LD L,A
        POP BC
        RET
DNINCPTR  LD A,(DNPTRLO)
        INC A
        LD (DNPTRLO),A
        RET NZ
        LD A,(DNPTRHI)
        INC A
        LD (DNPTRHI),A
        RET
DNRINGWR  PUSH AF
        CALL DNRADDR
        POP AF
        CALL DNWWRITE
        CALL DNINCPTR
        RET
DNRINGRD  CALL DNRADDR
        CALL DNWREAD
        PUSH AF
        CALL DNINCPTR
        POP AF
        RET

; Transmit DNS query as ONE UDP datagram, never through chunked FC.
DNTXDNS   LD A,1BH
        LD C,40H
        CALL DNRINGSE
        JP C,DNTXFAIL
        LD A,20H
        CALL DNWGET
        OR A
        JR NZ,DNTXSPAC
        LD A,21H
        CALL DNWGET
        LD B,A
        LD A,(DNQCNT)
        CP B
        JR C,DNTXSPAC
        JR Z,DNTXSPAC
        SCF
        RET
DNTXSPAC LD A,24H
        LD (DNREGPTR),A
        CALL DNGETPTR
        LD HL,DNQBUF
        LD A,(DNQCNT)
        LD B,A
DNTXLOOP  LD A,(HL)
        PUSH HL
        CALL DNRINGWR
        POP HL
        INC HL
        DJNZ DNTXLOOP
        CALL DNSETPTR
        LD B,2
        LD A,18H
        CALL DNWSET
        LD E,20H
        CALL DNFBCMD
        CP 0FFH
        JR Z,DNTXFAIL
        LD HL,30000
DNTXWAIT  PUSH HL
        LD A,2
        CALL DNWGET
        POP HL
        AND 18H
        CP 10H
        JR Z,DNTXOK
        CP 08H
        JR Z,DNTXFAIL
        DEC HL
        LD A,H
        OR L
        JR Z,DNTXFAIL
        JR DNTXWAIT
DNTXOK    OR A
        RET
DNTXFAIL  SCF
        RET

; Receive one UDP datagram. W5100 adds 8-byte metadata header.
; DNRXBUF starts with source IP (4), source port (2), packet length (2).
DNRXDNS   LD HL,50000
DNRXWAIT  PUSH HL
        LD A,26H
        CALL DNWGET
        LD (DNAVHIGH),A
        LD A,27H
        CALL DNWGET
        LD (DNAVLOW),A
        POP HL
        LD A,(DNAVHIGH)
        OR A
        JR NZ,DNRXREAD
        LD A,(DNAVLOW)
        CP 8
        JR NC,DNRXREAD
        DEC HL
        LD A,H
        OR L
        JP Z,DNRXFAIL
        JR DNRXWAIT
DNRXREAD LD A,1AH
        LD C,60H
        CALL DNRINGSE
        JP C,DNRXFAIL
        LD A,28H
        LD (DNREGPTR),A
        CALL DNGETPTR
        LD HL,DNRXBUF
        LD BC,8
        CALL DNREADN
        LD A,(DNRXBUF+6)
        CP 2
        JR C,DNRXSIZE
        JP NZ,DNRXFAIL
        LD A,(DNRXBUF+7)
        OR A
        JP NZ,DNRXFAIL
DNRXSIZE  LD A,(DNRXBUF+6)
        LD B,A
        LD A,(DNRXBUF+7)
        LD C,A
        LD (DNDLEN),BC
        ; Confirm W5100 reports the complete 8-byte header plus payload.
        LD A,C
        ADD A,8
        LD C,A
        LD A,B
        ADC A,0
        LD B,A
        LD A,(DNAVHIGH)
        CP B
        JP C,DNRXFAIL
        JR NZ,DNRXAVOK
        LD A,(DNAVLOW)
        CP C
        JP C,DNRXFAIL
DNRXAVOK  LD BC,(DNDLEN)
        ; Discard packets not sent by the requested resolver on UDP/53.
        LD HL,DNRXBUF
        LD DE,DNSIP
        LD B,4
DNRXSRC   LD A,(DE)
        CP (HL)
        JP NZ,DNRXFAIL
        INC DE
        INC HL
        DJNZ DNRXSRC
        LD A,(DNRXBUF+4)
        OR A
        JP NZ,DNRXFAIL
        LD A,(DNRXBUF+5)
        CP 35H
        JP NZ,DNRXFAIL
        LD BC,(DNDLEN)
        LD A,B
        OR A
        JR NZ,DNRXBODY
        LD A,C
        CP 12
        JR C,DNRXFAIL
DNRXBODY  LD HL,DNRXBUF+8
        LD BC,(DNDLEN)
        CALL DNREADN
        CALL DNSETPTR
        LD E,40H
        CALL DNFBCMD
        CP 0FFH
        JP Z,DNRXFAIL
        OR A
        RET
DNRXFAIL  SCF
        RET
; Read BC bytes into HL, reading the selected W5100 RX ring.
DNREADN   LD A,B
        OR C
        RET Z
        PUSH BC
        PUSH HL
        CALL DNRINGRD
        POP HL
        LD (HL),A
        INC HL
        POP BC
        DEC BC
        JR DNREADN

; Packet parse: check ID, QR, RCODE, QDCOUNT; skip compressed names.
DNPARSE   LD A,(DNSBUF)
        CP 05AH
        JP NZ,DNDNFAIL
        LD A,(DNSBUF+1)
        CP 0A5H
        JP NZ,DNDNFAIL
        LD A,(DNSBUF+2)
        AND 80H
        JP Z,DNDNFAIL
        LD A,(DNSBUF+2)
        AND 02H                 ; TC: truncated UDP response
        JP NZ,DNDNFAIL
        LD A,(DNSBUF+3)
        AND 0FH
        JR Z,DNRCOK
        SCF
        RET
DNRCOK    LD A,(DNSBUF+4)
        OR A
        JP NZ,DNDNFAIL
        LD A,(DNSBUF+5)
        CP 1
        JP NZ,DNDNFAIL
        LD HL,DNSBUF
        LD BC,(DNDLEN)
        ADD HL,BC
        LD (DNENDPTR),HL
        LD HL,DNSBUF+12
        CALL DNSKNAME
        JP C,DNDNFAIL
        LD DE,4
        ADD HL,DE
        CALL DNCHEC01
        JP C,DNDNFAIL
        LD A,(DNSBUF+6)
        OR A
        JP NZ,DNDNFAIL
        LD A,(DNSBUF+7)
        LD (DNANLEFT),A
DNANLOOP  LD A,(DNANLEFT)
        OR A
        JP Z,DNANEND
        CALL DNSKNAME
        JP C,DNDNFAIL
        PUSH HL
        LD DE,10
        ADD HL,DE
        CALL DNCHEC01
        POP HL
        JP C,DNDNFAIL
        LD A,(HL)
        LD (DNRTYPE),A
        INC HL
        LD A,(HL)
        LD (DNRTYPE+1),A
        INC HL
        LD A,(HL)
        LD (DNRCLASS),A
        INC HL
        LD A,(HL)
        LD (DNRCLASS+1),A
        INC HL
        LD DE,4
        ADD HL,DE
        LD A,(HL)
        LD (DNRLENH),A
        INC HL
        LD A,(HL)
        LD (DNRLENL),A
        INC HL
        LD (DNRDPTR),HL
        LD A,(DNRLENH)
        LD B,A
        LD A,(DNRLENL)
        LD C,A
        ADD HL,BC
        CALL DNCHEC01
        JP C,DNDNFAIL
        LD (DNNEXTAD),HL
        LD A,(DNRTYPE)
        OR A
        JR NZ,DNANMORE
        LD A,(DNRTYPE+1)
        CP 1
        JR NZ,DNANMORE
        LD A,(DNRCLASS)
        OR A
        JR NZ,DNANMORE
        LD A,(DNRCLASS+1)
        CP 1
        JR NZ,DNANMORE
        LD A,(DNRLENH)
        OR A
        JR NZ,DNANMORE
        LD A,(DNRLENL)
        CP 4
        JR NZ,DNANMORE
        LD A,(DNFOUND)
        OR A
        JR NZ,DNPRTANS
        LD HL,(DNRDPTR)
        LD DE,DNSADDR
        LD BC,4
        LDIR                     ; preserve first A record for future callers
DNPRTANS  LD A,(DNFOUND)
        INC A
        LD (DNFOUND),A
DNANMORE  LD HL,(DNNEXTAD)
        LD A,(DNANLEFT)
        DEC A
        LD (DNANLEFT),A
        JP DNANLOOP
DNANEND   LD A,(DNFOUND)
        OR A
        RET NZ
        SCF
        RET
DNDNFAIL  SCF
        RET
; Consume QNAME/RR name at HL without following compression pointers.
DNSKNAME  LD B,40
DNSKLOOP  CALL DNCHECKL
        RET C
        LD A,(HL)
        OR A
        JR Z,DNSKZERO
        LD C,A
        AND 0C0H
        CP 0C0H
        JR Z,DNSKCOMP
        OR A
        JR NZ,DNSKBAD
        LD A,C
        CP 64
        JR NC,DNSKBAD
        LD E,A
        LD D,0
        INC HL
        ADD HL,DE
        CALL DNCHEC01
        RET C
        DJNZ DNSKLOOP
DNSKBAD   SCF
        RET
DNSKZERO  INC HL
        OR A
        RET
DNSKCOMP  INC HL
        CALL DNCHECKL
        RET C
        INC HL
        OR A
        RET
; Check HL < or <= DNENDPTR. No external pointer dereference.
DNCHECKL PUSH DE
        LD DE,(DNENDPTR)
        LD A,H
        CP D
        JR C,DNCLGOOD
        JR NZ,DNCLBAD
        LD A,L
        CP E
        JR C,DNCLGOOD
DNCLBAD   POP DE
        SCF
        RET
DNCLGOOD  POP DE
        OR A
        RET
DNCHEC01 PUSH DE
        LD DE,(DNENDPTR)
        LD A,H
        CP D
        JR C,DNCEGOOD
        JR NZ,DNCEBAD
        LD A,L
        CP E
        JR C,DNCEGOOD
        JR Z,DNCEGOOD
DNCEBAD   POP DE
        SCF
        RET
DNCEGOOD  POP DE
        OR A
        RET

DNQHEAD   DEFB 05AH,0A5H,1,0,0,1,0,0,0,0,0,0
DNSZTAB   DEFB 4,8,16,32
DNSIP   DEFB 1,1,1,1
DNHELD    DEFB 0
DNSOCKNO  DEFB 0
DNSOCKHI  DEFB 0
DNFOUND   DEFB 0
DNSADDR DEFB 0,0,0,0
DNQCNT    DEFB 0
DNQLABL   DEFB 0
DNHOSTPT DEFW 0
DNQSPTR   DEFW 0
DNQLBPTR  DEFW 0
DNWADDR   DEFB 0,0
DNWVAL    DEFB 0
DNMEMREG  DEFB 0
DNRBASE   DEFB 0
DNRMASK   DEFB 0
DNREGPTR  DEFB 0
DNPTRHI   DEFB 0
DNPTRLO   DEFB 0
DNAVHIGH  DEFB 0
DNAVLOW   DEFB 0
DNDLEN    DEFW 0
DNENDPTR  DEFW 0
DNANLEFT  DEFB 0
DNRTYPE   DEFB 0,0
DNRCLASS  DEFB 0,0
DNRLENH   DEFB 0
DNRLENL   DEFB 0
DNRDPTR   DEFW 0
DNNEXTAD DEFW 0
DNCMDTXT  DEFS 128
DNQBUF    DEFS 256
DNRXBUF   DEFS 520
DNSBUF  EQU DNRXBUF+8


; Runtime DNS configuration from Zapple-II kernel, same as FTP.COM.
DNSINIT LD D,0
        LD HL,DNSIP
DNILP   PUSH HL
        PUSH DE
        LD E,6
        LD C,0FDH
        CALL BDOS
        POP DE
        POP HL
        LD (HL),A
        INC HL
        INC D
        LD A,D
        CP 4
        JR NZ,DNILP
        RET

VARS0
QPTR    DEFW 0
DRYRUN  DEFB 0
INHEADER DEFB 0
LENLO   DEFW 0
LENHI   DEFW 0
TOTLO   DEFW 0
TOTHI   DEFW 0
URLCNT  DEFB 0
DVAL0   DEFW 0
DVAL2   DEFW 0
DIGBUF  DEFS 12
DIGPTR  DEFW 0
RXCOUNT DEFW 0
RXWAIT  DEFW 0
CRSTATE DEFB 0
RESPIDX DEFB 0
HTTPSTS DEFB 0
HOSTNAM DEFS 64
CMDTXT  DEFS 128
TOKENS  DEFS 12
TCOUNT  DEFB 0
HOSTIP  DEFS 4
NDIG    DEFB 0
DIGIT   DEFB 0
PORT21  DEFB 0,0
FCB     DEFS 36
FILEBUF DEFS 128
OUTBUF  DEFS 16
OUTCNT  DEFB 0
WASCR   DEFB 0
FILEOP  DEFB 0
FIDX    DEFB 0
SAVEB   DEFB 0
ERRCODE DEFB 0
SERVER  DEFB 0
CSOCK   DEFB 0
CHELD   DEFB 0
DSOCK   DEFB 0
DHELD   DEFB 0
CURSOCK DEFB 0
DESTIP  DEFW 0
DESTPRT DEFW 0
OUTPTR  DEFW 0
WPAR    DEFS 2
WVAL    DEFB 0
NXP     DEFS 5
RXBUF   DEFS 16
RCNT    DEFB 0
GOTDATA DEFB 0
BYTES   DEFW 0
PROGBY  DEFW 0
SPTR    DEFW 0
RLEFT   DEFB 0
SWAIT   DEFW 0
VARS1
        DEFS 128
STKTOP
