; FTP.COM v0.2c - independent control/data receive buffers
; Passive FTP client: GET, PUT, DIR. Binary (TYPE I), FTP plaintext only.
; Usage: FTP host[:port] GET remote local [user [password]]
;        FTP host[:port] PUT local remote [user [password]]
;        FTP host[:port] DIR path [user [password]]
; User only, or password of ? or *, prompts for case-sensitive password.
; Username ? prompts for case-sensitive username.
; Command-tail arguments are uppercased by CP/M CCP.
; Defaults to anonymous login. Port defaults to 21.
; DNSLIB is copied verbatim from the hardware-proven NSLOOKUP resolver.
; Existing BDOS F9, FA, FB, FC - no kernel modifications.
; CP/M files are 128-byte records. GET pads the final record with 1Ah.
; PUT transmits the entire last 128-byte record, including CP/M padding.
; Credentials and payload are NOT encrypted. No FTPS or SFTP.
; Udo Munk Z80ASM. Labels <= 8 significant characters.
BDOS    EQU 0005H
        ORG 0100H
START   LD SP,STKTOP
        LD HL,VARS0
        LD BC,VARS1-VARS0
VCLEAR  XOR A
        LD (HL),A
        INC HL
        DEC BC
        LD A,B
        OR C
        JP NZ,VCLEAR
        LD A,21
        LD (PORT21+1),A
        LD DE,BANNER
        CALL PRINT
        CALL GETARG
        JP C,USGERR
        CALL PARHOST
        JP C,HOSTERR
        CALL PARACT
        JP C,USGERR
        CALL CKFILE
        JP C,FILERR
        CALL DNSHOST
        JP C,DNSERR
        CALL ALCCTL
        JP C,NETERR
        LD A,(CSOCK)
        LD (CURSOCK),A
        LD HL,HOSTIP
        LD (DESTIP),HL
        LD HL,PORT21
        LD (DESTPRT),HL
        CALL SETTCP
        CALL CONNEC
        JP C,NETERR
        CALL LOGIN
        JP C,FTPERR
        CALL OPENDAT
        JP C,FTPERR
        CALL DOXFER
        JP C,FTPERR
        LD DE,FINMSG
        CALL PRINT
        JP CLEAN
USGERR  LD DE,USAGE
        JP FAIL
HOSTERR LD DE,BADHOST
        JP FAIL
FILERR  LD DE,BADFILE
        JP FAIL
DNSERR  LD DE,BADDNS
        JP FAIL
NETERR  LD DE,BADNET
        JP FAIL
FTPERR  LD DE,BADFTP
FAIL    CALL PRINT
CLEAN   CALL CLOSEF
        LD A,(DHELD)
        OR A
        JP Z,CLCTL
        LD A,(DSOCK)
        CALL FREEONE
        XOR A
        LD (DHELD),A
CLCTL   LD A,(CHELD)
        OR A
        JP Z,QUIT
        LD A,(CSOCK)
        CALL FREEONE
QUIT    LD C,0
        JP BDOS

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
        CP 2
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

; HOST[:port] copies hostname to private buffer (max 63 chars).
PARHOST LD HL,(TOKENS)
        LD DE,HOSTNAM
        LD B,63
HOSTCP  LD A,(HL)
        OR A
        JP Z,HOSTEND
        CP ':'
        JP Z,HPORT
        LD (DE),A
        INC HL
        INC DE
        DJNZ HOSTCP
        SCF
        RET
HPORT   XOR A
        LD (DE),A
        INC HL
        CALL GETPORT
        RET C
        JP HEND2
HOSTEND XOR A
        LD (DE),A
HEND2   LD A,(HOSTNAM)
        OR A
        JP Z,ARGBAD
        LD HL,HOSTNAM
        LD DE,HOSTIP
        LD B,4
HIPS    PUSH BC
        PUSH DE
        CALL OCTET
        POP DE
        POP BC
        JP C,ISHOST
        LD (DE),A
        INC DE
        DEC B
        JP Z,HLAST
        LD A,(HL)
        CP '.'
        JP NZ,ISHOST
        INC HL
        JP HIPS
HLAST   LD A,(HL)
        OR A
        JP NZ,ISHOST
        XOR A
        LD (NEEDDNS),A
        RET
ISHOST  LD A,1
        LD (NEEDDNS),A
        OR A
        RET
ARGBAD  SCF
        RET
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
DNSHOST LD A,(NEEDDNS)
        OR A
        RET Z
        LD DE,DNSMSG
        CALL PRINT
        LD HL,HOSTNAM
        CALL DNRSLV
        RET C
        EX DE,HL
        LD DE,HOSTIP
        LD BC,4
        LDIR
        OR A
        RET

; Syntax: host GET remote local [user password], etc.
PARACT  LD A,(TCOUNT)
        CP 2
        JP Z,DIR2
        CP 5
        JP Z,ARG5
        CP 6
        JP Z,ARG6
        CP 4
        JP Z,ARG4
        CP 3
        JP NZ,ARGBAD
        LD HL,(TOKENS+2)
        LD DE,CMDDIR
        CALL STREQ
        JP NZ,ARGBAD
        LD A,3
        LD (MODE),A
        LD HL,(TOKENS+4)
        LD (REMOTE),HL
        LD HL,ANON
        LD (UNAME),HL
        LD HL,ANONPWD
        LD (PASSWD),HL
        OR A
        RET
DIR2    LD HL,(TOKENS+2)
        LD DE,CMDDIR
        CALL STREQ
        JP NZ,ARGBAD
        LD A,3
        LD (MODE),A
        LD HL,DOTSTR
        LD (REMOTE),HL
        LD HL,ANON
        LD (UNAME),HL
        LD HL,ANONPWD
        LD (PASSWD),HL
        OR A
        RET
DIR5    LD HL,(TOKENS+2)
        LD DE,CMDDIR
        CALL STREQ
        JP NZ,ARGBAD
        LD A,3
        LD (MODE),A
        LD HL,(TOKENS+4)
        LD (REMOTE),HL
        LD HL,(TOKENS+6)
        LD (UNAME),HL
        LD HL,(TOKENS+8)
        LD (PASSWD),HL
        JP FIXPASS
; With four tokens, DIR path user prompts for password.
; With GET/PUT, four tokens are the anonymous forms.
ARG4    LD HL,(TOKENS+2)
        LD DE,CMDDIR
        CALL STREQ
        JP NZ,ARG4GP
        LD A,3
        LD (MODE),A
        LD HL,(TOKENS+4)
        LD (REMOTE),HL
        LD HL,(TOKENS+6)
        LD (UNAME),HL
        JP PRMPASS
ARG4GP  LD HL,(TOKENS+2)
        LD DE,CMDGET
        CALL STREQ
        JP Z,AGET
        LD HL,(TOKENS+2)
        LD DE,CMDPUT
        CALL STREQ
        JP NZ,ARGBAD
        LD A,2
        JP SETOP
AGET    LD A,1
SETOP   LD (MODE),A
        CP 2
        JP Z,PUTPTR
        LD HL,(TOKENS+4)
        LD (REMOTE),HL
        LD HL,(TOKENS+6)
        LD (LOCAL),HL
        JP ANPTR
PUTPTR  LD HL,(TOKENS+6)
        LD (REMOTE),HL
        LD HL,(TOKENS+4)
        LD (LOCAL),HL
ANPTR   LD HL,ANON
        LD (UNAME),HL
        LD HL,ANONPWD
        LD (PASSWD),HL
        OR A
        RET
ARG6    LD HL,(TOKENS+2)
        LD DE,CMDGET
        CALL STREQ
        JP Z,AGET6
        LD HL,(TOKENS+2)
        LD DE,CMDPUT
        CALL STREQ
        JP Z,APUT6
        JP ARGBAD
AGET6   LD A,1
        JP SET6
APUT6   LD A,2
SET6    LD (MODE),A
        CP 2
        JP Z,PUT6PTR
        LD HL,(TOKENS+4)
        LD (REMOTE),HL
        LD HL,(TOKENS+6)
        LD (LOCAL),HL
        JP CREDS6
PUT6PTR LD HL,(TOKENS+6)
        LD (REMOTE),HL
        LD HL,(TOKENS+4)
        LD (LOCAL),HL
CREDS6  LD HL,(TOKENS+8)
        LD (UNAME),HL
        LD HL,(TOKENS+10)
        LD (PASSWD),HL
        JP FIXPASS
; Five tokens: DIR path user password, or GET/PUT remote local user.
ARG5    LD HL,(TOKENS+2)
        LD DE,CMDDIR
        CALL STREQ
        JP Z,DIR5
        LD HL,(TOKENS+2)
        LD DE,CMDGET
        CALL STREQ
        JP Z,AGET5
        LD HL,(TOKENS+2)
        LD DE,CMDPUT
        CALL STREQ
        JP NZ,ARGBAD
        LD A,2
        JP SET5
AGET5   LD A,1
SET5    CALL SETOP
        LD HL,(TOKENS+8)
        LD (UNAME),HL
; A password entered via the CCP is always uppercased. Prompt instead.
PRMPASS LD HL,PWBUF
        LD (PASSWD),HL
        LD A,1
        LD (PWPROM),A
        OR A
        RET
; Backward compatible explicit password, except ? or * asks interactively.
FIXPASS LD HL,(PASSWD)
        LD A,(HL)
        CP '?'
        JP Z,FIXPW1
        CP '*'
        JP NZ,FIXPWOK
FIXPW1  INC HL
        LD A,(HL)
        OR A
        JP NZ,FIXPWOK
        JP PRMPASS
FIXPWOK OR A
        RET

; FCB always initialized, regardless of DEFS contents.
CKFILE  LD A,(MODE)
        CP 3
        RET Z
        LD HL,(LOCAL)
        LD (OUTPTR),HL
        CALL FPAR
        RET C
        LD A,(MODE)
        CP 1
        JP Z,CHECKEX
        LD DE,FCB
        LD C,15
        CALL BDOS
        CP 0FFH
        JP Z,ARGBAD
        LD A,1
        LD (FILEOP),A
        OR A
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
        LD DE,FCB+1
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
        SCF
        RET
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
        JP Z,ARGBAD
        LD A,1
        LD (FILEOP),A
        LD DE,FILEBUF
        LD C,26
        CALL BDOS
        OR A
        RET
WRREC   LD DE,FILEBUF
        LD C,26
        CALL BDOS
        LD DE,FCB
        LD C,21
        CALL BDOS
        OR A
        RET Z
        SCF
        RET
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

; FA allocate two sockets, FB commands/status, F9 register writes.
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
; Sends NUL-terminated string in 16-byte batches.
SENDSTR LD (STRPTR),HL
SSTRLP LD HL,(STRPTR)
        LD A,(HL)
        OR A
        RET Z
        LD DE,TXBUF
        LD B,16
SCPY    LD A,(HL)
        OR A
        JP Z,SCEND
        LD (DE),A
        INC HL
        INC DE
        DJNZ SCPY
SCEND   LD A,16
        SUB B
        LD (TXLEN),A
        LD HL,TXBUF
        CALL SENDRAW
        RET C
        LD HL,(STRPTR)
        LD A,(TXLEN)
        LD E,A
        LD D,0
        ADD HL,DE
        LD (STRPTR),HL
        JP SSTRLP
; Send prefix (HL), a string pointed by (CMDARG), and CRLF.
CMDARG0 CALL SENDSTR
        RET C
        LD HL,(CMDARG)
        CALL SENDSTR
        RET C
        LD HL,CRLF0
        JP SENDSTR
CMDSIMP CALL SENDSTR
        RET C
        LD HL,CRLF0
        JP SENDSTR
; Receive a batch on selected socket. A=length/0/FF.
READ16  LD A,(CURSOCK)
        LD (NXP),A
        LD A,1
        LD (NXP+1),A
        LD A,16
        LD (NXP+2),A
        LD HL,RXBUF
        LD (NXP+3),HL
        LD DE,NXP
        LD C,0FCH
        JP BDOS
; Control-char stream, A=next byte carry clear. C set on error/close.
CTLGET  LD A,(RXCNT)
        OR A
        JP Z,CTLFILL
        LD HL,CRXBUF
        LD A,(RXIDX)
        LD E,A
        LD D,0
        ADD HL,DE
        LD A,(HL)
        LD (CTLSAVE),A
        LD A,(RXIDX)
        INC A
        LD (RXIDX),A
        LD A,(RXCNT)
        DEC A
        LD (RXCNT),A
        LD A,(CTLSAVE)
        OR A
        RET
CTLFILL LD HL,30000
        LD (IDLE),HL
CTRLTRY LD A,(CSOCK)
        LD (CURSOCK),A
        CALL CTLREAD
        CP 0FFH
        JP Z,ARGBAD
        OR A
        JP NZ,CTLNEW
        CALL FBGET
        CP 017H
        JP NZ,ARGBAD
        LD HL,(IDLE)
        DEC HL
        LD (IDLE),HL
        LD A,H
        OR L
        JP Z,ARGBAD
        LD C,11
        CALL BDOS
        JP CTRLTRY
CTLNEW  LD (RXCNT),A
        XOR A
        LD (RXIDX),A
        JP CTLGET
; FTP response: consume multiline replies, echo complete lines.
READLN  LD HL,RPLINE
        LD (RLPTR),HL
LINLOOP CALL CTLGET
        RET C
        CP 13
        JP Z,LINLOOP
        CP 10
        JP Z,LINEEND
        LD B,A
        LD HL,(RLPTR)
        LD DE,RPLINE+140
        LD A,H
        CP D
        JP C,ADDCHAR
        JP NZ,LINLOOP
        LD A,L
        CP E
        JP NC,LINLOOP
ADDCHAR LD (HL),B
        INC HL
        LD (RLPTR),HL
        JP LINLOOP
LINEEND LD HL,(RLPTR)
        LD (HL),'$'
        LD DE,RPLINE
        CALL PRINT
        LD DE,NL
        CALL PRINT
        OR A
        RET
READREP XOR A
        LD (MULTI),A
REPLOOP CALL READLN
        RET C
        LD A,(RPLINE)
        CP '1'
        JP C,REPLOOP
        CP '5'+1
        JP NC,REPLOOP
        LD A,(RPLINE+1)
        CP '0'
        JP C,REPLOOP
        CP '9'+1
        JP NC,REPLOOP
        LD A,(RPLINE+2)
        CP '0'
        JP C,REPLOOP
        CP '9'+1
        JP NC,REPLOOP
        LD A,(MULTI)
        OR A
        JP NZ,RMULTI
        LD A,(RPLINE+3)
        CP '-'
        JP Z,RMSTART
        CP ' '
        JP NZ,REPLOOP
        JP REPDONE
RMSTART LD HL,RPLINE
        LD DE,MULTCOD
        LD BC,3
        LDIR
        LD A,1
        LD (MULTI),A
        JP REPLOOP
RMULTI LD HL,RPLINE
        LD DE,MULTCOD
        LD B,3
RMCMP   LD A,(DE)
        CP (HL)
        JP NZ,REPLOOP
        INC DE
        INC HL
        DJNZ RMCMP
        LD A,(RPLINE+3)
        CP ' '
        JP NZ,REPLOOP
REPDONE LD A,(RPLINE)
        SUB '0'
        OR A
        RET
; Read reply, succeed only for class 2, else carry set.
EXPECT2 CALL READREP
        RET C
        CP 2
        JP NZ,ARGBAD
        OR A
        RET
EXPECT1 CALL READREP
        RET C
        CP 1
        JP NZ,ARGBAD
        OR A
        RET
; Send command line then read reply. Selected socket must be control.
SENDCMD CALL CMDARG0
        RET C
        JP READREP
SIMPLE  CALL CMDSIMP
        RET C
        JP READREP

; Interactive case-sensitive credentials.  CCP has already uppercased
; its command tail; BDOS 6 E=FF reads raw console bytes without echo.
; For username ' ?', echo manually; password never echoes.
ASKUSER LD HL,(UNAME)
        LD A,(HL)
        CP '?'
        JP Z,ASKUYES
        OR A
        RET
ASKUYES INC HL
        LD A,(HL)
        OR A
        RET NZ
        LD HL,USRBUF
        LD (UNAME),HL
        LD A,1
        LD (INPECHO),A
        LD DE,USRMSG
        JP INPSTR
ASKPASS XOR A
        LD (INPECHO),A
        LD DE,PASMSG
        LD HL,PWBUF
        JP INPSTR
; DE = $-terminated prompt, HL -> 65-byte destination.
; Ctrl-C/Esc cancels; backspace/delete edits; return terminates.
; B holds remaining capacity; original start is in INPBASE.
INPSTR  LD (INPBASE),HL
        PUSH HL
        CALL PRINT
        POP HL
        LD B,64
INPLOOP PUSH HL
        PUSH BC
        LD C,6
        LD E,0FFH
        CALL BDOS
        POP BC
        POP HL
        OR A
        JP Z,INPLOOP
        CP 0DH
        JP Z,INPDONE
        CP 0AH
        JP Z,INPLOOP
        CP 03H
        JP Z,INPABRT
        CP 1BH
        JP Z,INPABRT
        CP 08H
        JP Z,INPBACK
        CP 7FH
        JP Z,INPBACK
        CP ' '
        JP C,INPLOOP
        CP 7FH
        JP NC,INPLOOP
        LD C,A
        LD A,B
        OR A
        JP Z,INPLOOP
        LD A,C
        LD (HL),A
        INC HL
        DEC B
        LD A,(INPECHO)
        OR A
        JP Z,INPLOOP
        LD A,C
        PUSH HL
        PUSH BC
        CALL PUTC
        POP BC
        POP HL
        JP INPLOOP
INPBACK LD A,B
        CP 64
        JP Z,INPLOOP
        DEC HL
        INC B
        XOR A
        LD (HL),A
        LD A,(INPECHO)
        OR A
        JP Z,INPLOOP
        PUSH HL
        PUSH BC
        LD A,08H
        CALL PUTC
        LD A,' '
        CALL PUTC
        LD A,08H
        CALL PUTC
        POP BC
        POP HL
        JP INPLOOP
INPDONE LD (HL),0
        LD DE,NL
        CALL PRINT
        OR A
        RET
INPABRT LD HL,(INPBASE)
        LD B,65
        XOR A
INPZERO LD (HL),A
        INC HL
        DJNZ INPZERO
        LD DE,NL
        CALL PRINT
        SCF
        RET

LOGIN   LD A,(CSOCK)
        LD (CURSOCK),A
        CALL EXPECT2
        RET C
        CALL ASKUSER
        RET C
        LD HL,CUSER
        LD DE,(UNAME)
        LD (CMDARG),DE
        CALL SENDCMD
        RET C
        CP 3
        JP Z,LOGPASS
        CP 2
        JP NZ,ARGBAD
        JP LOGTYPE
LOGPASS LD A,(PWPROM)
        OR A
        JP Z,LPASSOK
        CALL ASKPASS
        RET C
LPASSOK LD HL,CPASS
        LD DE,(PASSWD)
        LD (CMDARG),DE
        CALL SENDCMD
        RET C
        CP 2
        JP NZ,ARGBAD
LOGTYPE LD HL,CTYPE
        CALL SIMPLE
        RET C
        CP 2
        JP NZ,ARGBAD
        OR A
        RET
; PASV: 227 reply contains h1,h2,h3,h4,p1,p2 in decimal.
; Use the reply address. Can fall back to control host if server returns 0s.
PASVP   LD HL,RPLINE
PSEEK   LD A,(HL)
        CP '('
        JP Z,PFND
        CP '$'
        JP Z,ARGBAD
        INC HL
        JP PSEEK
PFND    INC HL
        LD DE,PASVIP
        LD B,6
PNUM    PUSH BC
        PUSH DE
        CALL OCTET
        POP DE
        POP BC
        RET C
        LD (DE),A
        INC DE
        DEC B
        JP Z,PEND
        LD A,(HL)
        CP ','
        JP NZ,ARGBAD
        INC HL
        JP PNUM
PEND    LD A,(HL)
        CP ')'
        JP NZ,ARGBAD
        LD A,(PASVIP)
        LD B,A
        LD A,(PASVIP+1)
        OR B
        LD B,A
        LD A,(PASVIP+2)
        OR B
        LD B,A
        LD A,(PASVIP+3)
        OR B
        JP NZ,PVOK
        LD HL,HOSTIP
        LD DE,PASVIP
        LD BC,4
        LDIR
PVOK    LD A,(PASPRT)
        LD B,A
        LD A,(PASPRT+1)
        OR B
        JP Z,ARGBAD
        OR A
        RET
OPENDAT LD A,(CSOCK)
        LD (CURSOCK),A
        LD HL,CPASV
        CALL SIMPLE
        RET C
        CP 2
        JP NZ,ARGBAD
        LD A,(RPLINE+1)
        CP '2'
        JP NZ,ARGBAD
        LD A,(RPLINE+2)
        CP '7'
        JP NZ,ARGBAD
        CALL PASVP
        RET C
        CALL ALCDAT
        RET C
        LD A,(DSOCK)
        LD (CURSOCK),A
        LD HL,PASVIP
        LD (DESTIP),HL
        LD HL,PASPRT
        LD (DESTPRT),HL
        CALL SETTCP
        CALL CONNEC
        RET
; Send command based on action. Return to control socket and read 1xx.
DOXFER  LD A,(CSOCK)
        LD (CURSOCK),A
        LD A,(MODE)
        CP 1
        JP Z,XGET
        CP 2
        JP Z,XPUT
        LD HL,CLIST
        JP XARG
XGET    LD HL,CRETR
        JP XARG
XPUT    LD HL,CSTOR
XARG    LD DE,(REMOTE)
        LD (CMDARG),DE
        CALL CMDARG0
        RET C
        CALL EXPECT1
        RET C
        LD A,(MODE)
        CP 1
        JP Z,RECVGET
        CP 2
        JP Z,SENDPUT
        JP RECVDIR
RECVGET CALL FCREATE
        RET C
        ; GET always writes to the local file.  Never dispatch from MODE
        ; while consuming data: it may be altered by a BDOS call.
        XOR A
        LD (RXROUTE),A
        LD DE,GSTART
        CALL PRINT
        CALL DATAREC
        RET C
        CALL FINFILE
        RET C
        LD DE,DONEBYT
        CALL PRINT
        JP TRANSOK
RECVDIR LD A,1
        LD (RXROUTE),A
        CALL DATAREC
        RET C
        JP TRANSOK
TRANSOK LD A,(DSOCK)
        CALL FREEONE
        XOR A
        LD (DHELD),A
        LD A,(CSOCK)
        LD (CURSOCK),A
        CALL EXPECT2
        RET C
        OR A
        RET
; Consume bytes from data socket, until CLOSE_WAIT/CLOSED and drained.
DATAREC LD HL,30000
        LD (IDLE),HL
RECVLP  LD A,(DSOCK)
        LD (CURSOCK),A
        CALL READ16
        CP 0FFH
        JP Z,ARGBAD
        OR A
        JP Z,RIDLE
        LD B,A
        LD HL,30000
        LD (IDLE),HL
        LD HL,RXBUF
REACH   LD A,(RXROUTE)       ; stable receive sink chosen at entry
        OR A
        JP NZ,DIRBYTE
        LD A,(HL)
        PUSH HL
        PUSH BC
        CALL SAVECHR
        POP BC
        POP HL
        RET C
        JP RCONT
DIRBYTE LD A,(HL)
        PUSH HL
        PUSH BC
        CALL PUTC
        POP BC
        POP HL
RCONT   INC HL
        DJNZ REACH
        JP RECVLP
RIDLE   CALL FBGET
        CP 01CH
        JP Z,REND
        CP 0
        JP Z,REND
        CP 017H
        JP NZ,ARGBAD
        LD HL,(IDLE)
        DEC HL
        LD (IDLE),HL
        LD A,H
        OR L
        JP Z,ARGBAD
        LD C,11
        CALL BDOS
        JP RECVLP
REND    OR A
        RET
; PUT uploads all CP/M 128-byte records (including final padding).
SENDPUT LD A,(DSOCK)
        LD (CURSOCK),A
PUTLP   LD DE,FILEBUF
        LD C,26
        CALL BDOS
        LD DE,FCB
        LD C,20
        CALL BDOS
        OR A
        JP Z,PUTREC
        CP 1
        JP NZ,ARGBAD
        LD E,8                    ; DISCON after last queued SEND
        CALL FBCMD
        CP 0FFH
        JP Z,ARGBAD
        CALL CLOSEF
        LD HL,30000
PWAIT   PUSH HL
        CALL FBGET
        POP HL
        CP 0
        JP Z,TRANSOK
        CP 01CH
        JP Z,TRANSOK
        DEC HL
        LD A,H
        OR L
        JP Z,ARGBAD
        LD A,L
        OR A
        JP NZ,PWAIT
        PUSH HL
        LD C,11
        CALL BDOS
        POP HL
        JP PWAIT
PUTREC  LD HL,FILEBUF
        LD A,8
        LD (CHUNKS),A
PCHUNK  LD A,16
        CALL SENDRAW
        RET C
        LD HL,(SPTR)
        LD A,(CHUNKS)
        DEC A
        LD (CHUNKS),A
        JP NZ,PCHUNK
        JP PUTLP

BANNER  DEFM 'Zapple-II FTP v0.2b (PASV)'
        DEFB 13,10,'$'
USAGE   DEFM 'FTP host[:port] GET remote local [user [pass]]'
        DEFB 13,10
        DEFM 'FTP host[:port] PUT local remote [user [pass]]'
        DEFB 13,10
        DEFM 'FTP host[:port] DIR [path] [user [pass]]'
        DEFB 13,10
        DEFM 'Omit pass (or use ?) to prompt. User ? prompts too'
        DEFB 13,10,'$'
BADHOST DEFM 'Invalid host or TCP port'
        DEFB 13,10,'$'
BADFILE DEFM 'Invalid, missing or existing local file'
        DEFB 13,10,'$'
BADDNS  DEFM 'DNS lookup failed'
        DEFB 13,10,'$'
BADNET  DEFM 'Socket error / connection timeout'
        DEFB 13,10,'$'
BADFTP  DEFM 'FTP error (partial local file may remain)'
        DEFB 13,10,'$'
FINMSG DEFM 'Transfer finished'
        DEFB 13,10,'$'
GSTART  DEFM '[GET] Receiving into CP/M file'
        DEFB 13,10,'$'
DONEBYT DEFM '[GET] Data channel finished - waiting for FTP reply'
        DEFB 13,10,'$'
DNSMSG DEFM 'Resolving host...'
        DEFB 13,10,'$'
USRMSG  DEFM 'Username: $'
PASMSG  DEFM 'Password: $'
NL      DEFB 13,10,'$'
CRLF0   DEFB 13,10,0
CMDGET  DEFM 'GET'
        DEFB 0
CMDPUT  DEFM 'PUT'
        DEFB 0
CMDDIR  DEFM 'DIR'
        DEFB 0
DOTSTR  DEFM '.'
        DEFB 0
ANON    DEFM 'anonymous'
        DEFB 0
ANONPWD DEFM 'zapple@apple2'
        DEFB 0
CUSER   DEFM 'USER '
        DEFB 0
CPASS   DEFM 'PASS '
        DEFB 0
CTYPE   DEFM 'TYPE I'
        DEFB 0
CPASV   DEFM 'PASV'
        DEFB 0
CRETR   DEFM 'RETR '
        DEFB 0
CSTOR   DEFM 'STOR '
        DEFB 0
CLIST   DEFM 'LIST '
        DEFB 0
; IMPORTANT: Explicit initialization of uninitialized storage at startup.
VARS0
CMDTXT  DEFS 128
TOKENS  DEFS 12
TCOUNT  DEFB 0
MODE    DEFB 0
RXROUTE DEFB 0           ; 0=save to file, 1=print DIR listing
REMOTE  DEFW 0
LOCAL   DEFW 0
UNAME   DEFW 0
PASSWD  DEFW 0
PWPROM  DEFB 0
INPECHO DEFB 0
INPBASE DEFW 0
USRBUF  DEFS 65
PWBUF   DEFS 65
HOSTNAM DEFS 64
HOSTIP  DEFS 4
NEEDDNS DEFB 0
NDIG    DEFB 0
DIGIT   DEFB 0
PORT21  DEFB 0,21
PASVIP  DEFS 4
PASPRT  DEFS 2
FCB     DEFS 36
FILEBUF DEFS 128
FILEOP  DEFB 0
FIDX    DEFB 0
SAVEB   DEFB 0
CSOCK   DEFB 0
DSOCK   DEFB 0
CHELD   DEFB 0
DHELD   DEFB 0
CURSOCK DEFB 0
DESTIP  DEFW 0
DESTPRT DEFW 0
WPAR    DEFS 2
WVAL    DEFB 0
NXP     DEFS 5
TXBUF   DEFS 16
RXBUF   DEFS 16
SPTR    DEFW 0
STRPTR  DEFW 0
TXLEN   DEFB 0
RLEFT   DEFB 0
SWAIT   DEFW 0
IDLE    DEFW 0
CHUNKS  DEFB 0
RXCNT   DEFB 0
RXIDX   DEFB 0
CTLSAVE DEFB 0
RPLINE  DEFS 145
RLPTR   DEFW 0
MULTI   DEFB 0
MULTCOD DEFS 3
CMDARG  DEFW 0
OUTPTR  DEFW 0
VARS1

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

STACK   DEFS 512
STKTOP

; v0.2c fix: control stream gets its OWN 16-byte receive buffer.
; Important: READLN may leave unread bytes in CRXBUF when the first
; 150 reply shares a packet with a later 226 reply. DATAREC must never
; overwrite those bytes while receiving file content in RXBUF.
; This entry is placed after STKTOP, preserving every prior address.
CTLREAD LD A,(CURSOCK)
        LD (NXP),A
        LD A,1
        LD (NXP+1),A
        LD A,16
        LD (NXP+2),A
        LD HL,CRXBUF
        LD (NXP+3),HL
        LD DE,NXP
        LD C,0FCH
        JP BDOS
CRXBUF  DEFS 16
        END
