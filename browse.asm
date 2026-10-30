; BROWSE.COM - text-only HTTP browser for Zapple-II / Apple IIe.
; Phase 6L.3: interactive, case-preserving URL entry (no command tail).
; HTTP/1.0, shared DNS, ~16KB HTML buffer,
; 32 numbered links, paged navigation and plain-HTTP redirects.
; Assembler: Udo Munk Z80ASM v1.1 (8-character symbols).
; No files, no kernel changes, no timers or interrupts.
; Some modern sites require HTTPS/JS; browser supports HTTP only.
;
BDOS    EQU 0005H
        ORG 0100H
START   LD SP,STKTOP
        XOR A
        LD (HELD),A
        LD (BACKOK),A
        LD DE,BANNER
        CALL PRINT
        CALL ASKURL
        JP C,EXIT
MAIN    CALL GETPAGE
        JP C,FAILED
        CALL DISPLAY
        LD A,(ABORT)
        OR A
        JP NZ,EXIT
        LD A,(PAGCMD)
        OR A
        JP NZ,COMACT
COMLOOP LD DE,PROMPT
        CALL PRINT
        CALL INPUT
COMACT  LD HL,INBUF
        CALL SKIPSP
        LD A,(HL)
        OR A
        JR Z,COMLOOP
        CALL UPPER
        CP 'Q'
        JP Z,EXIT
        CP 'R'
        JP Z,MAIN
        CP 'B'
        JR Z,GOBACK
        CP 'U'
        JR Z,GOTOURL
        CALL GETNUM
        JR C,COMBAD
        CALL GOLINK
        JR C,COMBAD
        JP MAIN
GOBACK  LD A,(BACKOK)
        OR A
        JR Z,COMBAD
        LD HL,BACKURL
        LD DE,URLBUF
        CALL CPURL
        XOR A
        LD (BACKOK),A
        JP MAIN
GOTOURL INC HL
        CALL SKIPSP
        LD A,(HL)
        OR A
        JR Z,COMBAD
        LD DE,TMPURL
        CALL CPURL
        JR C,COMBAD
        CALL COMMIT
        JP MAIN
COMBAD  LD DE,BADSEL
        CALL PRINT
        JP COMLOOP
FAILED  LD DE,PAGEERR
        CALL PRINT
        JP COMLOOP
EXIT    CALL NETFREE
        LD C,0
        JP BDOS

PRINT   LD C,9
        JP BDOS
; Diagnostic hex printer retained from working WGET.
HEXBYTE PUSH AF
        RRCA
        RRCA
        RRCA
        RRCA
        CALL NIBBLE
        POP AF
NIBBLE  AND 0FH
        ADD A,'0'
        CP '9'+1
        JR C,HEXCHR
        ADD A,7
HEXCHR  LD E,A
        LD C,2
        JP BDOS

; The CP/M 2.2 CCP uppercases the command tail at 0080h by design.
; URLs have case-sensitive paths, so read them directly from the terminal.
; This deliberately ignores any arguments supplied to BROWSE.COM.
ASKURL  LD DE,ASKMSG
        CALL PRINT
        CALL INPUT
        LD HL,INBUF
        CALL SKIPSP
        LD A,(HL)
        OR A
        JR Z,ASKURL             ; empty URL: ask again
        CALL UPPER
        CP 'Q'
        JR NZ,ASKCOPY
        INC HL
        LD A,(HL)
        OR A
        JR Z,ASKQUIT            ; Q alone quits
        DEC HL
ASKCOPY LD DE,URLBUF
        CALL CPURL              ; copy verbatim: preserve URL case
        RET NC
        LD DE,ASKLONG
        CALL PRINT
        JR ASKURL
ASKQUIT SCF
        RET
; CPURL copies NUL-terminated string, checking 190-byte limit.
; HL->source, DE->target. Returns carry set if too long.
CPURL   LD B,190
CPULP   LD A,(HL)
        LD (DE),A
        OR A
        RET Z
        INC HL
        INC DE
        DJNZ CPULP
        SCF
        RET
SKIPSP  LD A,(HL)
        CP ' '
        JR Z,SKIP1
        CP 9
        RET NZ
SKIP1   INC HL
        JR SKIPSP
; Uppercase input A, also used in URL parsing.

; Ensure URLs with no path acquire a '/' before URLPAR.
FIXSLAS LD HL,URLBUF+7
        LD B,180
FXSLP   LD A,(HL)
        CP '/'
        RET Z
        OR A
        JR Z,FXEND
        INC HL
        DJNZ FXSLP
        SCF
        RET
FXEND   LD (HL),'/'
        INC HL
        LD (HL),0
        OR A
        RET

; Follow a bounded number of HTTP redirects.  Redirects do not create
; extra Back-history entries; only the initiating user navigation does.
GETPAGE LD A,5
        LD (RDLEFT),A
GPNEXT  CALL GETONCE
        RET C
        LD A,(REDIR)
        OR A
        RET Z
        LD A,(RDLEFT)
        DEC A
        LD (RDLEFT),A
        JR Z,GPTOOM
        LD HL,REDURL
        LD (HREFPT),HL
        LD A,1
        LD (RDINNAV),A
        CALL LINKURL
        PUSH AF
        XOR A
        LD (RDINNAV),A
        POP AF
        JR NC,GPCONT
        LD DE,REDERR
        CALL PRINT
        LD DE,REDURL
        CALL PRINT0
        CALL NEWLINE
        SCF
        RET
GPCONT  JP GPNEXT
GPTOOM  LD DE,TOOMANY
        CALL PRINT
        SCF
        RET

; Fetch response into HTML, then release the socket before display.
GETONCE XOR A
        LD (HELD),A
        LD (ABORT),A
        LD (CUT),A
        LD (LPOS),A
        LD (REDIR),A
        LD (GOTLOC),A
        LD (STCODE),A
        LD A,1
        LD (HEADER),A
        LD (FIRST),A
        LD HL,HTML
        LD (BODYPT),HL
        LD HL,80
        LD A,H
        LD (DPORT),A
        LD A,L
        LD (DPORT+1),A
        CALL FIXSLAS
        RET C
        LD HL,URLBUF
        LD (URLPTR),HL
        CALL URLPAR
        RET C
        LD DE,URLMSG
        CALL PRINT
        LD DE,URLBUF
        CALL PRINT0
        CALL NEWLINE
        CALL NETALOC
        RET C
        CALL SETTCP
        JR C,GETFAIL
        CALL OPENCON
        JR C,GETFAIL
        CALL REQHTTP
        JR C,GETFAIL
        CALL RECEIVE
        JR C,GETFAIL
        CALL NETFREE
        OR A
        RET
GETFAIL CALL NETFREE
        SCF
        RET
; Print NUL-terminated string at DE, not CP/M $ terminated.
PRINT0  LD A,(DE)
        OR A
        RET Z
        PUSH DE
        CALL RAWOUT
        POP DE
        INC DE
        JR PRINT0
RAWOUT  PUSH BC
        PUSH DE
        PUSH HL
        LD E,A
        LD C,2
        CALL BDOS
        POP HL
        POP DE
        POP BC
        RET
NEWLINE PUSH AF
        LD A,13
        CALL RAWOUT
        LD A,10
        CALL RAWOUT
        POP AF
        RET

; User command input, up to 189 characters.
INPUT   LD HL,INBUF
        LD B,189
INLOOP  PUSH BC
        PUSH HL
        LD C,1
        CALL BDOS
        POP HL
        POP BC
        CP 13
        JR Z,INEND
        CP 8
        JR Z,INBACK
        CP 127
        JR Z,INBACK
        CP 32
        JR C,INLOOP
        LD (HL),A
        INC HL
        DJNZ INLOOP
        JR INEND
INBACK  LD A,B
        CP 189
        JR Z,INLOOP
        DEC HL
        INC B
        JR INLOOP
INEND   LD (HL),0
        CALL NEWLINE
        RET
; A number between 1 and 32; input HL->first digit.
GETNUM  LD B,0
NUMLOOP LD A,(HL)
        CP '0'
        JR C,NUMDONE
        CP '9'+1
        JR NC,NUMDONE
        SUB '0'
        LD C,A
        LD A,B
        ADD A,A
        LD D,A
        ADD A,A
        ADD A,A
        ADD A,D
        ADD A,C
        LD B,A
        INC HL
        JR NUMLOOP
NUMDONE CALL SKIPSP
        LD A,(HL)
        OR A
        JR NZ,NUMBAD
        LD A,B
        OR A
        JR Z,NUMBAD
        LD C,A
        LD A,(LCOUNT)
        CP C
        JR C,NUMBAD
        LD A,C
        OR A
        RET
NUMBAD  SCF
        RET
; Commit navigated URL, saving previous URL for one-level Back.
COMMIT  LD HL,URLBUF
        LD DE,BACKURL
        CALL CPURL
        LD HL,TMPURL
        LD DE,URLBUF
        CALL CPURL
        LD A,1
        LD (BACKOK),A
        OR A
        RET

; Parse http://host-or-IP[:port]/path, retaining original Host: header.
; Resolve hostnames using the resident DNS setting before opening TCP.
URLPAR  LD HL,(URLPTR)
        LD DE,PREFIX
URLPRE  LD A,(DE)
        OR A
        JR Z,PREOK
        LD B,A
        LD A,(HL)
        CALL UPPER
        CP B
        JP NZ,URLBAD
        INC HL
        INC DE
        JR URLPRE
PREOK   LD (HOSTPT),HL
        LD DE,HOSTNAM
        LD B,63
UHLOOP  LD A,(HL)
        OR A
        JP Z,URLBAD
        CP ':'
        JR Z,UHDONE
        CP '/'
        JR Z,UHDONE
        CP 33                  ; no spaces or controls
        JP C,URLBAD
        LD (DE),A
        INC HL
        INC DE
        DJNZ UHLOOP
        JP URLBAD              ; hostname too long
UHDONE  LD A,B
        CP 63
        JP Z,URLBAD            ; empty host
        XOR A
        LD (DE),A
        LD A,(HL)
        CP ':'
        JR NZ,PORTEND
        INC HL
        CALL GETPORT
        JP C,URLBAD
PORTEND LD A,(HL)
        CP '/'
        JP NZ,URLBAD
        LD (PATHPT),HL
        ; HTTP Host: must include :port if supplied; use original URL.
        LD HL,(HOSTPT)
        LD DE,HOSTTX
        LD B,69
HOSTCP  LD A,(HL)
        CP '/'
        JR Z,HOSTEND
        OR A
        JP Z,URLBAD
        LD (DE),A
        INC HL
        INC DE
        DJNZ HOSTCP
        JP URLBAD
HOSTEND XOR A
        LD (DE),A
        CALL NUMIP
        RET NC                ; numeric IPv4: no DNS query needed
        CALL DNSINIT
        LD HL,HOSTNAM
        CALL DNRSLV
        JP C,URLBAD
        EX DE,HL
        LD DE,HOSTIP
        LD BC,4
        LDIR
        OR A
        RET
URLBAD  SCF
        RET

; Try parsing the entire host as dotted decimal IPv4.
; Non-numeric hosts are resolved by DNSLIB instead.
NUMIP   LD HL,HOSTNAM
        LD DE,HOSTIP
        LD B,4
NIPLP   PUSH BC
        PUSH DE
        CALL OCTET
        POP DE
        POP BC
        JR C,NIPBAD
        LD (DE),A
        INC DE
        DEC B
        JR Z,NIPEND
        LD A,(HL)
        CP '.'
        JR NZ,NIPBAD
        INC HL
        JR NIPLP
NIPEND  LD A,(HL)
        OR A
        JR NZ,NIPBAD
        OR A
        RET
NIPBAD  SCF
        RET

; Input HL->digits, return A=octet, HL->delimiter.
OCTET   LD B,0
        LD C,0
OCTLP   LD A,(HL)
        CP '0'
        JR C,OCTEND
        CP '9'+1
        JR NC,OCTEND
        SUB '0'
        LD D,A
        LD A,B
        ADD A,A
        JR C,OCTBAD
        LD E,A
        ADD A,A
        JR C,OCTBAD
        ADD A,A
        JR C,OCTBAD
        ADD A,E
        JR C,OCTBAD
        ADD A,D
        JR C,OCTBAD
        LD B,A
        INC C
        INC HL
        JR OCTLP
OCTEND  LD A,C
        OR A
        JR Z,OCTBAD
        LD A,B
        OR A
        RET
OCTBAD  SCF
        RET
; Input HL->digits ending '/', store big-endian DPORT.
GETPORT EX DE,HL
        LD HL,0
        LD A,0
        LD (PNDIG),A
PORTLP  LD A,(DE)
        CP '0'
        JR C,PORTDN
        CP '9'+1
        JR NC,PORTDN
        SUB '0'
        LD (PDIG),A
        PUSH DE
        LD D,H
        LD E,L
        ADD HL,HL
        JR C,PORTOF
        ADD HL,HL
        JR C,PORTOF
        ADD HL,HL
        JR C,PORTOF
        ADD HL,DE
        JR C,PORTOF
        ADD HL,DE
        JR C,PORTOF
        LD A,(PDIG)
        LD E,A
        LD D,0
        ADD HL,DE
        JR C,PORTOF
        POP DE
        INC DE
        LD A,(PNDIG)
        INC A
        LD (PNDIG),A
        CP 6
        JR NC,PORTERR
        JR PORTLP
PORTOF  POP DE
PORTERR SCF
        RET
PORTDN  LD A,(PNDIG)
        OR A
        JR Z,PORTERR
        LD A,H
        OR L
        JR Z,PORTERR
        LD A,H
        LD (DPORT),A
        LD A,L
        LD (DPORT+1),A
        EX DE,HL
        OR A
        RET
UPPER   CP 'a'
        RET C
        CP 'z'+1
        RET NC
        SUB 32
        RET



; Resolve the Nth numbered href into TMPURL.
; Accepted: http://host/path, //host/path, /path, relative path.
; Reject https://, mailto:, javascript:, fragments and other schemes.
GOLINK  LD B,A
        LD HL,LINKS
GLNEXT  DEC B
        JR Z,GLFOUND
        LD DE,128
        ADD HL,DE
        JR GLNEXT
GLFOUND JP LINKURL
LINKURL LD (HREFPT),HL
        LD A,(HL)
        OR A
        JP Z,NAVBAD
        CP '#'
        JP Z,NAVBAD
        ; Absolute http URL?
        LD DE,HPREFIX
        CALL MATCHP
        JR NC,GLABS
        LD HL,(HREFPT)
        LD A,(HL)
        CP '/'
        JR NZ,GLREL
        INC HL
        LD A,(HL)
        CP '/'
        JR Z,GLPROT
        JR GLROOT
GLABS   LD HL,(HREFPT)
        LD DE,TMPURL
        CALL CPURL
        RET C
        JP NAVCMIT
GLPROT  LD HL,HTTPCOL
        LD DE,TMPURL
        CALL CATSTR
        JP C,NAVBAD
        LD HL,(HREFPT)
        CALL CATSTR
        JP C,NAVBAD
        JP NAVCMIT
GLROOT  LD HL,HPREFIX
        LD DE,TMPURL
        CALL CATSTR
        JP C,NAVBAD
        LD HL,HOSTTX
        CALL CATSTR
        JP C,NAVBAD
        LD HL,(HREFPT)
        CALL CATSTR
        JP C,NAVBAD
        JP NAVCMIT
GLREL   LD HL,(HREFPT)    ; relative URL
GLRSCAN LD A,(HL)
        OR A
        JR Z,GLRGOOD
        CP '/'
        JR Z,GLRGOOD
        CP ':'
        JP Z,NAVBAD
        INC HL
        JR GLRSCAN
GLRGOOD LD HL,URLBUF    ; copy through final slash
        LD DE,TMPURL
        LD BC,0
        LD (LASTSL),BC
GLRCOPY LD A,(HL)
        OR A
        JR Z,GLRFIN
        PUSH HL
        LD HL,TMPURL+189
        OR A
        SBC HL,DE
        POP HL
        JP C,NAVBAD
        LD A,(HL)
        LD (DE),A
        CP '/'
        JR NZ,GLRNO
        LD (LASTSL),DE
GLRNO   INC HL
        INC DE
        JR GLRCOPY
GLRFIN  LD DE,(LASTSL)
        LD A,D
        OR E
        JP Z,NAVBAD
        INC DE
        LD HL,(HREFPT)
        LD A,(HL)
        CP '.'
        JR NZ,GLRCAT
        INC HL
        LD A,(HL)
        CP '/'
        JR NZ,NAVBAD
        INC HL
GLRCAT  CALL CATSTR
        JP C,NAVBAD
        JP NAVCMIT
NAVBAD  SCF
        RET
; Automatic redirects retain the original browser Back location.
NAVCMIT LD A,(RDINNAV)
        OR A
        JP Z,COMMIT
        LD HL,TMPURL
        LD DE,URLBUF
        JP CPURL
; Append NUL-terminated string HL to TMPURL at DE safely.
; Carry set if it would exceed the 190 byte URL limit.
CATSTR  LD A,(HL)
        OR A
        JR Z,CATEND
        PUSH HL
        LD HL,TMPURL+189
        OR A
        SBC HL,DE
        POP HL
        JR C,CATERR
        LD A,(HL)
        LD (DE),A
        INC HL
        INC DE
        JR CATSTR
CATEND  XOR A
        LD (DE),A
        RET
CATERR  SCF
        RET
; Match literal at DE with text at HL, case insensitive.
; Carry clear if matched; HL preserved.
MATCHP  PUSH HL
MATLP   LD A,(DE)
        OR A
        JR Z,MATOK
        LD B,A
        LD A,(HL)
        CALL UPPER
        CP B
        JR NZ,MATBAD
        INC HL
        INC DE
        JR MATLP
MATOK   POP HL
        OR A
        RET
MATBAD  POP HL
        SCF
        RET

; Network ownership from Phase 3/4: FA allocate/free.
NETALOC LD E,0
        LD C,0FAH
        CALL BDOS
        CP 4
        JR NC,ALFAIL
        LD (SOCKNO),A
        LD D,A
        ADD A,4
        LD (SOCKHI),A
        LD A,1
        LD (HELD),A
        LD DE,SOCKMSG
        CALL PRINT
        LD A,(SOCKNO)
        CALL HEXBYTE
        LD DE,CRLF
        CALL PRINT
        OR A
        RET
ALFAIL  SCF
        RET
NETFREE LD A,(HELD)
        OR A
        RET Z
        XOR A
        LD (HELD),A
        LD A,(SOCKNO)
        LD D,A
        LD E,1
        LD C,0FAH
        CALL BDOS
        RET

; F9: three-byte MAIN-to-6502 bridge writes W5100 address/value.
; B=selected socket register offset, A=value.
WSET    LD (WVAL),A
        LD A,(SOCKHI)
        LD (WPAR),A
        LD A,B
        LD (WPAR+1),A
        LD DE,WPAR
        LD C,0F9H
        CALL BDOS
        RET
; Set TCP mode, source port, destination IP/port. Reassert mode.
SETTCP  LD B,0
        LD A,1
        CALL WSET
        LD B,4
        LD A,0C0H
        CALL WSET
        LD B,5
        LD A,(SOCKNO)
        ADD A,0DEH
        CALL WSET
        LD B,0CH
        LD A,(HOSTIP)
        CALL WSET
        LD B,0DH
        LD A,(HOSTIP+1)
        CALL WSET
        LD B,0EH
        LD A,(HOSTIP+2)
        CALL WSET
        LD B,0FH
        LD A,(HOSTIP+3)
        CALL WSET
        LD B,10H
        LD A,(DPORT)
        CALL WSET
        LD B,11H
        LD A,(DPORT+1)
        CALL WSET
        LD B,0
        LD A,1
        CALL WSET
        OR A
        RET
; FB: D=socket E=operation, A=00 success (E=0 returns SR).
FBGET   LD A,(SOCKNO)
        LD D,A
        LD E,0
        LD C,0FBH
        CALL BDOS
        RET
FBCMD   LD D,A
        LD A,(SOCKNO)
        LD D,A
        LD C,0FBH
        CALL BDOS
        RET
OPENCON LD E,1
        CALL FBCMD
        CP 0FFH
        JR Z,NFATAL
        CALL FBGET
        CP 013H
        JR NZ,NFATAL
        LD E,4
        CALL FBCMD
        CP 0FFH
        JR Z,NFATAL
        LD HL,30000
CNWAIT  PUSH HL
        CALL FBGET
        POP HL
        CP 017H
        JR Z,CONOK
        CP 000H
        JR Z,NFATAL
        CP 01CH
        JR Z,NFATAL
        DEC HL
        LD A,H
        OR L
        JR Z,NFATAL
        LD A,L
        OR A
        JR NZ,CNWAIT
        PUSH HL
        LD C,11
        CALL BDOS
        POP HL
        JR CNWAIT
CONOK   OR A
        RET
NFATAL  SCF
        RET

; TCP transmit data via FC, up to 16 bytes, retry would-block.
; SENDSTR HL=NUL-terminated string. Uses a retry bound and yields.
SENDSTR LD (SPTR),HL
SSTRLP LD HL,(SPTR)
        LD A,(HL)
        OR A
        RET Z
        LD DE,TXBUF
        LD B,16
SCPY    LD A,(HL)
        OR A
        JR Z,SCEND
        LD (DE),A
        INC HL
        INC DE
        DJNZ SCPY
SCEND   LD A,16
        SUB B
        LD (SLEN),A
        LD HL,10000
        LD (SWAIT),HL
SRETRY  LD A,(SOCKNO)
        LD (NXP),A
        XOR A
        LD (NXP+1),A
        LD A,(SLEN)
        LD (NXP+2),A
        LD HL,TXBUF
        LD (NXP+3),HL
        LD DE,NXP
        LD C,0FCH
        CALL BDOS
        CP 0FFH
        JR Z,SDERR
        OR A
        JR Z,SWAIT0
        LD B,A
        LD A,(SLEN)
        CP B
        JR NZ,SDERR
        LD HL,(SPTR)
        LD E,A
        LD D,0
        ADD HL,DE
        LD (SPTR),HL
        JR SSTRLP
SWAIT0  LD HL,(SWAIT)
        DEC HL
        LD (SWAIT),HL
        LD A,H
        OR L
        JR Z,SDERR
        LD C,11
        CALL BDOS
        JR SRETRY
SDERR   SCF
        RET
REQHTTP LD HL,REQGET
        CALL SENDSTR
        RET C
        LD HL,(PATHPT)
        CALL SENDSTR
        RET C
        LD HL,REQVER
        CALL SENDSTR
        RET C
        LD HL,HOSTTX
        CALL SENDSTR
        RET C
        LD HL,REQTAIL
        JP SENDSTR



; Network receive: WGET FC 16-byte bursts, headers parsed across bursts.
; Record status code and Location: header. HTML limited to HTMLSZ.
RECEIVE LD HL,30000
        LD (IDLE),HL
RXLOOP  LD A,(SOCKNO)
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
        JP Z,RXERR
        OR A
        JR Z,RXIDLE
        LD B,A
        LD HL,30000
        LD (IDLE),HL
        LD HL,RXBUF
RXEACH  LD A,(HL)
        PUSH HL
        PUSH BC
        CALL PROCESS
        POP BC
        POP HL
        JP C,RXERR
        LD A,(CUT)
        OR A
        JR NZ,RXEOF
        INC HL
        DJNZ RXEACH
        JR RXLOOP
RXIDLE CALL FBGET
        CP 01CH
        JR Z,RXEOF
        CP 0
        JR Z,RXEOF
        CP 017H
        JP NZ,RXERR
        LD HL,(IDLE)
        DEC HL
        LD (IDLE),HL
        LD A,H
        OR L
        JP Z,RXERR
        LD C,11
        CALL BDOS
        JP RXLOOP
RXEOF   LD A,(HEADER)
        OR A
        JP NZ,RXERR
        LD HL,(BODYPT)
        LD (HL),0
        LD A,(STCODE)
        CP '2'
        JR NZ,RX3XX
        LD A,(STCODE+1)
        CP '0'
        JR NZ,RXSTATUS
        LD A,(STCODE+2)
        CP '0'
        JR NZ,RXSTATUS
        XOR A
        RET
RX3XX   LD A,(STCODE)
        CP '3'
        JR NZ,RXSTATUS
        ; Only redirect responses with a Location are actionable.
        LD A,(GOTLOC)
        OR A
        JR Z,RXSTATUS
        LD A,1
        LD (REDIR),A
        OR A
        RET
RXSTATUS LD DE,STATUSM
        CALL PRINT
        LD A,(STCODE)
        CALL RAWOUT
        LD A,(STCODE+1)
        CALL RAWOUT
        LD A,(STCODE+2)
        CALL RAWOUT
        CALL NEWLINE
RXERR   SCF
        RET
PROCESS LD E,A
        LD A,(HEADER)
        OR A
        JP Z,BODBYTE
        LD A,E
        CP 13
        JR Z,PROCOK
        CP 10
        JR Z,LINEDN
        LD A,(LPOS)
        CP 189
        JR NC,PROCOK
        LD L,A
        LD H,0
        LD BC,LINEBUF
        ADD HL,BC
        LD (HL),E
        LD A,(LPOS)
        INC A
        LD (LPOS),A
PROCOK  OR A
        RET
LINEDN  LD A,(FIRST)
        OR A
        JR Z,NOTFST
        XOR A
        LD (FIRST),A
        LD A,(LPOS)
        CP 12
        JP C,BADHTTP
        LD A,(LINEBUF)
        CP 'H'
        JP NZ,BADHTTP
        LD A,(LINEBUF+1)
        CP 'T'
        JP NZ,BADHTTP
        LD A,(LINEBUF+5)
        CP '1'
        JP NZ,BADHTTP
        ; Save actual 3-digit HTTP status. Never invent HTTP 200.
        LD A,(LINEBUF+9)
        LD (STCODE),A
        LD A,(LINEBUF+10)
        LD (STCODE+1),A
        LD A,(LINEBUF+11)
        LD (STCODE+2),A
LINRESET XOR A
        LD (LPOS),A
        RET
NOTFST  LD A,(LPOS)
        OR A
        JR Z,HDRDONE
        ; A header line was received.  NUL-terminate and test Location:.
        LD E,A
        LD D,0
        LD HL,LINEBUF
        ADD HL,DE
        LD (HL),0
        LD HL,LINEBUF
        LD DE,LOCATION
        CALL MATCHP
        JR C,LINRESET
        LD HL,LINEBUF+9
        CALL WHITES
        LD DE,REDURL
        LD B,189
LOCOPY  LD A,(HL)
        OR A
        JR Z,LOCDONE
        LD (DE),A
        INC DE
        INC HL
        DJNZ LOCOPY
LOCDONE XOR A
        LD (DE),A
        LD A,(REDURL)
        OR A
        JR Z,LINRESET
        LD A,1
        LD (GOTLOC),A
        JR LINRESET
HDRDONE XOR A
        LD (HEADER),A
        LD (LPOS),A
        RET
BADHTTP SCF
        RET
BODBYTE PUSH DE             ; E is received byte
        LD HL,(BODYPT)
        LD DE,HTMLEND-1
        OR A
        SBC HL,DE
        JR NC,BODYFULL
        ADD HL,DE
        POP DE
        LD (HL),E
        INC HL
        LD (BODYPT),HL
        OR A
        RET
BODYFULL POP DE
        LD A,1
        LD (CUT),A
        OR A
        RET


; Render HTML from buffered response. Number up to 32 links.
; Text-only, 76 columns, page every 22 text rows.
DISPLAY LD HL,LINKS
        LD (LPTR),HL
        XOR A
        LD (LCOUNT),A
        LD (COL),A
        LD (ROWS),A
        LD (SPACE),A
        LD (ABORT),A
        LD (QUIET),A
        LD (PAGCMD),A
        LD HL,HTML
        LD (RDPTR),HL
        CALL NEWLINE
DLOOP   LD A,(ABORT)
        OR A
        JP NZ,DEND
        LD HL,(RDPTR)
        LD A,(HL)
        OR A
        JP Z,DEND
        CP '<'
        JP Z,DTAG
        CP '&'
        JR Z,DENTITY
        CP 32
        JR C,DSPACE
        CP 127
        JR NC,DSKIP
        CALL TXCHAR
        JR DSKIP
DSPACE  LD A,1
        LD (SPACE),A
DSKIP   LD HL,(RDPTR)
        INC HL
        LD (RDPTR),HL
        JR DLOOP
DENTITY CALL ENTCON
        CALL TXCHAR
        JR DSKIP
; Tokenize tag name and dispatch simple structural tags.
DTAG    LD HL,(RDPTR)
        INC HL
        LD A,(HL)
        CP '!'
        JP Z,DSKIPT
        CP '/'
        JR NZ,DTOPEN
        INC HL
DTOPEN  LD A,(HL)
        CALL UPPER
        CP 'A'
        JP Z,DTANCH
        CP 'B'
        JP Z,DTBRT
        CP 'P'
        JP Z,DTBRT
        CP 'D'
        JP Z,DTBRT
        CP 'H'
        JP Z,DTBRT
        CP 'L'
        JP Z,DTBRT
        CP 'T'
        JP Z,DTBRT
        CP 'S'
        JP Z,DTSKIP
        JR DSKIPT
DTSKIP  ; Ignore script and stylesheet body text.
        PUSH HL
        LD DE,SCRIPT
        CALL MATCHP
        POP HL
        JR NC,DTSCR
        PUSH HL
        LD DE,STYLET
        CALL MATCHP
        POP HL
        JR NC,DTSTY
        JP DSKIPT
DTSCR   LD DE,SCRIPT
        JP SKIPBLK
DTSTY   LD DE,STYLET
        JP SKIPBLK
; Move to matching closing tag, then skip it normally.
SKIPBLK PUSH DE
        LD HL,(RDPTR)
SKBLP   LD A,(HL)
        OR A
        JR Z,SKBEND
        CP '<'
        JR NZ,SKBNXT
        INC HL
        LD A,(HL)
        CP '/'
        JR NZ,SKBNXT
        INC HL
        POP DE
        PUSH DE
        CALL MATCHP
        JR C,SKBNXT
        ; HL still points at closing element name.
        DEC HL
        DEC HL
        LD (RDPTR),HL
        POP DE
        JP DSKIPT
SKBNXT INC HL
        JR SKBLP
SKBEND POP DE
        JP DEND
DTBRT   CALL HARDNL
DSKIPT  LD HL,(RDPTR)
DSTLP   LD A,(HL)
        OR A
        JP Z,DEND
        CP '>'
        JR Z,DSTEND
        INC HL
        JR DSTLP
DSTEND  INC HL
        LD (RDPTR),HL
        JP DLOOP
; Only recognize actual <a ...>, not <article> or <aside>.
DTANCH  INC HL
        LD A,(HL)
        CP '>'
        JR Z,DSKIPT
        CP ' '
        JR Z,DFHREF
        CP 9
        JR Z,DFHREF
        JR DSKIPT
DFHREF  LD A,(LCOUNT)
        CP 32
        JR NC,DSKIPT
; Scan attributes until '>' looking for HREF=, quote optional.
AHSRCH  LD A,(HL)
        OR A
        JP Z,DEND
        CP '>'
        JP Z,DSKIPT
        CP 'H'
        JR Z,AHMAY
        CP 'h'
        JR NZ,AHNEXT
AHMAY   PUSH HL
        LD DE,HREFKEY
        CALL MATCHP
        POP HL
        JR C,AHNEXT
        LD DE,4
        ADD HL,DE
        CALL WHITES
        LD A,(HL)
        CP '='
        JR NZ,AHNEXT
        INC HL
        CALL WHITES
        CALL ADDLINK
        JP DSKIPT
AHNEXT  INC HL
        JR AHSRCH
WHITES  LD A,(HL)
        CP ' '
        JR Z,WHSP
        CP 9
        RET NZ
WHSP    INC HL
        JR WHITES
; HL->start of href value; add to table; modifies HL.
ADDLINK LD A,(HL)
        LD (QUOTE),A
        CP 34
        JR Z,AHQUOT
        CP 39
        JR NZ,AHBEGIN
AHQUOT  INC HL
        JR AHBEGIN
AHBEGIN LD DE,(LPTR)
        LD B,120
AHCOPY  LD A,(HL)
        OR A
        JR Z,AHDONE
        CP '>'
        JR Z,AHDONE
        CP 32
        JR Z,AHSPEND
        CP 9
        JR Z,AHSPEND
        LD C,A
        LD A,(QUOTE)
        CP 34
        JR Z,AHQTST
        CP 39
        JR NZ,AHSTORE
; Keep DE as the link-table write pointer. C holds the href character.
AHQTST  LD A,(QUOTE)
        CP C
        JR Z,AHDONE
AHSTORE LD A,C
        LD (DE),A
        INC DE
        INC HL
        DJNZ AHCOPY
        JR AHDONE
AHSPEND JR AHDONE
AHDONE XOR A
        LD (DE),A
        LD A,B
        CP 120
        RET Z
        LD A,(LCOUNT)
        INC A
        LD (LCOUNT),A
        PUSH HL
        CALL LINKNUM
        POP HL
        LD DE,(LPTR)
        LD HL,128
        ADD HL,DE
        LD (LPTR),HL
        RET
LINKNUM PUSH AF
        LD A,' '
        CALL TXCHAR
        LD A,'['
        CALL TXCHAR
        POP AF
        CALL DECNUM
        LD A,']'
        CALL TXCHAR
        LD A,' '
        CALL TXCHAR
        RET
; Decimal two-digit output, A in 0..99.
DECNUM  LD B,0
DCLOOP  CP 10
        JR C,DCDONE
        SUB 10
        INC B
        JR DCLOOP
DCDONE  LD C,A
        LD A,B
        ADD A,'0'
        CALL TXCHAR
        LD A,C
        ADD A,'0'
        JP TXCHAR
; Decode a few common HTML entities: &amp; &lt; &gt; &quot; &nbsp;
; RDPTR advances past entity, then DSKIP increments once more.
ENTCON  LD HL,(RDPTR)
        INC HL
        LD A,(HL)
        CP 'a'
        JR Z,ENTAMP
        CP 'l'
        JR Z,ENTLT
        CP 'g'
        JR Z,ENTGT
        CP 'q'
        JR Z,ENTQ
        CP 'n'
        JR Z,ENTNB
        LD A,'&'
        RET
ENTAMP  LD DE,EAMP
        LD B,'&'
        JR ENTMAT
ENTLT   LD DE,ELT
        LD B,'<'
        JR ENTMAT
ENTGT   LD DE,EGT
        LD B,'>'
        JR ENTMAT
ENTQ    LD DE,EQUOT
        LD B,34
        JR ENTMAT
ENTNB   LD DE,ENBSP
        LD B,' '
ENTMAT  PUSH BC
        CALL MATCHP
        POP BC
        JR C,ENTFAIL
        ; matched NUL terminated entity string, skip to semicolon.
ENTSKIP LD A,(HL)
        CP 03BH
        JR Z,ENTEND
        INC HL
        JR ENTSKIP
ENTEND  LD (RDPTR),HL
        LD A,B
        RET
ENTFAIL LD A,'&'
        RET
; Output text, folding whitespace and wrapping at col 76.
TXCHAR  PUSH AF
        LD A,(QUIET)
        OR A
        JR Z,TXLIVE
        POP AF
        RET
TXLIVE  LD A,(SPACE)
        OR A
        JR Z,TXNOW
        XOR A
        LD (SPACE),A
        LD A,(COL)
        OR A
        JR Z,TXNOW
        CP 75
        JR NC,TXWRAP
        LD A,' '
        CALL TXRAW
        JR TXNOW
TXWRAP  CALL HARDNL
TXNOW   POP AF
        JP TXRAW
TXRAW   PUSH AF
        LD A,(QUIET)
        OR A
        JR NZ,TXDROP
        LD A,(COL)
        CP 76
        JR C,TXOK
        CALL HARDNL
TXOK    LD A,(QUIET)
        OR A
        JR NZ,TXDROP
        POP AF
        CALL RAWOUT
        LD HL,COL
        INC (HL)
        RET
TXDROP  POP AF
        RET
HARDNL  LD A,(QUIET)
        OR A
        RET NZ
        LD A,(COL)
        OR A
        RET Z
        CALL NEWLINE
        XOR A
        LD (COL),A
        LD (SPACE),A
        LD A,(ROWS)
        INC A
        LD (ROWS),A
        CP 22
        RET C
        XOR A
        LD (ROWS),A
        LD DE,MOREMSG
        CALL PRINT
        ; Space and Enter retain one-key page advance.  Otherwise accept
        ; the full normal menu command, including two-digit link numbers.
        LD C,1
        CALL BDOS
        CP ' '
        JR Z,MOREOK
        CP 13
        JR Z,MOREOK
        LD (INBUF),A
        CALL UPPER
        CP 'Q'
        JR NZ,MOCHK
        LD A,1
        LD (ABORT),A
        JR MOREOK
MOCHK   CP 'M'
        JR NZ,MORECMD
        LD A,1
        LD (QUIET),A
        JR MOREOK
MORECMD LD HL,INBUF+1
        LD B,188
        CALL INLOOP
        LD A,1
        LD (QUIET),A
        ; Finish scanning HTML silently so later links are available.
        LD A,1
        LD (PAGCMD),A
MOREOK  CALL NEWLINE
        RET
DEND    CALL HARDNL
        CALL NEWLINE
        LD A,(CUT)
        OR A
        JR Z,DENOK
        LD DE,TRUNCMSG
        CALL PRINT
DENOK   LD DE,ENDMSG
        CALL PRINT
        LD A,(LCOUNT)
        CALL DECNUM
        CALL NEWLINE
        RET


BANNER  DEFM 'Zapple-II BROWSE v0.3 - text HTTP browser'
        DEFB 13,10,'$'
ASKMSG  DEFM 'URL (Q quits)> $'
ASKLONG DEFM 'URL too long (maximum 189 characters).'
        DEFB 13,10,'$'
PAGEERR DEFM 'Fetch failed (HTTP or connection error).'
        DEFB 13,10,'$'
BADSEL  DEFM 'No such link or unsupported address.'
        DEFB 13,10,'$'
PROMPT  DEFM 'Link #, U URL, B back, R reload, Q quit> $'
URLMSG  DEFM 'Fetching: $'
MOREMSG DEFM '--More-- SPACE next, # link, U URL, B back,'
        DEFM ' R reload, M menu, Q quit> '
        DEFB '$'
TRUNCMSG DEFM '(Page truncated to 16KB)'
        DEFB 13,10,'$'
ENDMSG  DEFM 'Links: $'
STATUSM DEFM 'HTTP status: $'
REDERR  DEFM 'Unsupported redirect: $'
TOOMANY DEFM 'Too many HTTP redirects'
        DEFB 13,10,'$'
LOCATION DEFM 'LOCATION:'
        DEFB 0
SOCKMSG DEFM 'Socket $'
CRLF    DEFB 13,10,'$'
HPREFIX DEFM 'HTTP://'
        DEFB 0
HTTPCOL DEFM 'http:'
        DEFB 0
HREFKEY DEFM 'HREF'
        DEFB 0
SCRIPT  DEFM 'SCRIPT'
        DEFB 0
STYLET  DEFM 'STYLE'
        DEFB 0
EAMP    DEFM 'AMP'
        DEFB 03BH,0
ELT     DEFM 'LT'
        DEFB 03BH,0
EGT     DEFM 'GT'
        DEFB 03BH,0
EQUOT   DEFM 'QUOT'
        DEFB 03BH,0
ENBSP   DEFM 'NBSP'
        DEFB 03BH,0
PREFIX  DEFM 'HTTP://'
        DEFB 0
REQGET  DEFM 'GET '
        DEFB 0
REQVER  DEFM ' HTTP/1.0'
        DEFB 13,10
        DEFM 'Host: '
        DEFB 0
REQTAIL DEFB 13,10
        DEFM 'Connection: close'
        DEFB 13,10
        DEFM 'Accept: text/html, text/plain'
        DEFB 13,10,13,10,0
URLBUF  DEFS 192
BACKURL DEFS 192
TMPURL  DEFS 192
INBUF   DEFS 192
BACKOK  DEFB 0
URLPTR  DEFW 0
HOSTPT  DEFW 0
PATHPT  DEFW 0
HOSTIP  DEFS 4
HOSTNAM DEFS 64
HOSTTX  DEFS 70
DPORT   DEFB 0,80
PNDIG   DEFB 0
PDIG    DEFB 0
SOCKNO  DEFB 0
SOCKHI  DEFB 0
HELD    DEFB 0
WPAR    DEFB 0,0
WVAL    DEFB 0
NXP     DEFS 5
TXBUF   DEFS 16
RXBUF   DEFS 16
SPTR    DEFW 0
SLEN    DEFB 0
SWAIT   DEFW 0
IDLE    DEFW 0
HEADER  DEFB 1
FIRST   DEFB 1
LPOS    DEFB 0
LINEBUF DEFS 192
STCODE  DEFS 3
REDURL  DEFS 192
REDIR   DEFB 0
GOTLOC  DEFB 0
RDLEFT  DEFB 0
RDINNAV DEFB 0
BODYPT  DEFW 0
RDPTR   DEFW 0
CUT     DEFB 0
ABORT   DEFB 0
QUIET   DEFB 0
PAGCMD  DEFB 0
COL     DEFB 0
ROWS    DEFB 0
SPACE   DEFB 0
QUOTE   DEFB 0
LCOUNT  DEFB 0
LPTR    DEFW 0
HREFPT  DEFW 0
LASTSL  DEFW 0
LINKS   DEFS 4096     ; 32 links x 128 bytes
HTMLSZ  EQU 16384
HTML    DEFS HTMLSZ
HTMLEND EQU HTML+HTMLSZ

; Obtain the shared runtime DNS address configured by IPCONFIG.
; FD: E=6, D=octet index 0..3, A=octet value on return.
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



STACK   DEFS 256
STKTOP
        END
