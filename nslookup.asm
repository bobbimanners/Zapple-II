; NSLOOKUP.COM v0.1 -- Zapple-II / Apple //e Z80 SoftCard / Uthernet-II
; UDP DNS A-record lookup over W5100. Udo Munk Z80ASM (8-char symbols).
; Usage: NSLOOKUP host.name [dns-server-ip]
; Default resolver: 1.1.1.1.  Explicit server IP recommended for LAN.
; Kernel BDOS FA alloc/free; FB OPEN/SEND/RECV/CLOSE; F9 W5100 writes.
; Single UDP datagram TX requires direct ring handling (FC sends per call).
; W5100 native Z80 reads and kernel F9 writes use the proven TELNET path.
; No kernel changes; fixed Uthernet-II slot 5, same as current F9 bridge.
; QNAME length limited by CP/M command tail; max 512-byte DNS response.

BDOS    EQU 0005H
        ORG 0100H
START   LD SP,STKTOP
        XOR A
        LD (HELD),A
        LD (FOUND),A
        LD DE,BANNER
        CALL PRINT
        CALL DNSINIT
        CALL ARGS
        JP C,BADARG
        CALL MAKEQ
        JP C,BADHOST
        CALL SETPORT
        CALL PICK
        JP C,NOSOCK
        CALL UDPOPEN
        JP C,NETERR
        CALL TXDNS
        JP C,NETERR
        LD DE,WAITMSG
        CALL PRINT
        CALL RXDNS
        JP C,NETERR
        CALL PARSE
        JP C,DNSERR
        JP EXIT
BADARG  LD DE,USAGE
        JP ERROR
BADHOST LD DE,HOSTERR
        JP ERROR
NOSOCK  LD DE,SOCKERR
        JP ERROR
NETERR  LD DE,NETMSG
        JP ERROR
DNSERR  LD DE,PARERR
ERROR   CALL PRINT
EXIT    CALL RELEASE
        LD C,0
        JP BDOS

; Phase 6K: default DNS server from kernel runtime setting (FD E=6).
; Requires 6K shared resolver interface. Explicit command-line override remains.
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

PRINT   PUSH BC
        PUSH DE
        PUSH HL
        LD C,9
        CALL BDOS
        POP HL
        POP DE
        POP BC
        RET
PUTC    PUSH AF
        PUSH BC
        PUSH DE
        PUSH HL
        LD E,A
        LD C,2
        CALL BDOS
        POP HL
        POP DE
        POP BC
        POP AF
        RET
HEX     PUSH AF
        RRCA
        RRCA
        RRCA
        RRCA
        CALL NIBBLE
        POP AF
NIBBLE  AND 0FH
        ADD A,'0'
        CP '9'+1
        JR C,PUTC
        ADD A,7
        JP PUTC

; Parse CP/M tail, name required; optional numeric DNS server IPv4.
ARGS    LD A,(0080H)
        CP 124
        JR NC,ARGFAIL
        LD B,A
        LD HL,0081H
        LD DE,CMDTXT
ARCPY   LD A,B
        OR A
        JR Z,ARDONE
        LD A,(HL)
        LD (DE),A
        INC HL
        INC DE
        DJNZ ARCPY
ARDONE  XOR A
        LD (DE),A
        LD HL,CMDTXT
        CALL SKIPSP
        LD A,(HL)
        OR A
        JR Z,ARGFAIL
        LD (HOSTPTR),HL
        CALL NEXTTOK
        CALL SKIPSP
        LD A,(HL)
        OR A
        JR Z,ARGOK
        LD DE,DNSIP
        LD B,4
IPLOOP  PUSH BC
        PUSH DE
        CALL OCTET
        POP DE
        POP BC
        JR C,ARGFAIL
        LD (DE),A
        INC DE
        DEC B
        JR Z,IPLAST
        LD A,(HL)
        CP '.'
        JR NZ,ARGFAIL
        INC HL
        JR IPLOOP
IPLAST  CALL SKIPSP
        LD A,(HL)
        OR A
        JR NZ,ARGFAIL
ARGOK   OR A
        RET
ARGFAIL SCF
        RET
SKIPSP  LD A,(HL)
        CP ' '
        JR Z,SKIP1
        CP 9
        RET NZ
SKIP1   INC HL
        JR SKIPSP
NEXTTOK LD A,(HL)
        OR A
        RET Z
        CP ' '
        JR Z,TOKEND
        CP 9
        JR Z,TOKEND
        INC HL
        JR NEXTTOK
TOKEND  XOR A
        LD (HL),A
        INC HL
        RET
; Numeric IPv4 octet. HL points at first digit, ends at '.' or NUL.
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

; DNS header 5AA5 flags 0100 (recursion desired), one A/IN question.
; DEFS is not necessarily zero! Every transmitted byte is written.
MAKEQ   LD HL,QHEAD
        LD DE,QBUF
        LD BC,12
        LDIR
        LD A,12
        LD (QCNT),A
        LD HL,(HOSTPTR)
        LD (QSPTR),HL
        LD DE,QBUF+12
        CALL NEWLAB
QLOOP   LD HL,(QSPTR)
        LD A,(HL)
        OR A
        JR Z,QEND
        CP '.'
        JR Z,QDOT
        CP 'A'
        JR C,QLOW
        CP 'Z'+1
        JR NC,QLOW
        ADD A,32
QLOW    CP 'a'
        JR C,QDIG
        CP 'z'+1
        JR C,QCHAR
QDIG    CP '0'
        JR C,QDASH
        CP '9'+1
        JR C,QCHAR
QDASH   CP '-'
        JR NZ,QBAD
QCHAR   LD B,A
        LD A,(QLABL)
        INC A
        CP 64
        JR NC,QBAD
        LD (QLABL),A
        LD A,B
        CALL QPUT
        LD HL,(QSPTR)
        INC HL
        LD (QSPTR),HL
        JR QLOOP
QDOT    CALL ENDLAB
        JR C,QBAD
        LD HL,(QSPTR)
        INC HL
        LD (QSPTR),HL
        LD A,(HL)
        OR A
        JR Z,QFIN
        CALL NEWLAB
        JR QLOOP
QEND    CALL ENDLAB
        JR C,QBAD
QFIN    XOR A
        CALL QPUT
        XOR A
        CALL QPUT
        LD A,1
        CALL QPUT
        XOR A
        CALL QPUT
        LD A,1
        CALL QPUT
        OR A
        RET
QBAD    SCF
        RET
NEWLAB  LD (QLBPTR),DE
        XOR A
        LD (QLABL),A
        CALL QPUT
        RET
ENDLAB  LD A,(QLABL)
        OR A
        JR Z,QBAD
        LD HL,(QLBPTR)
        LD (HL),A
        OR A
        RET
QPUT    LD (DE),A
        INC DE
        PUSH AF
        LD A,(QCNT)
        INC A
        LD (QCNT),A
        POP AF
        RET

; Slot 5 W5100 IO: verified Z80 native reads and kernel F9 writes.
SETPORT LD A,5
        ADD A,A
        ADD A,A
        ADD A,A
        ADD A,A
        ADD A,084H
        LD (MOD001+1),A
        INC A
        LD (ADD003+1),A
        INC A
        LD (ADD004+1),A
        INC A
        LD (DAT001+1),A
        RET
MOD001  LD A,(0E0B4H)
        RET
DAT001  LD A,(0E0B7H)
        RET
ADD003  LD (0E0B5H),A
        RET
ADD004  LD (0E0B6H),A
        RET
WSEL    PUSH AF
        LD A,H
        CALL ADD003
        LD A,L
        CALL ADD004
        POP AF
        RET
WREAD   CALL WSEL
        JP DAT001
WWRITE  PUSH AF
        PUSH BC
        PUSH DE
        PUSH HL
        LD (WVAL),A
        LD A,H
        LD (WADDR),A
        LD A,L
        LD (WADDR+1),A
        LD DE,WADDR
        LD C,0F9H
        CALL BDOS
        POP HL
        POP DE
        POP BC
        POP AF
        RET
; Write a selected socket register. B=offset, A=value.
WSET    PUSH HL
        PUSH AF
        LD A,(SOCKHI)
        LD H,A
        LD L,B
        POP AF
        CALL WWRITE
        POP HL
        RET
; Read a selected socket register. A=offset, return A=register.
WGET    PUSH HL
        LD L,A
        LD A,(SOCKHI)
        LD H,A
        CALL WREAD
        POP HL
        RET

PICK    LD E,0
        LD C,0FAH
        CALL BDOS
        CP 4
        JR NC,PICKERR
        LD (SOCKNO),A
        ADD A,4
        LD (SOCKHI),A
        LD A,1
        LD (HELD),A
        LD DE,SOCKMSG
        CALL PRINT
        LD A,(SOCKNO)
        CALL HEX
        LD DE,CRLF
        CALL PRINT
        OR A
        RET
PICKERR SCF
        RET
RELEASE LD A,(HELD)
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
; FB: E=W5100 command, or 0 to read status. Ownership checked.
FBCMD   LD A,(SOCKNO)
        LD D,A
        LD C,0FBH
        CALL BDOS
        RET
FBGET   LD E,0
        CALL FBCMD
        RET

UDPOPEN LD A,0
        CALL FBGET
        CP 0
        JR NZ,UDPBAD
        LD B,0
        LD A,2
        CALL WSET
        LD B,4
        LD A,0D3H
        CALL WSET
        LD B,5
        LD A,(SOCKNO)
        ADD A,051H
        CALL WSET
        LD B,0CH
        LD A,(DNSIP)
        CALL WSET
        LD B,0DH
        LD A,(DNSIP+1)
        CALL WSET
        LD B,0EH
        LD A,(DNSIP+2)
        CALL WSET
        LD B,0FH
        LD A,(DNSIP+3)
        CALL WSET
        LD B,10H
        XOR A
        CALL WSET
        LD B,11H
        LD A,35H
        CALL WSET
        LD B,0
        LD A,2
        CALL WSET
        LD E,1
        CALL FBCMD
        CP 0FFH
        JR Z,UDPBAD
        CALL FBGET
        CP 22H
        JR NZ,UDPBAD
        LD DE,UDPMSG
        CALL PRINT
        OR A
        RET
UDPBAD  SCF
        RET

; Compute TX or RX ring base and mask from live TMSR/RMSR.
; Input A=memory allocation register offset (1Bh TX, 1Ah RX).
; C=base page 40h (TX) or 60h (RX).
RINGSET LD (MEMREG),A
        LD A,C
        LD (RBASE),A
        LD A,(MEMREG)
        LD L,A
        LD H,0
        CALL WREAD
        LD B,A
        LD A,(SOCKNO)
        LD C,A
RINGLP  LD A,C
        OR A
        JR Z,RINGCUR
        LD A,B
        AND 3
        CALL SIZPAGE
        LD D,A
        LD A,(RBASE)
        ADD A,D
        LD (RBASE),A
        LD A,B
        RRCA
        RRCA
        LD B,A
        DEC C
        JR RINGLP
RINGCUR LD A,B
        AND 3
        CALL SIZPAGE
        DEC A
        LD (RMASK),A
        LD D,A
        LD A,(RBASE)
        AND 01FH
        ADD A,D
        CP 32
        JR NC,RINGBAD
        OR A
        RET
RINGBAD SCF
        RET
SIZPAGE LD E,A
        LD D,0
        LD HL,SZTAB
        ADD HL,DE
        LD A,(HL)
        RET
; PTRHI/PTRLO are full 16-bit W5100 hardware ring pointers.
; Input A=socket register offset of pointer's high byte.
GETPTR  CALL WGET
        LD (PTRHI),A
        LD A,(REGPTR)
        INC A
        CALL WGET
        LD (PTRLO),A
        RET
SETPTR  LD A,(REGPTR)
        LD B,A
        LD A,(PTRHI)
        CALL WSET
        LD A,(REGPTR)
        INC A
        LD B,A
        LD A,(PTRLO)
        CALL WSET
        RET
RADDR   PUSH BC
        LD A,(PTRHI)
        LD B,A
        LD A,(RMASK)
        AND B
        LD B,A
        LD A,(RBASE)
        ADD A,B
        LD H,A
        LD A,(PTRLO)
        LD L,A
        POP BC
        RET
INCPTR  LD A,(PTRLO)
        INC A
        LD (PTRLO),A
        RET NZ
        LD A,(PTRHI)
        INC A
        LD (PTRHI),A
        RET
RINGWR  PUSH AF
        CALL RADDR
        POP AF
        CALL WWRITE
        CALL INCPTR
        RET
RINGRD  CALL RADDR
        CALL WREAD
        PUSH AF
        CALL INCPTR
        POP AF
        RET

; Transmit DNS query as ONE UDP datagram, never through chunked FC.
TXDNS   LD A,1BH
        LD C,40H
        CALL RINGSET
        JP C,TXFAIL
        LD A,20H
        CALL WGET
        OR A
        JR NZ,TXSPACE
        LD A,21H
        CALL WGET
        LD B,A
        LD A,(QCNT)
        CP B
        JR C,TXSPACE
        JR Z,TXSPACE
        SCF
        RET
TXSPACE LD A,24H
        LD (REGPTR),A
        CALL GETPTR
        LD HL,QBUF
        LD A,(QCNT)
        LD B,A
TXLOOP  LD A,(HL)
        PUSH HL
        CALL RINGWR
        POP HL
        INC HL
        DJNZ TXLOOP
        CALL SETPTR
        LD B,2
        LD A,18H
        CALL WSET
        LD E,20H
        CALL FBCMD
        CP 0FFH
        JR Z,TXFAIL
        LD HL,30000
TXWAIT  PUSH HL
        LD A,2
        CALL WGET
        POP HL
        AND 18H
        CP 10H
        JR Z,TXOK
        CP 08H
        JR Z,TXFAIL
        DEC HL
        LD A,H
        OR L
        JR Z,TXFAIL
        JR TXWAIT
TXOK    LD DE,SENTMSG
        CALL PRINT
        OR A
        RET
TXFAIL  SCF
        RET

; Receive one UDP datagram. W5100 adds 8-byte metadata header.
; RXBUF starts with source IP (4), source port (2), packet length (2).
RXDNS   LD HL,50000
RXWAIT  PUSH HL
        LD A,26H
        CALL WGET
        LD (AVHIGH),A
        LD A,27H
        CALL WGET
        LD (AVLOW),A
        POP HL
        LD A,(AVHIGH)
        OR A
        JR NZ,RXREADY
        LD A,(AVLOW)
        CP 8
        JR NC,RXREADY
        DEC HL
        LD A,H
        OR L
        JP Z,RXFAIL
        JR RXWAIT
RXREADY LD A,1AH
        LD C,60H
        CALL RINGSET
        JP C,RXFAIL
        LD A,28H
        LD (REGPTR),A
        CALL GETPTR
        LD HL,RXBUF
        LD BC,8
        CALL READN
        LD A,(RXBUF+6)
        CP 2
        JR C,RXSIZE
        JP NZ,RXFAIL
        LD A,(RXBUF+7)
        OR A
        JP NZ,RXFAIL
RXSIZE  LD A,(RXBUF+6)
        LD B,A
        LD A,(RXBUF+7)
        LD C,A
        LD (DLEN),BC
        ; Confirm W5100 reports the complete 8-byte header plus payload.
        LD A,C
        ADD A,8
        LD C,A
        LD A,B
        ADC A,0
        LD B,A
        LD A,(AVHIGH)
        CP B
        JP C,RXFAIL
        JR NZ,RXAVOK
        LD A,(AVLOW)
        CP C
        JP C,RXFAIL
RXAVOK  LD BC,(DLEN)
        ; Discard packets not sent by the requested resolver on UDP/53.
        LD HL,RXBUF
        LD DE,DNSIP
        LD B,4
RXSRC   LD A,(DE)
        CP (HL)
        JP NZ,RXFAIL
        INC DE
        INC HL
        DJNZ RXSRC
        LD A,(RXBUF+4)
        OR A
        JP NZ,RXFAIL
        LD A,(RXBUF+5)
        CP 35H
        JP NZ,RXFAIL
        LD BC,(DLEN)
        LD A,B
        OR A
        JR NZ,RXBODY
        LD A,C
        CP 12
        JR C,RXFAIL
RXBODY  LD HL,RXBUF+8
        LD BC,(DLEN)
        CALL READN
        CALL SETPTR
        LD E,40H
        CALL FBCMD
        CP 0FFH
        JP Z,RXFAIL
        LD DE,FROMMSG
        CALL PRINT
        LD HL,RXBUF
        CALL PRTIP
        LD DE,CRLF
        CALL PRINT
        OR A
        RET
RXFAIL  SCF
        RET
; Read BC bytes into HL, reading the selected W5100 RX ring.
READN   LD A,B
        OR C
        RET Z
        PUSH BC
        PUSH HL
        CALL RINGRD
        POP HL
        LD (HL),A
        INC HL
        POP BC
        DEC BC
        JR READN

; Packet parse: check ID, QR, RCODE, QDCOUNT; skip compressed names.
PARSE   LD A,(DNSBUF)
        CP 05AH
        JP NZ,DNFAIL
        LD A,(DNSBUF+1)
        CP 0A5H
        JP NZ,DNFAIL
        LD A,(DNSBUF+2)
        AND 80H
        JP Z,DNFAIL
        LD A,(DNSBUF+2)
        AND 02H                 ; TC: truncated UDP response
        JP NZ,DNFAIL
        LD A,(DNSBUF+3)
        AND 0FH
        JR Z,RCOK
        LD DE,RCMSG
        CALL PRINT
        LD A,(DNSBUF+3)
        AND 0FH
        CALL HEX
        LD DE,CRLF
        CALL PRINT
        OR A
        RET
RCOK    LD A,(DNSBUF+4)
        OR A
        JP NZ,DNFAIL
        LD A,(DNSBUF+5)
        CP 1
        JP NZ,DNFAIL
        LD HL,DNSBUF
        LD BC,(DLEN)
        ADD HL,BC
        LD (ENDPTR),HL
        LD HL,DNSBUF+12
        CALL SKNAME
        JP C,DNFAIL
        LD DE,4
        ADD HL,DE
        CALL CHECKLE
        JP C,DNFAIL
        LD A,(DNSBUF+6)
        OR A
        JP NZ,DNFAIL
        LD A,(DNSBUF+7)
        LD (ANLEFT),A
ANLOOP  LD A,(ANLEFT)
        OR A
        JP Z,ANEND
        CALL SKNAME
        JP C,DNFAIL
        PUSH HL
        LD DE,10
        ADD HL,DE
        CALL CHECKLE
        POP HL
        JP C,DNFAIL
        LD A,(HL)
        LD (RTYPE),A
        INC HL
        LD A,(HL)
        LD (RTYPE+1),A
        INC HL
        LD A,(HL)
        LD (RCLASS),A
        INC HL
        LD A,(HL)
        LD (RCLASS+1),A
        INC HL
        LD DE,4
        ADD HL,DE
        LD A,(HL)
        LD (RLENH),A
        INC HL
        LD A,(HL)
        LD (RLENL),A
        INC HL
        LD (RDPTR),HL
        LD A,(RLENH)
        LD B,A
        LD A,(RLENL)
        LD C,A
        ADD HL,BC
        CALL CHECKLE
        JP C,DNFAIL
        LD (NEXTADR),HL
        LD A,(RTYPE)
        OR A
        JR NZ,ANMORE
        LD A,(RTYPE+1)
        CP 1
        JR NZ,ANMORE
        LD A,(RCLASS)
        OR A
        JR NZ,ANMORE
        LD A,(RCLASS+1)
        CP 1
        JR NZ,ANMORE
        LD A,(RLENH)
        OR A
        JR NZ,ANMORE
        LD A,(RLENL)
        CP 4
        JR NZ,ANMORE
        LD A,(FOUND)
        OR A
        JR NZ,PRTANS
        LD HL,(RDPTR)
        LD DE,FIRSTIP
        LD BC,4
        LDIR                     ; preserve first A record for future callers
PRTANS  LD DE,ADDRMSG
        CALL PRINT
        LD HL,(RDPTR)
        CALL PRTIP
        LD DE,CRLF
        CALL PRINT
        LD A,(FOUND)
        INC A
        LD (FOUND),A
ANMORE  LD HL,(NEXTADR)
        LD A,(ANLEFT)
        DEC A
        LD (ANLEFT),A
        JP ANLOOP
ANEND   LD A,(FOUND)
        OR A
        RET NZ
        LD DE,NOADDR
        CALL PRINT
        OR A
        RET
DNFAIL  SCF
        RET
; Consume QNAME/RR name at HL without following compression pointers.
SKNAME  LD B,40
SKLOOP  CALL CHECKLT
        RET C
        LD A,(HL)
        OR A
        JR Z,SKZERO
        LD C,A
        AND 0C0H
        CP 0C0H
        JR Z,SKCOMP
        OR A
        JR NZ,SKBAD
        LD A,C
        CP 64
        JR NC,SKBAD
        LD E,A
        LD D,0
        INC HL
        ADD HL,DE
        CALL CHECKLE
        RET C
        DJNZ SKLOOP
SKBAD   SCF
        RET
SKZERO  INC HL
        OR A
        RET
SKCOMP  INC HL
        CALL CHECKLT
        RET C
        INC HL
        OR A
        RET
; Check HL < or <= ENDPTR. No external pointer dereference.
CHECKLT PUSH DE
        LD DE,(ENDPTR)
        LD A,H
        CP D
        JR C,CLGOOD
        JR NZ,CLBAD
        LD A,L
        CP E
        JR C,CLGOOD
CLBAD   POP DE
        SCF
        RET
CLGOOD  POP DE
        OR A
        RET
CHECKLE PUSH DE
        LD DE,(ENDPTR)
        LD A,H
        CP D
        JR C,CEGOOD
        JR NZ,CEBAD
        LD A,L
        CP E
        JR C,CEGOOD
        JR Z,CEGOOD
CEBAD   POP DE
        SCF
        RET
CEGOOD  POP DE
        OR A
        RET

; Dotted-decimal IP in (HL)..(HL+3), preserving HL.
PRTIP   PUSH BC
        PUSH HL
        LD B,4
IPSHOW  LD A,(HL)
        CALL PRDEC
        INC HL
        DEC B
        JR Z,IPSDONE
        LD A,'.'
        CALL PUTC
        JR IPSHOW
IPSDONE POP HL
        POP BC
        RET
PRDEC   PUSH BC
        PUSH DE
        LD C,A
        LD B,0
HUNLP   LD A,C
        CP 100
        JR C,HUNDN
        SUB 100
        LD C,A
        INC B
        JR HUNLP
HUNDN   LD D,0
        LD A,B
        OR A
        JR Z,TENPRE
        LD D,1
        ADD A,'0'
        CALL PUTC
TENPRE  LD B,0
TENLP   LD A,C
        CP 10
        JR C,TEND
        SUB 10
        LD C,A
        INC B
        JR TENLP
TEND    LD A,B
        OR A
        JR NZ,TENOUT
        LD A,D
        OR A
        JR Z,ONEOUT
        LD A,'0'
        CALL PUTC
        JR ONEOUT
TENOUT  LD A,B
        ADD A,'0'
        CALL PUTC
ONEOUT  LD A,C
        ADD A,'0'
        CALL PUTC
        POP DE
        POP BC
        RET

BANNER  DEFM 'Zapple-II NSLOOKUP 0.1'
        DEFB 13,10,'$'
USAGE   DEFM 'Usage: NSLOOKUP hostname [DNS-server-IP]'
        DEFB 13,10,'$'
HOSTERR DEFM 'Invalid DNS hostname'
        DEFB 13,10,'$'
SOCKERR DEFM 'No free network sockets'
        DEFB 13,10,'$'
NETMSG  DEFM 'UDP network error or timeout'
        DEFB 13,10,'$'
PARERR  DEFM 'Invalid or truncated DNS response'
        DEFB 13,10,'$'
SOCKMSG DEFM 'Socket '
        DEFB '$'
UDPMSG  DEFM 'UDP socket opened'
        DEFB 13,10,'$'
SENTMSG DEFM 'DNS query sent'
        DEFB 13,10,'$'
WAITMSG DEFM 'Waiting for DNS response...'
        DEFB 13,10,'$'
FROMMSG DEFM 'Reply from '
        DEFB '$'
ADDRMSG DEFM 'Address: '
        DEFB '$'
NOADDR  DEFM 'No IPv4 A records in answer'
        DEFB 13,10,'$'
RCMSG   DEFM 'DNS server RCODE: '
        DEFB '$'
CRLF    DEFB 13,10,'$'
QHEAD   DEFB 05AH,0A5H,1,0,0,1,0,0,0,0,0,0
SZTAB   DEFB 4,8,16,32
DNSIP   DEFB 1,1,1,1
HELD    DEFB 0
SOCKNO  DEFB 0
SOCKHI  DEFB 0
FOUND   DEFB 0
FIRSTIP DEFB 0,0,0,0
QCNT    DEFB 0
QLABL   DEFB 0
HOSTPTR DEFW 0
QSPTR   DEFW 0
QLBPTR  DEFW 0
WADDR   DEFB 0,0
WVAL    DEFB 0
MEMREG  DEFB 0
RBASE   DEFB 0
RMASK   DEFB 0
REGPTR  DEFB 0
PTRHI   DEFB 0
PTRLO   DEFB 0
AVHIGH  DEFB 0
AVLOW   DEFB 0
DLEN    DEFW 0
ENDPTR  DEFW 0
ANLEFT  DEFB 0
RTYPE   DEFB 0,0
RCLASS  DEFB 0,0
RLENH   DEFB 0
RLENL   DEFB 0
RDPTR   DEFW 0
NEXTADR DEFW 0
CMDTXT  DEFS 128
QBUF    DEFS 256
RXBUF   DEFS 520
DNSBUF  EQU RXBUF+8
STACK   DEFS 256
STKTOP
        END
