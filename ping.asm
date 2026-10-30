; Zapple-II PING.COM 6K -- ICMP echo over W5100 IPRAW, Uthernet-II slot 5.
; Usage PING a.b.c.d (numeric IPv4 only). Four echo requests, no clock/RTT.
; Needs one FREE W5100 hardware socket (4 max); NETCCP listeners untouched.
; Private BDOS FA (alloc/free), FB (socket command), F9 (W5100 write).
; Packet ring operations adapted from working NSLOOKUP.COM UDP code.
BDOS    EQU 0005H
        ORG 0100H
START   LD SP,STKTOP
        XOR A
        LD (HELD),A
        LD (OKCNT),A
        CALL SETPORT
        LD DE,TITLE
        CALL PRINT
        CALL ARGS
        JP C,BADARG
        CALL PICK
        JP C,NOSOCK
        CALL RAWOPEN
        JP C,NETERR
        LD A,1
        LD (SEQ),A
PINGLP  CALL ECHOPKT
        CALL TXECHO
        JR C,PTIME
        CALL RXECHO
        JR C,PTIME
        LD DE,REPLY
        CALL PRINT
        LD HL,DSTIP
        CALL PRTIP
        LD DE,SEQMSG
        CALL PRINT
        LD A,(SEQ)
        CALL DEC8
        LD DE,CRLF
        CALL PRINT
        LD A,(OKCNT)
        INC A
        LD (OKCNT),A
        JR PNEXT
PTIME   LD DE,TIMOUT
        CALL PRINT
PNEXT   LD A,(SEQ)
        INC A
        LD (SEQ),A
        CP 5
        JR NZ,PINGLP
        LD DE,SUMMSG
        CALL PRINT
        LD A,(OKCNT)
        CALL DEC8
        LD DE,SUFFIX
        CALL PRINT
        JP EXIT
BADARG  LD DE,USAGE
        JR ERROR
NOSOCK  LD DE,NOMORE
        JR ERROR
NETERR  LD DE,FAILMSG
ERROR   CALL PRINT
EXIT    CALL RELEASE
        LD C,0
        JP BDOS
; Read command tail; numeric four-octet IPv4 only.
ARGS    LD A,(0080H)
        CP 126
        JR NC,ARGERR
        LD B,A
        LD HL,0081H
        LD DE,TAIL
ARGCPY  LD A,B
        OR A
        JR Z,ACPDON
        LD A,(HL)
        LD (DE),A
        INC HL
        INC DE
        DJNZ ARGCPY
ACPDON  XOR A
        LD (DE),A
        LD HL,TAIL
        CALL SKIPSP
        LD DE,DSTIP
        LD B,4
AIPLP   PUSH BC
        PUSH DE
        CALL OCTET
        POP DE
        POP BC
        JR C,ARGERR
        LD (DE),A
        INC DE
        DEC B
        JR Z,AILAST
        LD A,(HL)
        CP '.'
        JR NZ,ARGERR
        INC HL
        JR AIPLP
AILAST  CALL SKIPSP
        LD A,(HL)
        OR A
        JR NZ,ARGERR
        OR A
        RET
ARGERR  SCF
        RET
SKIPSP  LD A,(HL)
        CP ' '
        JR Z,SKIP1
        CP 9
        RET NZ
SKIP1   INC HL
        JR SKIPSP
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
        LD A,C
        CP 4
        JR NC,OCTBAD
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
; ICMP 8-byte header, type 8 code 0, ID 5AA5, sequence 0001..0004.
; 16-bit one's-complement checksum: ~(0800h+5AA5h+SEQ)=9D5Ah-SEQ.
ECHOPKT LD A,(SEQ)
        LD (PKT+7),A
        LD E,A
        LD D,0
        LD HL,09D5AH
        OR A
        SBC HL,DE
        LD A,H
        LD (PKT+2),A
        LD A,L
        LD (PKT+3),A
        RET
; Use W5100 RAW IP socket on one owned hardware socket.
RAWOPEN LD E,0
        CALL FBCMD
        OR A
        JR NZ,RAWBAD
        LD B,0
        LD A,3
        CALL WSET                 ; Sn_MR IPRAW
        LD B,014H
        LD A,1
        CALL WSET                 ; Sn_PROTO ICMP
        LD HL,DSTIP
        LD B,0CH
        LD C,4
RDEST   LD A,(HL)
        PUSH BC
        PUSH HL
        CALL WSET                 ; Sn_DIPR0..3
        POP HL
        POP BC
        INC B
        INC HL
        DEC C
        JR NZ,RDEST
        LD E,1
        CALL FBCMD                ; OPEN
        CP 0FFH
        JR Z,RAWBAD
        LD E,0
        CALL FBCMD                ; STATUS
        CP 032H                 ; SOCK_IPRAW
        JR NZ,RAWBAD
        OR A
        RET
RAWBAD  SCF
        RET
; TX: exactly one ICMP message in hardware ring, one SEND.
TXECHO  LD A,1BH
        LD C,40H
        CALL RINGSET
        RET C
        LD A,20H
        CALL WGET
        OR A
        JR NZ,TXSPACE
        LD A,21H
        CALL WGET
        CP 8
        JR C,TXFAIL
TXSPACE LD A,24H
        LD (REGPTR),A
        CALL GETPTR
        LD HL,PKT
        LD B,8
TXLOOP  LD A,(HL)
        PUSH HL
        PUSH BC
        CALL RINGWR
        POP BC
        POP HL
        INC HL
        DJNZ TXLOOP
        CALL SETPTR
        LD B,2
        LD A,018H
        CALL WSET                 ; clear SENDOK/TIMEOUT
        LD E,020H
        CALL FBCMD                ; SEND
        CP 0FFH
        JR Z,TXFAIL
        OR A
        RET
TXFAIL  SCF
        RET
; Expect W5100 IPRAW receive format: src IPv4 (4), length (2),
; followed by ICMP echo reply (8). W5100 owns IPv4 header generation.
RXECHO  LD HL,10000            ; bounded by polls, NOT wall-clock seconds
RXWAIT  PUSH HL
        LD C,11                 ; BDOS status: let scheduler advance
        CALL BDOS
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
        CP 14
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
        LD BC,6
        CALL READN
        ; Full packet may exceed 8 ICMP bytes. Do not overrun RXBUF.
        LD A,(RXBUF+4)
        OR A
        JR NZ,RXSKIP
        LD A,(RXBUF+5)
        CP 8
        JR C,RXSKIP
        LD (RXLEN),A
        LD B,A
        LD C,A
        LD HL,RXBUF+6
        LD A,C
        CP 8
        JR C,RXSKIP
        LD BC,8
        CALL READN
        ; Ignore extra payload if any (for unexpected ICMP data).
        LD A,(RXLEN)
        SUB 8
        LD B,A
RXSPLUS LD A,B
        OR A
        JR Z,RXACK
        PUSH BC
        CALL RINGRD
        POP BC
        DJNZ RXSPLUS
        JR RXACK
RXSKIP  ; malformed frame: abandon this ping (socket closed on EXIT).
        JR RXFAIL
RXACK   CALL SETPTR
        LD E,40H
        CALL FBCMD
        CP 0FFH
        JR Z,RXFAIL
        LD HL,RXBUF
        LD DE,DSTIP
        LD B,4
RXIPCHK LD A,(DE)
        CP (HL)
        JR NZ,RXFAIL
        INC HL
        INC DE
        DJNZ RXIPCHK
        LD A,(RXBUF+6)
        OR A
        JR NZ,RXFAIL
        LD A,(RXBUF+7)
        OR A
        JR NZ,RXFAIL
        LD A,(RXBUF+10)
        CP 05AH
        JR NZ,RXFAIL
        LD A,(RXBUF+11)
        CP 0A5H
        JR NZ,RXFAIL
        LD A,(RXBUF+12)
        OR A
        JR NZ,RXFAIL
        LD A,(SEQ)
        LD B,A
        LD A,(RXBUF+13)
        CP B
        JR NZ,RXFAIL
        OR A
        RET
RXFAIL  SCF
        RET
; Common output helpers.
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
PRTIP   LD B,4
IPSHOW  LD A,(HL)
        CALL DEC8
        INC HL
        DEC B
        RET Z
        LD A,'.'
        CALL PUTC
        JR IPSHOW
DEC8    PUSH BC
        LD C,A
        LD B,0
        LD A,C
DC100   CP 100
        JR C,DC100E
        SUB 100
        INC B
        JR DC100
DC100E  LD C,A
        LD A,B
        LD (HUND),A
        OR A
        JR Z,DC10S
        ADD A,'0'
        CALL PUTC
DC10S   LD B,0
        LD A,C
DC10    CP 10
        JR C,DC10E
        SUB 10
        INC B
        JR DC10
DC10E   LD C,A
        LD A,B
        OR A
        JR NZ,DC10P
        LD A,(HUND)
        OR A
        JR Z,DCONE
        XOR A
DC10P   ADD A,'0'
        CALL PUTC
DCONE   LD A,C
        ADD A,'0'
        CALL PUTC
        POP BC
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
        CALL DEC8                ; socket 0..3, print decimal
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


TITLE   DEFM 'Zapple-II PING 6K (ICMP / W5100 IPRAW)'
        DEFB 13,10,'$'
USAGE   DEFM 'Usage: PING a.b.c.d (numeric IP)'
        DEFB 13,10,'$'
SOCKMSG DEFM 'Using W5100 socket $'
NOMORE  DEFM 'No free W5100 socket (4 total)'
        DEFB 13,10,'$'
FAILMSG DEFM 'Cannot open ICMP IPRAW socket'
        DEFB 13,10,'$'
REPLY   DEFM 'Reply from $'
SEQMSG  DEFM ' seq=$'
TIMOUT  DEFM 'Request timed out or unexpected ICMP reply'
        DEFB 13,10,'$'
SUMMSG  DEFM 'Echo replies: $'
SUFFIX  DEFM '/4'
        DEFB 13,10,'$'
CRLF    DEFB 13,10,'$'
SZTAB   DEFB 4,8,16,32
PKT     DEFB 8,0,09DH,059H,05AH,0A5H,0,1
DSTIP   DEFB 0,0,0,0
SOCKNO  DEFB 0
SOCKHI  DEFB 0
HELD    DEFB 0
OKCNT   DEFB 0
SEQ     DEFB 0
RXLEN   DEFB 0
HUND    DEFB 0
AVHIGH  DEFB 0
AVLOW   DEFB 0
WADDR   DEFB 0,0
WVAL    DEFB 0
MEMREG  DEFB 0
RBASE   DEFB 0
RMASK   DEFB 0
REGPTR  DEFB 0
PTRHI   DEFB 0
PTRLO   DEFB 0
TAIL    DEFS 128
RXBUF   DEFS 16
STACK   DEFS 256
STKTOP
        END
