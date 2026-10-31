; Zapple-II DHCP.COM (Phase 6N.0) - one-shot DHCPv4 client
; W5100 Uthernet-II, fixed physical slot 5. Udo Munk z80asm 1.1.
; Tested only by static review: hardware testing is REQUIRED.
; No kernel changes. Uses FA socket ownership, F9 hardware writes,
; FD E=7 kernel DNS setter. Does not modify ZAPPLE2.CNF.
;
; Safety: refuses to touch W5100 IP if ANY socket is active, including
; external VEDRIVE sockets. Only after this guard may SIPR become 0.0.0.0.
; The previous SIPR is restored on failure. Renewals/ARP probes TBD.
; Run BEFORE starting VEDRIVE or NETCCP/TELNET sessions.
;
BDOS    EQU 0005H
        ORG 0100H
START   LD SP,STKTOP
        XOR A
        LD (HELD),A
        CALL SETPORT
        LD DE,BANNER
        CALL PRINT
        CALL TESTCHIP
        JP C,CHIPERR
        CALL CHECKSK
        JP C,BUSYERR
        CALL SAVECFG
        CALL MAKEREQ
        JP C,MACERR
        CALL PICK
        JP C,SOCKERR
        CALL ZEROIP
        CALL UDPOPEN
        JP C,NETERR
        LD DE,DISCMSG
        CALL PRINT
        LD A,1
        CALL BUILTOPT
        LD A,3
        LD (RETRIES),A
DODISC  CALL TXPKT
        JP C,NETERR
        CALL WAITPKT
        JP C,DISCAGN
        CP 2                         ; DHCPOFFER
        JP NZ,DISCAGN
        CALL GETOFFR
        JP NC,GOTO_REQ
DISCAGN LD A,(RETRIES)
        DEC A
        LD (RETRIES),A
        JP NZ,DODISC
        JP TIMERR
GOTO_REQ LD DE,REQMSG
        CALL PRINT
        LD A,3
        CALL BUILTOPT
        LD A,3
        LD (RETRIES),A
DOREQ   CALL TXPKT
        JP C,NETERR
        CALL WAITPKT
        JP C,REQAGAIN
        CP 6                         ; DHCPNAK
        JP Z,NAKERR
        CP 5                         ; DHCPACK
        JP NZ,REQAGAIN
        CALL CHECKAK
        JP NC,ACKGOOD
REQAGAIN LD A,(RETRIES)
        DEC A
        LD (RETRIES),A
        JP NZ,DOREQ
        JP TIMERR
ACKGOOD ; Socket must be closed BEFORE changing common W5100 IP.
        CALL RELEASE
        JP C,NETERR
        CALL APPLYC
        LD DE,DONEMSG
        CALL PRINT
        LD HL,YIADDR
        CALL PRINTIP
        LD DE,CRLF
        CALL PRINT
        LD DE,RENEWMS
        CALL PRINT
        JP FINISH
CHIPERR LD DE,CHIPMSG
        JP ERROR0
MACERR  LD DE,MACMSG
        JP ERROR0
BUSYERR LD DE,BUSYMSG
        JP ERROR0
SOCKERR LD DE,SOCKMSG
        JP ERROR0
NETERR  LD DE,NETMSG
        JP ERROR1
TIMERR  LD DE,TIMMSG
        JP ERROR1
PROTOER LD DE,PROTO
        JP ERROR1
NAKERR  LD DE,NAKMSG
ERROR1  CALL PRINT
        CALL RELEASE
        CALL RESTIP
        JP FINISH
ERROR0  CALL PRINT
FINISH  LD C,0
        JP BDOS

; Print strings via CP/M BDOS 9, single characters BDOS 2.
PRINT   PUSH AF
        PUSH BC
        PUSH DE
        PUSH HL
        LD C,9
        CALL BDOS
        POP HL
        POP DE
        POP BC
        POP AF
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
; Output unsigned byte A in dotted IPv4.
PRINTIP LD B,4
PIPLOOP LD A,(HL)
        CALL DEC8
        INC HL
        DEC B
        RET Z
        LD A,'.'
        CALL PUTC
        JP PIPLOOP
DEC8    PUSH BC
        PUSH DE
        PUSH HL
        LD C,A
        LD B,0
D100    LD A,C
        CP 100
        JP C,D10A
        SUB 100
        LD C,A
        INC B
        JP D100
D10A    LD A,B
        LD D,A
        OR A
        JP Z,D10B
        ADD A,'0'
        CALL PUTC
D10B    LD B,0
D10LP   LD A,C
        CP 10
        JP C,D10END
        SUB 10
        LD C,A
        INC B
        JP D10LP
D10END  LD A,B
        OR A
        JP NZ,D10PR
        LD A,D
        OR A
        JP Z,D1PR
        XOR A
D10PR   ADD A,'0'
        CALL PUTC
D1PR    LD A,C
        ADD A,'0'
        CALL PUTC
        POP HL
        POP DE
        POP BC
        RET

; Native read port (Z80) and kernel F9 common register write.
; Keep the exact 6K/6L bridge pattern, slot fixed at 5.
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
; B=socket register offset, A=value.
WSET    PUSH HL
        PUSH AF
        LD A,(SOCKHI)
        LD H,A
        LD L,B
        POP AF
        CALL WWRITE
        POP HL
        RET
; A=socket register offset, return A=value.
WGET    PUSH HL
        LD L,A
        LD A,(SOCKHI)
        LD H,A
        CALL WREAD
        POP HL
        RET
; Only operate when W5100 indirect bus mode is enabled.
; $FF readback indicates no supported card (e.g. MAME without Uthernet).
TESTCHIP CALL MOD001
        CP 0FFH
        JP Z,CHIPBAD
        AND 1
        JP Z,CHIPBAD
        OR A
        RET
CHIPBAD SCF
        RET
; Guard physically used sockets, including unmanaged VEDRIVE!
CHECKSK LD HL,0403H
        LD B,4
CKLOOP  CALL WREAD
        OR A
        JP NZ,CKBAD
        INC H
        DJNZ CKLOOP
        OR A
        RET
CKBAD   SCF
        RET
; Remember W5100 IPv4, restore on failure.
SAVECFG LD HL,000FH
        LD DE,OLDIP
        LD B,4
SVLOOP  CALL WREAD
        LD (DE),A
        INC DE
        INC HL
        DJNZ SVLOOP
        RET
ZEROIP  LD HL,000FH
        LD B,4
ZIPLOOP XOR A
        CALL WWRITE
        INC HL
        DJNZ ZIPLOOP
        RET
RESTIP  LD HL,OLDIP
        LD DE,000FH
        LD B,4
RSLOOP  LD A,(HL)
        EX DE,HL
        CALL WWRITE
        EX DE,HL
        INC HL
        INC DE
        DJNZ RSLOOP
        RET

; Kernel W5100 socket ownership API ($FA) and serialized FB commands.
PICK    LD E,0
        LD C,0FAH
        CALL BDOS
        CP 4
        JP NC,PICKERR
        LD (SOCKNO),A
        ADD A,4
        LD (SOCKHI),A
        LD A,1
        LD (HELD),A
        OR A
        RET
PICKERR SCF
        RET
RELEASE LD A,(HELD)
        OR A
        RET Z
        LD A,(SOCKNO)
        LD D,A
        LD E,1
        LD C,0FAH
        CALL BDOS
        CP 0FFH
        JP Z,RELFAIL
        XOR A
        LD (HELD),A
        RET
RELFAIL SCF
        RET
FBCMD   LD A,(SOCKNO)
        LD D,A
        LD C,0FBH
        CALL BDOS
        RET
FBGET   LD E,0
        CALL FBCMD
        RET
; UDP src port 68, destination broadcast port 67.
UDPOPEN CALL FBGET
        OR A
        JP NZ,UDPBAD
        LD B,0
        LD A,2
        CALL WSET
        LD B,4
        XOR A
        CALL WSET                ; Sn_PORT high
        LD B,5
        LD A,68
        CALL WSET
        LD B,0CH
        LD A,255
        CALL WSET
        LD B,0DH
        CALL WSET
        LD B,0EH
        CALL WSET
        LD B,0FH
        CALL WSET
        LD B,10H
        XOR A
        CALL WSET
        LD B,11H
        LD A,67
        CALL WSET
        LD E,1
        CALL FBCMD
        CP 0FFH
        JP Z,UDPBAD
        CALL FBGET
        CP 22H                     ; SOCK_UDP
        JP NZ,UDPBAD
        OR A
        RET
UDPBAD  SCF
        RET

; W5100 per-socket ring layout (preserves VEDRIVE socket sizes).
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
        JP Z,RINGCUR
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
        JP RINGLP
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
        JP NC,RINGBAD
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

; 300-byte BOOTP/DHCP datagram, filled with zeros before every send.
; Header offsets: XID 4, flags 10, ciaddr 12, chaddr 28.
; Magic cookie at 236 and DHCP options at 240.
MAKEREQ LD HL,PKTBUF
        XOR A
        LD (HL),A
        LD DE,PKTBUF+1
        LD BC,319
        LDIR
        LD A,1
        LD (PKTBUF),A          ; BOOTREQUEST
        LD (PKTBUF+1),A        ; Ethernet
        LD A,6
        LD (PKTBUF+2),A
        LD A,080H
        LD (PKTBUF+10),A       ; broadcast flag
        LD A,R
        XOR 0A7H
        LD (PKTBUF+4),A       ; XID, same in DISCOVER/REQUEST
        LD HL,0009H           ; W5100 SHAR hardware address
        LD DE,PKTBUF+28
        LD B,6
MACLOOP CALL WREAD
        LD (DE),A
        INC DE
        INC HL
        DJNZ MACLOOP
        LD HL,PKTBUF+28
        CALL NONZERO
        JP Z,MKFAIL
        LD A,(PKTBUF+28)
        AND 1                       ; reject multicast/broadcast source MAC
        JP NZ,MKFAIL
        LD A,(PKTBUF+28)
        XOR 05AH
        LD (PKTBUF+5),A
        LD A,(PKTBUF+31)
        XOR 0C3H
        LD (PKTBUF+6),A
        LD A,(PKTBUF+33)
        XOR 031H
        LD (PKTBUF+7),A
        LD HL,COOKIE
        LD DE,PKTBUF+236
        LD BC,4
        LDIR
        OR A
        RET
MKFAIL  SCF
        RET
; A=DHCP message type (1 discover,3 request); stable 300 bytes.
BUILTOPT LD (MSGTYPE),A
        LD HL,PKTBUF+240
        LD A,53
        LD (HL),A
        INC HL
        LD A,1
        LD (HL),A
        INC HL
        LD A,(MSGTYPE)
        LD (HL),A
        INC HL
        LD A,(MSGTYPE)
        CP 3
        JP NZ,BDISC
        LD A,50                ; requested IPv4
        LD (HL),A
        INC HL
        LD A,4
        LD (HL),A
        INC HL
        LD DE,OFFERIP
        LD B,4
OPTREQ1 LD A,(DE)
        LD (HL),A
        INC DE
        INC HL
        DJNZ OPTREQ1
        LD A,54                ; selected server ID
        LD (HL),A
        INC HL
        LD A,4
        LD (HL),A
        INC HL
        LD DE,SERVERIP
        LD B,4
OPTREQ2 LD A,(DE)
        LD (HL),A
        INC DE
        INC HL
        DJNZ OPTREQ2
BDISC   LD A,55                ; parameter request list
        LD (HL),A
        INC HL
        LD A,4
        LD (HL),A
        INC HL
        LD (HL),1              ; subnet
        INC HL
        LD (HL),3              ; router
        INC HL
        LD (HL),6              ; DNS
        INC HL
        LD (HL),51             ; lease time
        INC HL
        LD (HL),255            ; end, trailing zero padding
        RET

; Single UDP SEND, never use multi-send stream API.
TXPKT   LD A,1BH
        LD C,40H
        CALL RINGSET
        JP C,TXFAIL
        ; Check Sn_TX_FSR (0020h+socket base) >= 300 bytes.
        LD A,20H
        CALL WGET
        CP 1
        JP C,TXFAIL
        JP NZ,TXSPACE
        LD A,21H
        CALL WGET
        CP 02CH                 ; 300-256 = 44
        JP C,TXFAIL
TXSPACE LD A,24H
        LD (REGPTR),A
        CALL GETPTR
        LD HL,PKTBUF
        LD BC,300
TXLOOP  LD A,(HL)
        PUSH HL
        CALL RINGWR
        POP HL
        INC HL
        DEC BC
        LD A,B
        OR C
        JP NZ,TXLOOP
        CALL SETPTR
        LD B,2
        LD A,018H               ; clear SEND_OK/TIMEOUT interrupts
        CALL WSET
        LD E,20H                ; SEND
        CALL FBCMD
        CP 0FFH
        JP Z,TXFAIL
        LD HL,45000
TXWAIT  PUSH HL
        LD A,2
        CALL WGET
        POP HL
        AND 018H
        CP 010H
        JP Z,TXOK
        CP 008H
        JP Z,TXFAIL
        DEC HL
        LD A,H
        OR L
        JP NZ,TXWAIT
TXFAIL  SCF
        RET
TXOK    OR A
        RET

; Poll incoming UDP datagram. A=DHCP message type or 0 if no valid
; answer. RX hardware prefixes payload with 8-byte source header.
; Incoming packets over 576 bytes are consumed and discarded safely.
WAITPKT LD HL,60000
        LD A,0
        LD (TICK),A
WAITLP  PUSH HL
        CALL RXPOLL
        POP HL
        OR A
        RET NZ
        DEC HL
        LD A,H
        OR L
        JP Z,WTOUT
        LD A,(TICK)
        DEC A
        LD (TICK),A
        JP NZ,WAITLP
        PUSH HL
        LD C,11                ; BDOS console status: cooperative yield
        CALL BDOS
        POP HL
        JP WAITLP
WTOUT   SCF
        RET
RXPOLL  LD A,26H
        CALL WGET
        LD (AVAIL+1),A
        LD A,27H
        CALL WGET
        LD (AVAIL),A
        LD HL,(AVAIL)
        LD DE,8
        OR A
        SBC HL,DE
        JP C,RXNONE
        LD A,1AH
        LD C,60H
        CALL RINGSET
        JP C,RXNONE
        LD A,28H
        LD (REGPTR),A
        CALL GETPTR
        LD HL,PKTHEAD
        LD BC,8
        CALL READN
        LD A,(PKTHEAD+6)
        LD H,A
        LD A,(PKTHEAD+7)
        LD L,A
        LD (DLEN),HL
        ; Check packet complete before acknowledging it.
        LD DE,8
        ADD HL,DE
        EX DE,HL
        LD HL,(AVAIL)
        OR A
        SBC HL,DE
        JP C,RXNONE
        LD A,(PKTHEAD+4)
        OR A
        JP NZ,RXSKIP
        LD A,(PKTHEAD+5)
        CP 67                 ; DHCP server UDP port
        JP NZ,RXSKIP
        LD HL,(DLEN)
        LD DE,240
        OR A
        SBC HL,DE
        JP C,RXSKIP
        LD HL,(DLEN)
        LD DE,577
        OR A
        SBC HL,DE
        JP NC,RXSKIP
        LD HL,RXBUF
        LD BC,(DLEN)
        CALL READN
        CALL SETPTR
        LD E,40H              ; RECV
        CALL FBCMD
        JP PARSEPK
RXSKIP  LD HL,(DLEN)
        LD A,(PTRLO)
        ADD A,L
        LD (PTRLO),A
        LD A,(PTRHI)
        ADC A,H
        LD (PTRHI),A
        CALL SETPTR
        LD E,40H
        CALL FBCMD
RXNONE  XOR A
        RET
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
        JP READN

; Verify BOOTREPLY, Ethernet MAC, same XID, cookie; parse bounded TLVs.
PARSEPK LD A,(RXBUF)
        CP 2
        JP NZ,PKBAD
        LD A,(RXBUF+1)
        CP 1
        JP NZ,PKBAD
        LD A,(RXBUF+2)
        CP 6
        JP NZ,PKBAD
        LD HL,RXBUF+4
        LD DE,PKTBUF+4
        LD B,4
        CALL CMPRNG
        JP NZ,PKBAD
        LD HL,RXBUF+28
        LD DE,PKTBUF+28
        LD B,6
        CALL CMPRNG
        JP NZ,PKBAD
        LD HL,RXBUF+236
        LD DE,COOKIE
        LD B,4
        CALL CMPRNG
        JP NZ,PKBAD
        ; Only authenticated-by-XID replies are considered, not security!
        LD HL,RXBUF+16
        LD DE,YIADDR
        LD BC,4
        LDIR
        LD HL,OPTMES
        LD B,21             ; OPTMES+server/mask/router/DNS/lease
        XOR A
PZLOOP  LD (HL),A
        INC HL
        DJNZ PZLOOP
        LD HL,(DLEN)
        LD DE,240
        OR A
        SBC HL,DE
        LD B,H
        LD C,L
        LD HL,RXBUF+240
PLOOP   LD A,B
        OR C
        JP Z,PDONE
        LD A,(HL)
        INC HL
        DEC BC
        CP 255
        JP Z,PDONE
        OR A
        JP Z,PLOOP
        LD (OPTID),A
        LD A,B
        OR C
        JP Z,PKBAD
        LD A,(HL)
        INC HL
        DEC BC
        LD (OPTLEN),A
        LD E,A
        LD D,0
        PUSH HL
        LD H,B
        LD L,C
        OR A
        SBC HL,DE
        POP HL
        JP C,PKBAD
        LD A,(OPTID)
        CP 53
        JP Z,OPTTYPE
        CP 54
        JP Z,OPTSERV
        CP 1
        JP Z,OPTMASK
        CP 3
        JP Z,OPTGATE
        CP 6
        JP Z,OPTDNS
        CP 51
        JP Z,OPTLEASE
        JP PSKIP
OPTTYPE LD A,(OPTLEN)
        CP 1
        JP NZ,PSKIP
        LD A,(HL)
        LD (OPTMES),A
        JP PSKIP
OPTSERV LD A,(OPTLEN)
        CP 4
        JP NZ,PSKIP
        LD DE,STGSRV
        CALL CP4
        JP PSKIP
OPTMASK LD A,(OPTLEN)
        CP 4
        JP NZ,PSKIP
        LD DE,STGMASK
        CALL CP4
        JP PSKIP
OPTGATE LD A,(OPTLEN)
        CP 4
        JP C,PSKIP
        LD DE,STGGW
        CALL CP4
        JP PSKIP
OPTDNS  LD A,(OPTLEN)
        CP 4
        JP C,PSKIP
        LD DE,STGDNS
        CALL CP4
        JP PSKIP
OPTLEASE LD A,(OPTLEN)
        CP 4
        JP NZ,PSKIP
        LD DE,STGLEAS
        CALL CP4
PSKIP   LD A,(OPTLEN)
        LD E,A
        LD D,0
        ADD HL,DE
        PUSH HL
        LD H,B
        LD L,C
        OR A
        SBC HL,DE
        LD B,H
        LD C,L
        POP HL
        JP PLOOP
CP4     PUSH BC
        PUSH HL
        LD BC,4
        LDIR
        POP HL
        POP BC
        RET
CMPRNG  LD A,(DE)
        CP (HL)
        RET NZ
        INC DE
        INC HL
        DJNZ CMPRNG
        XOR A
        RET
PDONE   LD A,(OPTMES)
        RET
PKBAD   XOR A
        RET

; OFFER: require nonzero yiaddr and server id option 54.
GETOFFR LD HL,YIADDR
        CALL NONZERO
        JP Z,OFFERBAD
        LD HL,STGSRV
        CALL NONZERO
        JP Z,OFFERBAD
        LD HL,YIADDR
        LD DE,OFFERIP
        LD BC,4
        LDIR
        LD HL,STGSRV
        LD DE,SERVERIP
        LD BC,4
        LDIR
        OR A
        RET
OFFERBAD SCF
        RET
; ACK: same offered IP and same server, with valid subnet mask.
CHECKAK LD HL,YIADDR
        LD DE,OFFERIP
        LD B,4
        CALL CMPRNG
        JP NZ,ACKBAD
        LD HL,STGSRV
        LD DE,SERVERIP
        LD B,4
        CALL CMPRNG
        JP NZ,ACKBAD
        LD HL,STGMASK
        CALL NONZERO
        JP Z,ACKBAD
        OR A
        RET
ACKBAD  SCF
        RET
NONZERO LD B,4
        LD C,0
NZLOOP  LD A,(HL)
        OR C
        LD C,A
        INC HL
        DJNZ NZLOOP
        LD A,C
        OR A
        RET
; Apply ACK router/mask first, assigned IP last. DNS via kernel FD.
APPLYC  LD HL,STGGW
        LD DE,0001H
        CALL WRITE4
        LD HL,STGMASK
        LD DE,0005H
        CALL WRITE4
        LD HL,YIADDR
        LD DE,000FH
        CALL WRITE4
        LD HL,STGDNS
        CALL NONZERO
        RET Z
        LD HL,STGDNS
        LD D,0
DNSLOOP LD B,(HL)
        LD E,7
        LD C,0FDH
        PUSH HL
        PUSH DE
        CALL BDOS
        POP DE
        POP HL
        INC HL
        INC D
        LD A,D
        CP 4
        JP NZ,DNSLOOP
        RET
WRITE4  LD B,4
WR4LOOP LD A,(HL)
        EX DE,HL
        CALL WWRITE
        EX DE,HL
        INC DE
        INC HL
        DJNZ WR4LOOP
        RET

BANNER  DEFM 'Zapple-II DHCP 6N.0'
        DEFB 13,10,'$'
CHIPMSG DEFM 'DHCP: W5100 absent or not in indirect mode.'
        DEFB 13,10,'$'
MACMSG  DEFM 'DHCP: W5100 hardware MAC is not usable.'
        DEFB 13,10,'$'
BUSYMSG DEFM 'DHCP refused: active W5100 socket(s), including VEDRIVE.'
        DEFB 13,10,'$'
SOCKMSG DEFM 'DHCP: no unowned W5100 socket.'
        DEFB 13,10,'$'
NETMSG  DEFM 'DHCP: W5100 UDP / SEND failed.'
        DEFB 13,10,'$'
TIMMSG  DEFM 'DHCP: no reply before timeout.'
        DEFB 13,10,'$'
PROTO   DEFM 'DHCP: malformed or mismatched offer/ack.'
        DEFB 13,10,'$'
NAKMSG DEFM 'DHCP: server rejected address (NAK).'
        DEFB 13,10,'$'
DISCMSG DEFM 'DHCP DISCOVER...'
        DEFB 13,10,'$'
REQMSG  DEFM 'DHCP REQUEST...'
        DEFB 13,10,'$'
DONEMSG DEFM 'DHCP address: $'
RENEWMS DEFM 'One-shot lease: renew manually before expiry.'
        DEFB 13,10,'$'
CRLF    DEFB 13,10,'$'
COOKIE  DEFB 99,130,83,99
SZTAB   DEFB 4,8,16,32
HELD    DEFB 0
SOCKNO  DEFB 0
SOCKHI  DEFB 0
MSGTYPE DEFB 0
TICK    DEFB 0
RETRIES DEFB 0
WADDR   DEFB 0,0
WVAL    DEFB 0
MEMREG  DEFB 0
RBASE   DEFB 0
RMASK   DEFB 0
REGPTR  DEFB 0
PTRHI   DEFB 0
PTRLO   DEFB 0
AVAIL   DEFW 0           ; little endian, W5100 MSB at AVAIL+1
DLEN    DEFW 0
OLDIP   DEFB 0,0,0,0
OFFERIP DEFB 0,0,0,0
SERVERIP DEFB 0,0,0,0
YIADDR  DEFB 0,0,0,0
OPTMES  DEFB 0
STGSRV  DEFB 0,0,0,0
STGMASK DEFB 0,0,0,0
STGGW   DEFB 0,0,0,0
STGDNS  DEFB 0,0,0,0
STGLEAS DEFB 0,0,0,0
OPTID   DEFB 0
OPTLEN  DEFB 0
PKTHEAD DEFS 8
PKTBUF  DEFS 320
RXBUF   DEFS 576
STACK   DEFS 256
STKTOP
        END
