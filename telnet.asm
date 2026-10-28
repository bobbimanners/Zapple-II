; TELNET.COM v1.7 - Zapple-II / CP/M 2.2 / Uthernet II W5100
; Udo Munk Z80ASM dialect.  Standalone: NO resident kernel changes.
; Configuration is TELNET.CFG on the current drive/user.
; NOTE: RESET=1 RESETS THE ENTIRE W5100, INCLUDING VEDRIVE CONNECTIONS.
; With RESET=0, attach to existing chip configuration without altering it.
; Compatible with VEDRIVE only if socket 1 is unused; check for mismatches.
; Socket 1, dynamic TX/RX bases and sizes from W5100 allocation registers.
; Full trace before/after every important hardware phase.
;
; Z80 SoftCard mapping: Apple II $C0n0-$C0nF => Z80 $E0n0-$E0nF.
; Apple slot s (1..7) => low byte $80 + 16*s; ports +4,5,6,7.

BDOS          EQU   0005H
S1MR          EQU   0500H
S1CR          EQU   0501H
S1IR          EQU   0502H
S1SR          EQU   0503H
S1PORT        EQU   0504H
S1DIP         EQU   050CH
S1DPORT       EQU   0510H
S1TXFSR       EQU   0520H
S1TXWR        EQU   0524H
S1RXRSR       EQU   0526H
S1RXRD        EQU   0528H
; TX/RX socket 1 buffer addresses are determined at run time.

              ORG   0100H
START         LD    SP,STACKTOP
              LD    DE,MSG_BANNER
              CALL  PRINT
              CALL  CONFIG_READ
              JP    C,FATAL_CFG
              CALL  PRINT_CFG
              CALL  VALIDATE_CFG
              JP    C,FATAL_CFG
              LD    A,(CFG_SLOTNUM)
              CP    5
              JP    NZ,FATAL_CFG
              LD    A,(CFG_RESETFLAG)
              OR    A
              JP    NZ,FATAL_CFG
              CALL  SET_SLOT_IO
              LD    DE,MSG_HW
              CALL  PRINT
              CALL  HW_INIT
              JP    C,FATAL_HW
              CALL  SOCK_SETUP
              JP    C,FATAL_SOCK
              LD    DE,MSG_CONNECT
              CALL  PRINT
              CALL  SOCK_CONNECT
              JP    C,FATAL_CONN
              LD    DE,MSG_CONNECTED
              CALL  PRINT
              JP    MAIN_LOOP
FATAL_CFG     LD    DE,MSG_BADCFG
              JP    ERROR_EXIT
FATAL_HW      LD    DE,MSG_BADHW
              JP    ERROR_EXIT
FATAL_SOCK    LD    DE,MSG_BADSOCK
              JP    ERROR_EXIT
FATAL_CONN    LD    DE,MSG_BADCONN
              CALL  PRINT
              LD    DE,MSG_CONN_CLEAN
              CALL  PRINT
              LD    A,010H                 ; we own socket 1 after successful OPEN
              CALL  COMMAND              ; close failed connection before leaving
              JP    EXIT
ERROR_EXIT    CALL  PRINT
              JP    EXIT
EXIT          LD    DE,MSG_EXIT
              CALL  PRINT
              LD    C,0
              JP    BDOS

; BDOS 9 '$'-terminated message. Preserve the working caller's BC/HL.
PRINT         PUSH  BC
              PUSH  HL
              LD    C,9
              CALL  BDOS
              POP   HL
              POP   BC
              RET
PUTC          PUSH  BC
              PUSH  HL
              LD    E,A
              LD    C,2
              CALL  BDOS
              POP   HL
              POP   BC
              RET
NEWLINE       LD    A,13
              CALL  PUTC
              LD    A,10
              JP    PUTC
; Print A as two hexadecimal characters.
HEX           PUSH  AF
              RRCA
              RRCA
              RRCA
              RRCA
              CALL  HEXDIG
              POP   AF
HEXDIG        AND   0FH
              ADD   A,'0'
              CP    '9'+1
              JP    C,PUTC
              ADD   A,7
              JP    PUTC
; Show 16-bit HL as HHHH.
HEX16         LD    A,H
              CALL  HEX
              LD    A,L
              JP    HEX

; -------- CONFIG FILE ----------------------------------------------------
; File is read as sequential CP/M 128-byte records (up to EOF), line-by-line.
; No comments on key=value lines; '#' or ';' at line beginning = comment.
CONFIG_READ   LD    DE,MSG_CFGOPEN
              CALL  PRINT
              ; Udo Z80ASM may fill DEFS with $FF: zero writable FCB fields.
              LD    HL,CONFIG_FCB+12
              LD    B,24
              XOR   A
CFG_ZEROFCB   LD    (HL),A
              INC   HL
              DJNZ  CFG_ZEROFCB
              LD    DE,CONFIG_FCB
              LD    C,15
              CALL  BDOS
              CP    0FFH
              JP    Z,CONFIG_FAIL
              LD    DE,REC_BUF
              LD    C,26
              CALL  BDOS
              XOR   A
              LD    (LINE_LEN),A
CFG_NEXTREC   LD    DE,CONFIG_FCB
              LD    C,20
              CALL  BDOS
              OR    A
              JP    NZ,CFG_EOF
              LD    HL,REC_BUF
              LD    B,128
CFG_NEXTCHR   LD    A,(HL)
              CP    01AH
              JP    Z,CFG_EOF
              CP    13
              JP    Z,CFG_ENDLINE
              CP    10
              JP    Z,CFG_ENDLINE
              PUSH  HL
              PUSH  BC
              CALL  CFG_APPEND
              POP   BC
              POP   HL
              JP    CFG_ADV
CFG_ENDLINE   PUSH  HL
              PUSH  BC
              CALL  CFG_LINE
              POP   BC
              POP   HL
CFG_ADV       INC   HL
              DJNZ  CFG_NEXTCHR
              JP    CFG_NEXTREC
CFG_EOF       CALL  CFG_LINE
              LD    DE,CONFIG_FCB
              LD    C,16
              CALL  BDOS
              OR    A
              RET
CONFIG_FAIL   SCF
              RET
CFG_APPEND    PUSH  HL
              PUSH  DE
              LD    E,A
              LD    A,(LINE_LEN)
              CP    62
              JP    NC,CFG_APPDONE
              LD    L,A
              LD    H,0
              LD    BC,LINE_BUF
              ADD   HL,BC
              LD    (HL),E
              LD    A,(LINE_LEN)
              INC   A
              LD    (LINE_LEN),A
CFG_APPDONE   POP   DE
              POP   HL
              RET
CFG_LINE      LD    A,(LINE_LEN)
              OR    A
              RET   Z
              LD    L,A
              LD    H,0
              LD    DE,LINE_BUF
              ADD   HL,DE
              LD    (HL),0
              XOR   A
              LD    (LINE_LEN),A
              LD    A,(LINE_BUF)
              CP    '#'
              RET   Z
              CP    ';'
              RET   Z
              LD    HL,LINE_BUF
              LD    DE,K_IP
              CALL  PREFIX
              JP    NC,CFG_IP
              LD    HL,LINE_BUF
              LD    DE,K_NETMASK
              CALL  PREFIX
              JP    NC,CFG_MASK
              LD    HL,LINE_BUF
              LD    DE,K_MASK
              CALL  PREFIX
              JP    NC,CFG_MASK
              LD    HL,LINE_BUF
              LD    DE,K_GW
              CALL  PREFIX
              JP    NC,CFG_GW
              LD    HL,LINE_BUF
              LD    DE,K_HOST
              CALL  PREFIX
              JP    NC,CFG_HOST
              LD    HL,LINE_BUF
              LD    DE,K_MAC
              CALL  PREFIX
              JP    NC,CFG_SETMAC
              LD    HL,LINE_BUF
              LD    DE,K_SLOT
              CALL  PREFIX
              JP    NC,CFG_SLOT
              LD    HL,LINE_BUF
              LD    DE,K_PORT
              CALL  PREFIX
              JP    NC,CFG_PORT
              LD    HL,LINE_BUF
              LD    DE,K_RESET
              CALL  PREFIX
              JP    NC,CFG_RESET
              LD    DE,MSG_UNKNOWN
              CALL  PRINT
              JP    CFG_ECHO
CFG_IP        LD    DE,CFG_IPADDR
              JP    CFG_IPSET
CFG_MASK      LD    DE,CFG_NETMASK
              JP    CFG_IPSET
CFG_GW        LD    DE,CFG_GATEWAY
              JP    CFG_IPSET
CFG_HOST      LD    DE,CFG_REMOTE
CFG_IPSET     CALL  IPV4
              JP    C,CFG_INVALID
              RET
CFG_SETMAC    LD    DE,CFG_MAC
              CALL  MACADDR
              JP    C,CFG_INVALID
              RET
CFG_SLOT      CALL  DEC8
              JP    C,CFG_INVALID
              CP    1
              JP    C,CFG_INVALID
              CP    8
              JP    NC,CFG_INVALID
              CP    4                        ; slot 4 contains the SoftCard
              JP    Z,CFG_INVALID
              LD    (CFG_SLOTNUM),A
              RET
CFG_RESET     CALL  DEC8
              JP    C,CFG_INVALID
              CP    2
              JP    NC,CFG_INVALID
              LD    (CFG_RESETFLAG),A
              RET
CFG_PORT      CALL  DEC16
              JP    C,CFG_INVALID
              LD    A,H
              OR    L
              JP    Z,CFG_INVALID
              LD    A,H
              LD    (CFG_PORTBE),A
              LD    A,L
              LD    (CFG_PORTBE+1),A
              RET
CFG_INVALID   LD    DE,MSG_INVALID
              CALL  PRINT
CFG_ECHO      LD    HL,LINE_BUF
CFG_EL        LD    A,(HL)
              OR    A
              JP    Z,NEWLINE
              PUSH  HL
              CALL  PUTC
              POP   HL
              INC   HL
              JP    CFG_EL
; PREFIX: HL=line, DE=literal 0-terminated prefix.
; success carry clear and HL points just after prefix.
PREFIX        LD    A,(DE)
              OR    A
              JP    Z,PREFIX_OK
              CP    (HL)
              JP    NZ,PREFIX_BAD
              INC   DE
              INC   HL
              JP    PREFIX
PREFIX_OK     OR    A
              RET
PREFIX_BAD    SCF
              RET
; MACADDR: parse HH:HH:HH:HH:HH:HH; HL=input, DE=six bytes.
MACADDR       LD    A,6
              LD    (MAC_COUNT),A
MAC_NEXT      PUSH  DE
              CALL  HEXBYTE
              POP   DE
              RET   C
              LD    (DE),A
              INC   DE
              LD    A,(MAC_COUNT)
              DEC   A
              LD    (MAC_COUNT),A
              JP    Z,MAC_END
              LD    A,(HL)
              CP    ':'
              JP    NZ,MAC_BAD
              INC   HL
              JP    MAC_NEXT
MAC_END       LD    A,(HL)
              OR    A
              JP    NZ,MAC_BAD
              RET
MAC_BAD       SCF
              RET
HEXBYTE       LD    A,(HL)
              CALL  HEXNIB
              RET   C
              RRCA
              RRCA
              RRCA
              RRCA
              LD    B,A
              INC   HL
              LD    A,(HL)
              CALL  HEXNIB
              RET   C
              OR    B
              INC   HL
              RET
HEXNIB        CP    '0'
              JP    C,MAC_BAD
              CP    '9'+1
              JP    NC,HEXNIB_A
              SUB   '0'
              RET
HEXNIB_A      CP    'A'
              JP    C,MAC_BAD
              CP    'F'+1
              JP    NC,MAC_BAD
              SUB   'A'-10
              RET
; DEC8: HL->digits, returns A and HL->NUL; CY on syntax/overflow.
DEC8          LD    B,0
              LD    E,0
D8_LOOP       LD    A,(HL)
              OR    A
              JP    Z,D8_END
              CP    '0'
              JP    C,D8_BAD
              CP    '9'+1
              JP    NC,D8_BAD
              SUB   '0'
              LD    D,A
              LD    A,B
              ADD   A,A
              RET   C
              LD    C,A
              ADD   A,A
              RET   C
              ADD   A,A
              RET   C
              ADD   A,C
              RET   C
              ADD   A,D
              RET   C
              LD    B,A
              INC   E
              INC   HL
              JP    D8_LOOP
D8_END        LD    A,E
              OR    A
              JP    Z,D8_BAD
              LD    A,B
              OR    A
              RET
D8_BAD        SCF
              RET
; IPV4 parse four 0..255 octets, dotted numeric only.
; HL->value, DE->4-byte destination. Return CY on failure.
IPV4          LD    A,4
              LD    (IP_COUNT),A
IP_NEXT       PUSH  DE
              CALL  DEC8_PART
              POP   DE
              RET   C
              LD    (DE),A
              INC   DE
              LD    A,(IP_COUNT)
              DEC   A
              LD    (IP_COUNT),A
              JP    Z,IP_LAST
              LD    A,(HL)
              CP    '.'
              JP    NZ,IP_BAD
              INC   HL
              JP    IP_NEXT
IP_LAST       LD    A,(HL)
              OR    A
              JP    NZ,IP_BAD
              RET
IP_BAD        SCF
              RET
; Similar to DEC8 but stops on '.' and leaves HL on delimiter.
DEC8_PART     LD    B,0
              LD    E,0
D8P_LOOP      LD    A,(HL)
              CP    '.'
              JP    Z,D8P_END
              OR    A
              JP    Z,D8P_END
              CP    '0'
              JP    C,D8P_BAD
              CP    '9'+1
              JP    NC,D8P_BAD
              SUB   '0'
              LD    D,A
              LD    A,B
              ADD   A,A
              RET   C
              LD    C,A
              ADD   A,A
              RET   C
              ADD   A,A
              RET   C
              ADD   A,C
              RET   C
              ADD   A,D
              RET   C
              LD    B,A
              INC   E
              INC   HL
              JP    D8P_LOOP
D8P_END       LD    A,E
              OR    A
              JP    Z,D8P_BAD
              LD    A,B
              OR    A
              RET
D8P_BAD       SCF
              RET
; Decimal 16-bit port parsing, HL->digit string, returns HL=port.
; Uses a temporary byte to simplify the Z80 multiply-by-ten.
DEC16         EX    DE,HL
              LD    HL,0
              LD    A,0
              LD    (DIG_COUNT),A
D16_NEXT      LD    A,(DE)
              OR    A
              JP    Z,D16_END
              CP    '0'
              JP    C,D16_BAD
              CP    '9'+1
              JP    NC,D16_BAD
              SUB   '0'
              LD    (DIGIT),A
              ADD   HL,HL
              JP    C,D16_BAD
              LD    B,H
              LD    C,L
              ADD   HL,HL
              JP    C,D16_BAD
              ADD   HL,HL
              JP    C,D16_BAD
              ADD   HL,BC
              JP    C,D16_BAD
              LD    A,(DIGIT)
              LD    C,A
              LD    B,0
              ADD   HL,BC
              JP    C,D16_BAD
              LD    A,(DIG_COUNT)
              INC   A
              LD    (DIG_COUNT),A
              INC   DE
              JP    D16_NEXT
D16_END       LD    A,(DIG_COUNT)
              OR    A
              JP    Z,D16_BAD
              OR    A
              RET
D16_BAD       SCF
              RET

VALIDATE_CFG  LD    A,(CFG_IPADDR)
              OR    A
              JP    Z,VALID_BAD
              LD    A,(CFG_NETMASK)
              OR    A
              JP    Z,VALID_BAD
              LD    A,(CFG_REMOTE)
              OR    A
              JP    Z,VALID_BAD
              OR    A
              RET
VALID_BAD     SCF
              RET

PRINT_CFG     LD    DE,MSG_CFG
              CALL  PRINT
              LD    DE,MSG_SLOT
              CALL  PRINT
              LD    A,(CFG_SLOTNUM)
              ADD   A,'0'
              CALL  PUTC
              CALL  NEWLINE
              LD    DE,MSG_MAC
              CALL  PRINT
              LD    HL,CFG_MAC
              CALL  PRINT_MAC_BYTES
              LD    DE,MSG_LOCAL
              LD    HL,CFG_IPADDR
              CALL  PRINT_IP
              LD    DE,MSG_MASK
              LD    HL,CFG_NETMASK
              CALL  PRINT_IP
              LD    DE,MSG_GATEWAY
              LD    HL,CFG_GATEWAY
              CALL  PRINT_IP
              LD    DE,MSG_REMOTE
              LD    HL,CFG_REMOTE
              CALL  PRINT_IP
              LD    DE,MSG_PORT
              CALL  PRINT
              LD    A,(CFG_PORTBE)
              CALL  HEX
              LD    A,(CFG_PORTBE+1)
              CALL  HEX
              CALL  NEWLINE
              LD    DE,MSG_RESET
              CALL  PRINT
              LD    A,(CFG_RESETFLAG)
              ADD   A,'0'
              CALL  PUTC
              JP    NEWLINE
PRINT_MAC_BYTES
              LD    B,6
PRMAC         LD    A,(HL)
              CALL  HEX
              INC   HL
              DEC   B
              JP    Z,PRMAC_END
              LD    A,':'
              CALL  PUTC
              JP    PRMAC
PRMAC_END     JP    NEWLINE
PRINT_IP      PUSH  HL
              CALL  PRINT
              POP   HL
              LD    B,4
PIP_LOOP      LD    A,(HL)
              CALL  HEX
              INC   HL
              DEC   B
              JP    Z,NEWLINE
              LD    A,'.'
              CALL  PUTC
              JP    PIP_LOOP

; -------- HARDWARE PORTS -------------------------------------------------
; v0.9 on real hardware proved LD (BC),A works for DATA_WR, while
; LD (nn),A did not. v1.0 incorrectly changed pointer writes as well.
; Preserve v0.9's known-working address-pointer routines, and use
; register-indirect write ONLY for the W5100 data port.
SET_SLOT_IO   LD    A,(CFG_SLOTNUM)
              ADD   A,A
              ADD   A,A
              ADD   A,A
              ADD   A,A
              ADD   A,084H
              LD    (MODE_RD+1),A
              LD    (MODE_WR+1),A
              INC   A
              LD    (ADDRHI_RD+1),A
              LD    (ADDRHI_WR+1),A
              INC   A
              LD    (ADDRLO_RD+1),A
              LD    (ADDRLO_WR+1),A
              INC   A
              LD    (DATA_RD+1),A
              RET
MODE_RD       LD    A,(0E0B4H)
              RET
ADDRHI_RD     LD    A,(0E0B5H)
              RET
ADDRLO_RD     LD    A,(0E0B6H)
              RET
DATA_RD       LD    A,(0E0B7H)
              RET
; Preserve the mode register write form from v0.9 (RESET=0 never uses it).
MODE_WR       LD    (0E0B4H),A
              RET
; These two routines were working in the v0.9 opcode-comparison test.
ADDRHI_WR     LD    (0E0B5H),A
              RET
ADDRLO_WR     LD    (0E0B6H),A
              RET
; Only data-port writes use the experimentally confirmed indirect form.
; Mirror the exact proven v0.9 LD (HL),A hardware write sequence.
; Save the W5100 register address in HL because WBLOCK needs it intact.
; A is the byte to write; all BC/DE/HL preserved.
DATA_WR       PUSH  HL
              PUSH  AF
              LD    A,(DATA_RD+1)
              LD    L,A
              LD    H,0E0H
              POP   AF
              LD    (HL),A
              POP   HL
              RET
; Set W5100 16-bit internal pointer HL high then low, preserve HL.
WSEL          PUSH  AF
              LD    A,H
              CALL  ADDRHI_WR
              LD    A,L
              CALL  ADDRLO_WR
              POP   AF
              RET
; TELNET v1.5: hybrid W5100 access. Native Z80 reads, native 6502 writes.
; The v1.4 first 6502 READ handoff hung after W5100 mode display.
; Preserve working v1.3 read path; use 6502 only for writes.
WREAD         CALL  WSEL
              JP    DATA_RD
; Read B consecutive bytes into (DE) without BDOS or other interrupts.
; Mode $03/$13: hardware auto-increments W5100 indirect address.
; Mode $01/$11: pointer does NOT auto-increment; explicitly reselect for
; every byte. Never change VEDRIVE's mode register merely for efficiency.
WREADBLOCK    LD    A,(HW_MODE)
              AND   002H
              JP    Z,WRB_MANUAL
              CALL  WSEL
WRB_LOOP      CALL  DATA_RD
              LD    (DE),A
              INC   DE
              DJNZ  WRB_LOOP
              RET
WRB_MANUAL    CALL  WREAD
              LD    (DE),A
              INC   DE
              INC   HL
              DJNZ  WRB_MANUAL
              RET
; WWRITE: HL=W5100 address, A=data. Never switch CPUs directly
; from an AUX transient: private BDOS $F9 travels via AXGATE.
WWRITE        PUSH  AF
              PUSH  BC
              PUSH  DE
              PUSH  HL
              LD    A,H
              LD    (W5PARAM),A
              LD    A,L
              LD    (W5PARAM+1),A
              POP   HL
              POP   DE
              POP   BC
              POP   AF
              LD    (W5PARAM+2),A
              PUSH  AF
              PUSH  BC
              PUSH  DE
              PUSH  HL
              LD    DE,W5PARAM
              LD    C,0F9H
              CALL  BDOS
              POP   HL
              POP   DE
              POP   BC
              POP   AF
              RET
W5PARAM       DEFB  0,0,0
; All W5100 reads use the v1.3 native Z80 path proven on hardware.
; All writes use one native 6502 handoff per byte, with explicit address.
; Avoid BDOS inside individual W5100 transactions.
WBLOCK        LD    A,(DE)
              CALL  WWRITE
              INC   DE
              INC   HL
              DJNZ  WBLOCK
              RET

HW_INIT       LD    A,(CFG_RESETFLAG)
              OR    A
              JP    Z,HW_NO_RESET
              LD    DE,MSG_RESETWARN
              CALL  PRINT
              LD    A,080H
              CALL  MODE_WR
HW_NO_RESET   LD    A,(CFG_RESETFLAG)
              OR    A
              JP    Z,HW_MODE_READY
; Fresh reset only: program our preferred mode.  With VEDRIVE active,
; use the pre-existing mode without writing even a single byte to MR.
              LD    A,003H
              CALL  MODE_WR
HW_MODE_READY CALL  MODE_RD
              LD    (HW_MODE),A
; Always print *actual* mode, even for a failed probe (v0.3 omitted it).
              LD    DE,MSG_MODERB
              CALL  PRINT
              LD    A,(HW_MODE)
              CALL  HEX
              CALL  NEWLINE
; W5100 MR bit 0 = indirect addressing, the only mandatory bit.
; $03 is normal, $13 enables ping-block; $01/$11 omit auto-increment.
              LD    A,(HW_MODE)
              AND   001H
              JP    NZ,HW_INDIRECT_OK
              LD    DE,MSG_MODEKEEP
              CALL  PRINT
              SCF
              RET
HW_INDIRECT_OK
              LD    A,(HW_MODE)
              AND   002H
              JP    NZ,HW_AI_ON
              LD    DE,MSG_AI_OFF
              CALL  PRINT
              JP    HW_ALLOCS
HW_AI_ON      LD    DE,MSG_AI_ON
              CALL  PRINT
HW_ALLOCS     LD    HL,001AH
              CALL  WREAD
              LD    (RX_ALLOC),A
              LD    DE,MSG_RXALLOC
              CALL  PRINT
              LD    A,(RX_ALLOC)
              CALL  HEX
              CALL  NEWLINE
              LD    HL,001BH
              CALL  WREAD
              LD    (TX_ALLOC),A
              LD    DE,MSG_TXALLOC
              CALL  PRINT
              LD    A,(TX_ALLOC)
              CALL  HEX
              CALL  NEWLINE
; With RESET=1, force standard 2KB per socket. With RESET=0 preserve
; existing layout (including $06 used with a 4KB socket 0) and derive
; socket-1 bases and circular-buffer masks without modifying allocation.
              LD    A,(CFG_RESETFLAG)
              OR    A
              JP    Z,HW_CHECK_BUFFERS
              LD    HL,001AH
              LD    A,055H
              CALL  WWRITE
              LD    HL,001BH
              LD    A,055H
              CALL  WWRITE
              LD    A,055H
              LD    (RX_ALLOC),A
              LD    (TX_ALLOC),A
HW_CHECK_BUFFERS
              LD    A,(TX_ALLOC)
              CALL  WBUF_TX
              JP    C,HW_BUFFER_ERR
              LD    A,(RX_ALLOC)
              CALL  WBUF_RX
              JP    C,HW_BUFFER_ERR
              LD    DE,MSG_TXBUF
              CALL  PRINT
              LD    A,(TX_BASEHI)
              CALL  HEX
              LD    A,0
              CALL  HEX
              LD    DE,MSG_BUF_MASK
              CALL  PRINT
              LD    A,(TX_MASKHI)
              CALL  HEX
              CALL  NEWLINE
              LD    DE,MSG_RXBUF
              CALL  PRINT
              LD    A,(RX_BASEHI)
              CALL  HEX
              LD    A,0
              CALL  HEX
              LD    DE,MSG_BUF_MASK
              CALL  PRINT
              LD    A,(RX_MASKHI)
              CALL  HEX
              CALL  NEWLINE
; Print socket states before touching socket 1, so VEDRIVE ownership is
; evident on a real Apple //e.  SR codes 00=CLOSED, 22=UDP, 17=TCP.
              LD    DE,MSG_SOCKALL
              CALL  PRINT
              LD    HL,0403H
              CALL  WREAD
              CALL  HEX
              LD    A,' '
              CALL  PUTC
              LD    HL,0503H
              CALL  WREAD
              CALL  HEX
              LD    A,' '
              CALL  PUTC
              LD    HL,0603H
              CALL  WREAD
              CALL  HEX
              LD    A,' '
              CALL  PUTC
              LD    HL,0703H
              CALL  WREAD
              CALL  HEX
              CALL  NEWLINE
              LD    A,(CFG_RESETFLAG)
              OR    A
              JP    NZ,HW_FRESH_NET
; VEDRIVE-safe attach: read live hardware IP/netmask/GW/MAC and compare
; to TELNET.CFG.  NEVER change these shared registers in attach mode.
              LD    DE,MSG_ATTACH
              CALL  PRINT
              LD    HL,0001H
              LD    DE,HW_GATEWAY
              LD    B,4
              CALL  WREADBLOCK
              LD    HL,0005H
              LD    DE,HW_NETMASK
              LD    B,4
              CALL  WREADBLOCK
              LD    HL,0009H
              LD    DE,HW_MAC
              LD    B,6
              CALL  WREADBLOCK
              LD    HL,000FH
              LD    DE,HW_IPADDR
              LD    B,4
              CALL  WREADBLOCK
              LD    DE,MSG_ACTGW
              LD    HL,HW_GATEWAY
              CALL  PRINT_IP
              LD    DE,MSG_ACTMASK
              LD    HL,HW_NETMASK
              CALL  PRINT_IP
              LD    DE,MSG_ACTIP
              LD    HL,HW_IPADDR
              CALL  PRINT_IP
              LD    DE,MSG_ACTMAC
              CALL  PRINT
              LD    HL,HW_MAC
              CALL  PRINT_MAC_BYTES
              LD    HL,HW_GATEWAY
              LD    DE,CFG_GATEWAY
              LD    B,4
              CALL  COMPARE_BYTES
              JP    C,HW_NET_MISMATCH
              LD    HL,HW_NETMASK
              LD    DE,CFG_NETMASK
              LD    B,4
              CALL  COMPARE_BYTES
              JP    C,HW_NET_MISMATCH
              LD    HL,HW_IPADDR
              LD    DE,CFG_IPADDR
              LD    B,4
              CALL  COMPARE_BYTES
              JP    C,HW_NET_MISMATCH
              LD    HL,HW_MAC
              LD    DE,CFG_MAC
              LD    B,6
              CALL  COMPARE_BYTES
              JP    C,HW_NET_MISMATCH
              LD    DE,MSG_MATCH
              CALL  PRINT
              OR    A
              RET
HW_NET_MISMATCH
              LD    DE,MSG_NETMISMATCH
              CALL  PRINT
              OR    A                     ; warning only: use live chip config
              RET
; Fresh setup is ONLY legal with RESET=1.  RESET tears down VEDRIVE.
HW_FRESH_NET  LD    DE,MSG_FRESHNET
              CALL  PRINT
              LD    HL,0001H
              LD    DE,CFG_GATEWAY
              LD    B,4
              CALL  WBLOCK
              LD    HL,0005H
              LD    DE,CFG_NETMASK
              LD    B,4
              CALL  WBLOCK
              LD    HL,0009H
              LD    DE,CFG_MAC
              LD    B,6
              CALL  WBLOCK
              LD    HL,000FH
              LD    DE,CFG_IPADDR
              LD    B,4
              CALL  WBLOCK
              OR    A
              RET
; A=(DE) is expected config; (HL) is active W5100 byte.
COMPARE_BYTES LD    A,(DE)
              CP    (HL)
              JP    NZ,CMP_DIFFER
              INC   DE
              INC   HL
              DJNZ  COMPARE_BYTES
              OR    A
              RET
CMP_DIFFER    SCF
              RET
HW_BUFFER_ERR LD    DE,MSG_BUFERR
              CALL  PRINT
HW_ERROR      SCF
              RET

; Derive socket-1 buffer base (high address byte) and mask (high byte)
; from one W5100 allocation register (RX or TX).  Each socket's two-bit
; field encodes 1, 2, 4 or 8 KB; socket 1 starts after socket 0.
; B = size of socket 0 in 256-byte pages (4,8,16,32),
; C = (size of socket 1 in pages)-1 (3,7,15,31).
; Reject only arrangements that put socket 1 past the 8KB RX/TX space.
WBUF_CALC     PUSH  AF
              AND   003H
              LD    L,A
              LD    H,0
              LD    DE,WBUF_PAGES
              ADD   HL,DE
              LD    B,(HL)
              POP   AF
              RRCA
              RRCA
              AND   003H
              LD    L,A
              LD    H,0
              LD    DE,WBUF_PAGES
              ADD   HL,DE
              LD    C,(HL)
              LD    A,B
              ADD   A,C
              CP    021H                 ; 32 pages = 8KB, inclusive
              JP    NC,WBUF_INVALID
              DEC   C                     ; bit mask for ring address high
              OR    A                     ; carry clear
              RET
WBUF_INVALID  SCF
              RET
WBUF_PAGES    DEFB  004H,008H,010H,020H

WBUF_TX       CALL  WBUF_CALC
              RET   C
              LD    A,B
              ADD   A,040H               ; transmit memory starts at $4000
              LD    (TX_BASEHI),A
              LD    A,C
              LD    (TX_MASKHI),A
              OR    A
              RET
WBUF_RX       CALL  WBUF_CALC
              RET   C
              LD    A,B
              ADD   A,060H               ; receive memory starts at $6000
              LD    (RX_BASEHI),A
              LD    A,C
              LD    (RX_MASKHI),A
              OR    A
              RET

; -------- SOCKET 1: TCP --------------------------------------------------
SOCK_SETUP    LD    DE,MSG_SOCK
              CALL  PRINT
              LD    HL,S1SR
              CALL  WREAD
              PUSH  AF
              CALL  HEX
              CALL  NEWLINE
              POP   AF
              OR    A
              JP    NZ,SOCK_BUSY
              LD    DE,MSG_BRIDGE_PREW
              CALL  PRINT
              LD    HL,S1MR
              LD    A,1
              CALL  WWRITE
              LD    DE,MSG_BRIDGE_POSTW
              CALL  PRINT
              ; Check the TCP mode write immediately, before block writes.
              LD    HL,S1MR
              CALL  WREAD
              LD    (DBG_MR_NOW),A
              LD    HL,S1PORT
              LD    DE,LOCAL_PORT
              LD    B,2
              CALL  WBLOCK
              ; Determine whether the PORT block write changed Sn_MR.
              LD    HL,S1MR
              CALL  WREAD
              LD    (DBG_MR_PORT),A
              LD    HL,S1DIP
              LD    DE,CFG_REMOTE
              LD    B,4
              CALL  WBLOCK
              LD    HL,S1DPORT
              LD    DE,CFG_PORTBE
              LD    B,2
              CALL  WBLOCK
              ; Detect whether destination block writes changed Sn_MR.
              LD    HL,S1MR
              CALL  WREAD
              LD    (DBG_MR_DEST),A
              ; Read out checkpoints now (after the critical writes).
              LD    DE,MSG_DBGNOW
              CALL  PRINT
              LD    A,(DBG_MR_NOW)
              CALL  HEX
              CALL  NEWLINE
              LD    DE,MSG_DBGPORTMR
              CALL  PRINT
              LD    A,(DBG_MR_PORT)
              CALL  HEX
              CALL  NEWLINE
              LD    DE,MSG_DBGDESTMR
              CALL  PRINT
              LD    A,(DBG_MR_DEST)
              CALL  HEX
              CALL  NEWLINE
              ; Reassert TCP mode LAST, to isolate mode-write problems from
              ; subsequent WBLOCK address-pointer/buffer operations.
              LD    HL,S1MR
              LD    A,1
              CALL  WWRITE
              LD    HL,S1MR
              CALL  WREAD
              LD    (DBG_MR_LAST),A
              LD    DE,MSG_DBGLASTMR
              CALL  PRINT
              LD    A,(DBG_MR_LAST)
              CALL  HEX
              CALL  NEWLINE
              ; Do not issue OPEN if mode still isn't TCP: avoid changing
              ; socket state when we already know initialization failed.
              LD    A,(DBG_MR_LAST)
              CP    1
              JP    NZ,DBG_BADMODE
              ; Do not clear Sn_IR before opening: inspect its old value.
              ; Read all setup fields back, including the source port.
              LD    DE,MSG_DBGMR
              CALL  PRINT
              LD    HL,S1MR
              CALL  WREAD
              CALL  HEX
              CALL  NEWLINE
              LD    DE,MSG_DBGPORT
              CALL  PRINT
              LD    HL,S1PORT
              CALL  WREAD
              CALL  HEX
              LD    HL,S1PORT+1
              CALL  WREAD
              CALL  HEX
              CALL  NEWLINE
              LD    DE,MSG_DBGCR0
              CALL  PRINT
              LD    HL,S1CR
              CALL  WREAD
              CALL  HEX
              CALL  NEWLINE
              LD    DE,MSG_DBGIR0
              CALL  PRINT
              LD    HL,S1IR
              CALL  WREAD
              CALL  HEX
              CALL  NEWLINE
              ; No BDOS calls between command write and immediate CR sample.
              LD    HL,S1CR
              LD    A,1
              CALL  WWRITE
              LD    HL,S1CR
              CALL  WREAD
              LD    (DBG_IMMCR),A
              ; Poll Sn_CR; do not rely on one immediate Sn_SR sample.
              LD    BC,8000
DBG_CRWAIT    LD    HL,S1CR
              CALL  WREAD
              OR    A
              JP    Z,DBG_CRDONE
              DEC   BC
              LD    A,B
              OR    C
              JP    NZ,DBG_CRWAIT
              LD    DE,MSG_CMDTIME
              CALL  PRINT
              SCF
              RET
DBG_CRDONE    LD    HL,S1SR
              CALL  WREAD
              LD    (DBG_IMMSR),A
              LD    HL,S1IR
              CALL  WREAD
              LD    (DBG_IMMIR),A
              LD    DE,MSG_DBGCR1
              CALL  PRINT
              LD    A,(DBG_IMMCR)
              CALL  HEX
              CALL  NEWLINE
              LD    DE,MSG_DBGCR2
              CALL  PRINT
              LD    HL,S1CR
              CALL  WREAD
              CALL  HEX
              CALL  NEWLINE
              LD    DE,MSG_DBGSR1
              CALL  PRINT
              LD    A,(DBG_IMMSR)
              CALL  HEX
              CALL  NEWLINE
              LD    DE,MSG_DBGIR1
              CALL  PRINT
              LD    A,(DBG_IMMIR)
              CALL  HEX
              CALL  NEWLINE
              ; Probe status repeatedly before declaring failure.
              LD    BC,16000
DBG_SRWAIT    LD    HL,S1SR
              CALL  WREAD
              CP    013H
              JP    Z,DBG_SROK
              DEC   BC
              LD    A,B
              OR    C
              JP    NZ,DBG_SRWAIT
              LD    DE,MSG_DBGFINAL
              CALL  PRINT
              LD    HL,S1MR
              CALL  WREAD
              CALL  HEX
              CALL  NEWLINE
              JP    SOCK_BUSY
DBG_SROK     LD    HL,S1SR
              CALL  WREAD
              LD    DE,MSG_OPENSTATE
              PUSH  AF
              CALL  PRINT
              POP   AF
              CALL  HEX
              CALL  NEWLINE
              OR    A
              RET
DBG_BADMODE   LD    DE,MSG_BADMODE
              CALL  PRINT
              SCF
              RET
SOCK_BUSY     LD    DE,MSG_SOCKBUSY
              CALL  PRINT
              SCF
              RET

SOCK_CONNECT  LD    A,4
              CALL  COMMAND
              RET   C
              LD    BC,30000
              LD    DE,0
CONNECT_WAIT  LD    HL,S1SR
              CALL  WREAD
              CP    017H
              JP    Z,CONNECT_OK
              CP    000H
              JP    Z,CONNECT_BAD
              LD    HL,S1IR
              CALL  WREAD
              BIT   3,A
              JP    NZ,CONNECT_TIMEOUT
              DEC   BC
              LD    A,B
              OR    C
              JP    Z,CONNECT_TIMEOUT
              LD    A,C
              OR    A
              JP    NZ,CONNECT_WAIT
              PUSH  BC
              LD    DE,MSG_WAIT
              CALL  PRINT
              LD    HL,S1SR
              CALL  WREAD
              CALL  HEX
              CALL  NEWLINE
              LD    C,11
              CALL  BDOS
              POP   BC
              JP    CONNECT_WAIT
CONNECT_OK    OR    A
              RET
CONNECT_BAD   LD    DE,MSG_CLOSED
              CALL  PRINT
              SCF
              RET
CONNECT_TIMEOUT
              LD    DE,MSG_IR
              CALL  PRINT
              LD    HL,S1IR
              CALL  WREAD
              CALL  HEX
              CALL  NEWLINE
              LD    DE,MSG_TIMEOUT
              CALL  PRINT
              SCF
              RET
; A=command, waits for CR to clear with finite counter.
COMMAND       LD    HL,S1CR
              CALL  WWRITE
              LD    BC,8000
CMD_WAIT      LD    HL,S1CR
              CALL  WREAD
              OR    A
              RET   Z
              DEC   BC
              LD    A,B
              OR    C
              JP    NZ,CMD_WAIT
              LD    DE,MSG_CMDTIME
              CALL  PRINT
              SCF
              RET

; Read one byte if available. Carry=1 means no data; carry=0 A=data.
; Socket 1 ring size and base reflect the actual RMSR allocation.
RX_ONE        LD    HL,S1RXRSR
              CALL  WREAD
              LD    B,A
              INC   HL
              CALL  WREAD
              OR    B
              JP    Z,RX_EMPTY
              LD    HL,S1RXRD
              CALL  WREAD
              LD    B,A
              INC   HL
              CALL  WREAD
              LD    C,A
              LD    A,(RX_MASKHI)
              AND   B
              LD    H,A
              LD    A,(RX_BASEHI)
              OR    H
              LD    H,A
              LD    L,C
              CALL  WREAD
              LD    (RX_CHAR),A
              INC   BC
              LD    A,B
              LD    (RX_PTRHI),A
              LD    A,C
              LD    (RX_PTRLO),A
              LD    HL,S1RXRD
              LD    DE,RX_PTRHI
              LD    B,2
              CALL  WBLOCK
              LD    A,040H
              CALL  COMMAND
              JP    C,RX_EMPTY
              LD    A,(RX_CHAR)
              OR    A
              RET
RX_EMPTY      SCF
              RET

; Send B bytes from DE: Sn_TX_WR, ring wrap according to TMSR.
; Never call BDOS while an indirect W5100 pointer is active.
SEND_BYTES    LD    A,B
              OR    A
              RET   Z
              LD    (SEND_COUNT),A
              LD    (SEND_SRCPTR),DE
              LD    HL,S1TXFSR
              CALL  WREAD
              LD    C,A
              INC   HL
              CALL  WREAD
              LD    B,A
              LD    A,C
              OR    A
              JP    NZ,SEND_HAS_ROOM       ; available >=256
              LD    A,(SEND_COUNT)
              CP    B
              JP    C,SEND_HAS_ROOM
              JP    Z,SEND_HAS_ROOM
              LD    DE,MSG_TXFULL
              CALL  PRINT
              SCF
              RET
SEND_HAS_ROOM LD    HL,S1TXWR
              CALL  WREAD
              LD    B,A
              INC   HL
              CALL  WREAD
              LD    C,A
              LD    A,B
              LD    (TX_PTRHI),A
              LD    A,C
              LD    (TX_PTRLO),A
SEND_LOOP     LD    DE,(SEND_SRCPTR)
              LD    A,(DE)
              LD    (TX_CHAR),A
              INC   DE
              LD    (SEND_SRCPTR),DE
              LD    A,(TX_PTRHI)
              LD    H,A
              LD    A,(TX_MASKHI)
              AND   H
              LD    H,A
              LD    A,(TX_BASEHI)
              OR    H
              LD    H,A
              LD    A,(TX_PTRLO)
              LD    L,A
              LD    A,(TX_CHAR)
              CALL  WWRITE
              LD    A,(TX_PTRLO)
              INC   A
              LD    (TX_PTRLO),A
              JP    NZ,SEND_NEXT
              LD    A,(TX_PTRHI)
              INC   A
              LD    (TX_PTRHI),A
SEND_NEXT
              LD    A,(SEND_COUNT)
              DEC   A
              LD    (SEND_COUNT),A
              JP    NZ,SEND_LOOP
              LD    HL,S1TXWR
              LD    DE,TX_PTRHI
              LD    B,2
              CALL  WBLOCK
              LD    A,020H
              JP    COMMAND
; Send one keyboard byte (CR as CR LF); IAC $FF escaped as $FF $FF.
SEND_KEY      LD    (SEND_KEYBUF),A
              LD    B,1
              CP    13
              JP    NZ,SK_CHECKFF
              LD    A,10
              LD    (SEND_KEYBUF+1),A
              LD    B,2
SK_CHECKFF    LD    A,(SEND_KEYBUF)
              CP    0FFH
              JP    NZ,SK_SEND
              LD    A,0FFH
              LD    (SEND_KEYBUF+1),A
              LD    B,2
SK_SEND       LD    DE,SEND_KEYBUF
              JP    SEND_BYTES

; Basic TELNET IAC: accept remote ECHO/SGA; reject other options.
; Reply to every incoming WILL/WONT/DO/DONT; ignore subnegotiations.
TEL_IN        LD    B,A
              LD    A,(TN_STATE)
              OR    A
              JP    Z,TN_TEXT
              CP    1
              JP    Z,TN_IAC
              CP    2
              JP    Z,TN_OPTION
              CP    3
              JP    Z,TN_SUB
              CP    4
              JP    Z,TN_SUBIAC
              XOR   A
              LD    (TN_STATE),A
              RET
TN_TEXT       LD    A,B
              CP    0FFH
              JP    NZ,TN_OUTPUT
              LD    A,1
              LD    (TN_STATE),A
              RET
TN_OUTPUT     LD    E,A
              LD    C,6                      ; BDOS 6: raw console output
              JP    BDOS
TN_IAC        LD    A,B
              CP    0FFH
              JP    Z,TN_LITERALFF
              CP    0FAH                    ; SB
              JP    Z,TN_STARTSUB
              CP    0FBH                    ; WILL
              JP    Z,TN_SETCMD
              CP    0FCH                    ; WONT
              JP    Z,TN_SETCMD
              CP    0FDH                    ; DO
              JP    Z,TN_SETCMD
              CP    0FEH                    ; DONT
              JP    Z,TN_SETCMD
              XOR   A
              LD    (TN_STATE),A
              RET
TN_LITERALFF  XOR   A
              LD    (TN_STATE),A
              LD    A,'?'                  ; BDOS 6 uses $FF as CONIN, not output
              JP    TN_OUTPUT
TN_STARTSUB   LD    A,3
              LD    (TN_STATE),A
              RET
TN_SETCMD     LD    (TN_COMMAND),A
              LD    A,2
              LD    (TN_STATE),A
              RET
TN_SUB        LD    A,B
              CP    0FFH
              RET   NZ
              LD    A,4
              LD    (TN_STATE),A
              RET
TN_SUBIAC     LD    A,B
              CP    0F0H                    ; SE
              JP    Z,TN_SUBDONE
              LD    A,3
              LD    (TN_STATE),A
              RET
TN_SUBDONE    XOR   A
              LD    (TN_STATE),A
              RET
TN_OPTION     XOR   A
              LD    (TN_STATE),A
              LD    A,B
              LD    (TN_BUF+2),A
              LD    A,(TN_COMMAND)
              CP    0FBH                    ; WILL -> DO or DONT
              JP    Z,TN_WILL
              CP    0FDH                    ; DO -> WILL or WONT
              JP    Z,TN_DO
              RET                            ; WONT/DONT: accept silently
TN_WILL       LD    A,B
              CP    1                       ; ECHO
              JP    Z,TN_ALLOWDO
              CP    3                       ; SUPPRESS-GO-AHEAD
              JP    Z,TN_ALLOWDO
              LD    A,0FEH                   ; DONT
              JP    TN_REPLY
TN_ALLOWDO    LD    A,0FDH                   ; DO
              JP    TN_REPLY
TN_DO         LD    A,B
              CP    3
              JP    Z,TN_ALLOWWILL
              LD    A,0FCH                   ; WONT
              JP    TN_REPLY
TN_ALLOWWILL  LD    A,0FBH                   ; WILL
TN_REPLY      LD    (TN_BUF+1),A
              LD    DE,TN_BUF
              LD    B,3
              CALL  SEND_BYTES
              RET

MAIN_LOOP     CALL  RX_ONE
              JP    C,MAIN_NO_RX
              CALL  TEL_IN
MAIN_NO_RX    LD    HL,(POLL_COUNT)
              INC   HL
              LD    (POLL_COUNT),HL
              LD    A,H
              AND   00FH
              OR    L
              JP    NZ,MAIN_NO_HB
              LD    DE,MSG_HEART
              CALL  PRINT
              LD    HL,S1SR
              CALL  WREAD
              CALL  HEX
              CALL  NEWLINE
MAIN_NO_HB    LD    HL,S1SR
              CALL  WREAD
              CP    017H
              JP    Z,MAIN_KEY
              CP    01CH                    ; CLOSE_WAIT: drain outstanding data first
              JP    Z,MAIN_KEY
              LD    DE,MSG_DISCONNECT
              CALL  PRINT
              JP    CLOSE_EXIT
MAIN_KEY      LD    C,11                    ; cooperative scheduler+keyboard status
              CALL  BDOS
              OR    A
              JP    Z,MAIN_LOOP
              LD    E,0FFH
              LD    C,6                     ; non-blocking read
              CALL  BDOS
              AND   07FH
              CP    01DH                    ; Ctrl-] leaves telnet
              JP    Z,CLOSE_EXIT
              CP    3                       ; Ctrl-C leaves telnet
              JP    Z,CLOSE_EXIT
              CALL  SEND_KEY
              JP    C,CLOSE_EXIT
              JP    MAIN_LOOP
CLOSE_EXIT    LD    DE,MSG_CLOSE
              CALL  PRINT
              LD    A,010H
              CALL  COMMAND               ; CLOSE socket 1 only
              JP    EXIT

; --- Data and ASCII diagnostics ------------------------------------------
MSG_BANNER    DEFB  13,10
              DEFM  'Zapple-II TELNET/W5100 prototype v1.7'
              DEFB  13,10
              DEFB  '$'
MSG_CFGOPEN   DEFM  '[01] opening TELNET.CFG'
              DEFB  13,10
              DEFB  '$'
MSG_CFG       DEFM  '[02] configuration (IPs shown as HEX octets)'
              DEFB  13,10
              DEFB  '$'
MSG_SLOT      DEFM  ' slot = $'
MSG_MAC       DEFM  ' MAC = $'
MSG_LOCAL     DEFM  ' local IP = $'
MSG_MASK      DEFM  ' netmask  = $'
MSG_GATEWAY   DEFM  ' gateway  = $'
MSG_REMOTE    DEFM  ' remote IP= $'
MSG_PORT      DEFM  ' remote port HEX = $'
MSG_RESET     DEFM  ' reset W5100 = $'
MSG_BADCFG    DEFM  'ERROR: TELNET.CFG missing or IP/MASK/HOST invalid'
              DEFB  13,10
              DEFB  '$'
MSG_UNKNOWN   DEFM  '[CFG] unknown key: $'
MSG_INVALID   DEFM  '[CFG] INVALID value: $'
MSG_HW        DEFM  '[03] probing W5100 / attach or reset mode'
              DEFB  13,10
              DEFB  '$'
MSG_RESETWARN DEFM  '[WARN] RESET=1: resetting ALL W5100 sockets!'
              DEFB  13,10
              DEFB  '$'
MSG_MODERB    DEFM  ' [W5100] mode readback = $'
MSG_RXALLOC   DEFM  ' [W5100] RMSR = $'
MSG_TXALLOC   DEFM  ' [W5100] TMSR = $'
MSG_BUFERR    DEFM  ' [W5100] socket 1 TX/RX allocation invalid (over 8KB)'
              DEFB  13,10
              DEFB  '$'
MSG_TXBUF     DEFM  ' [W5100] socket 1 TX base = $'
MSG_RXBUF     DEFM  ' [W5100] socket 1 RX base = $'
MSG_BUF_MASK  DEFM  ' mask high = $'
MSG_MODEKEEP  DEFM  ' [SAFE] mode bit 0 (IND) is OFF; cannot access W5100 safely'
              DEFB  13,10
              DEFB  '$'
MSG_AI_OFF    DEFM  ' [W5100] auto-increment OFF; using per-byte addressing'
              DEFB  13,10
              DEFB  '$'
MSG_AI_ON     DEFM  ' [W5100] auto-increment ON; using block transfers'
              DEFB  13,10
              DEFB  '$'
MSG_SOCKALL   DEFM  ' [W5100] sockets 0/1/2/3 status = $'
MSG_ATTACH    DEFM  ' [SAFE] RESET=0: keeping VEDRIVE network configuration'
              DEFB  13,10
              DEFB  '$'
MSG_ACTGW     DEFM  '  active GW  = $'
MSG_ACTMASK   DEFM  '  active MASK= $'
MSG_ACTIP     DEFM  '  active IP  = $'
MSG_ACTMAC    DEFM  '  active MAC = $'
MSG_MATCH     DEFM  ' [SAFE] config matches; shared registers untouched'
              DEFB  13,10
              DEFB  '$'
MSG_NETMISMATCH DEFM  ' [SAFE] CONFIG MISMATCH: using active W5100 config (no writes)'
              DEFB  13,10
              DEFB  '$'
MSG_FRESHNET  DEFM  ' [WARN] RESET=1: programming GW/MASK/MAC/IP'
              DEFB  13,10
              DEFB  '$'
MSG_BADHW     DEFM  'ERROR: W5100 mode or socket 1 buffer layout invalid'
              DEFB  13,10
              DEFB  '$'
MSG_BRIDGE_BELL DEFM '[BRIDGE] Calling existing 6502 B809 bell...' 
               DEFB 13,10,'$'
MSG_BRIDGE_RETURN DEFM '[BRIDGE] Existing 6502 B809 returned'
               DEFB 13,10,'$'
MSG_BRIDGE_PREW DEFM '[BRIDGE] Entering AUX BDOS F9 write'
               DEFB 13,10,'$'
MSG_BRIDGE_POSTW DEFM '[BRIDGE] AUX BDOS F9 returned'
               DEFB 13,10,'$'
MSG_SOCK      DEFM  '[04] socket 1 previous status = $'
MSG_SOCKBUSY  DEFM  ' [W5100] socket 1 busy / TCP OPEN failed'
              DEFB  13,10
              DEFB  '$'
MSG_OPENSTATE DEFM  ' [W5100] after OPEN status = $'
MSG_BADMODE   DEFM  ' [DBG] TCP mode readback failed; OPEN skipped'
              DEFB  13,10
              DEFB  '$'
MSG_DBGNOW    DEFM  ' [DBG] MR right after write = $'
MSG_DBGPORTMR DEFM  ' [DBG] MR after PORT block = $'
MSG_DBGDESTMR DEFM  ' [DBG] MR after destination = $'
MSG_DBGLASTMR DEFM  ' [DBG] MR last re-write = $'
MSG_DBGMR     DEFM  ' [DBG] Sn_MR = $'
MSG_DBGPORT   DEFM  ' [DBG] Sn_PORT = $'
MSG_DBGCR0    DEFM  ' [DBG] Sn_CR before OPEN = $'
MSG_DBGIR0    DEFM  ' [DBG] Sn_IR before OPEN = $'
MSG_DBGCR1    DEFM  ' [DBG] Sn_CR immediate = $'
MSG_DBGCR2    DEFM  ' [DBG] Sn_CR after poll = $'
MSG_DBGSR1    DEFM  ' [DBG] Sn_SR after poll = $'
MSG_DBGIR1    DEFM  ' [DBG] Sn_IR after poll = $'
MSG_DBGFINAL  DEFM  ' [DBG] timeout: Sn_MR = $'
MSG_BADSOCK   DEFM  'ERROR: socket setup'
              DEFB  13,10
              DEFB  '$'
MSG_CONNECT   DEFM  '[05] CONNECT / wait for ESTABLISHED'
              DEFB  13,10
              DEFB  '$'
MSG_WAIT      DEFM  ' [WAIT] socket status = $'
MSG_IR        DEFM  ' [W5100] socket IR = $'
MSG_TIMEOUT   DEFM  ' [TIMEOUT] SYN not established (check host/port/gateway)'
              DEFB  13,10
              DEFB  '$'
MSG_CLOSED    DEFM  ' [W5100] CLOSED before ESTABLISHED'
              DEFB  13,10
              DEFB  '$'
MSG_CONN_CLEAN DEFM  ' [cleanup] closing socket 1 after failed CONNECT'
              DEFB  13,10
              DEFB  '$'
MSG_BADCONN   DEFM  'ERROR: failed to connect'
              DEFB  13,10
              DEFB  '$'
MSG_CMDTIME   DEFM  ' [W5100] socket command never cleared'
              DEFB  13,10
              DEFB  '$'
MSG_HEART     DEFM  '[POLL] socket status = $'
MSG_CONNECTED DEFM  '[06] CONNECTED - Ctrl-] or Ctrl-C to exit'
              DEFB  13,10
              DEFB  '$'
MSG_DISCONNECT DEFB  13,10
              DEFM  '[TCP] socket disconnected'
              DEFB  13,10
              DEFB  '$'
MSG_TXFULL    DEFM  '[TX] free buffer low; send aborted'
              DEFB  13,10
              DEFB  '$'
MSG_CLOSE     DEFB  13,10
              DEFM  '[07] closing socket 1'
              DEFB  13,10
              DEFB  '$'
MSG_EXIT      DEFM  '[08] exit to CCP'
              DEFB  13,10
              DEFB  '$'
K_IP          DEFM  'IP='
              DEFB  0
K_NETMASK     DEFM  'NETMASK='
              DEFB  0
K_MASK        DEFM  'MASK='
              DEFB  0
K_GW          DEFM  'GW='
              DEFB  0
K_HOST        DEFM  'HOST='
              DEFB  0
K_MAC         DEFM  'MAC='
              DEFB  0
K_SLOT        DEFM  'SLOT='
              DEFB  0
K_PORT        DEFM  'PORT='
              DEFB  0
K_RESET       DEFM  'RESET='
              DEFB  0

CONFIG_FCB    DEFB  0
              DEFM  'TELNET  CFG'
              DEFS  24
LOCAL_PORT    DEFB  0C0H,0DEH
CFG_IPADDR    DEFB  0,0,0,0
CFG_NETMASK   DEFB  0,0,0,0
CFG_GATEWAY   DEFB  0,0,0,0
CFG_REMOTE    DEFB  0,0,0,0
CFG_MAC       DEFB  002H,05AH,050H,04CH,045H,001H
CFG_PORTBE    DEFB  0,23
CFG_SLOTNUM   DEFB  3
CFG_RESETFLAG DEFB  0
LINE_LEN      DEFB  0
POLL_COUNT    DEFW  0
IP_COUNT      DEFB  0
MAC_COUNT     DEFB  0
DIG_COUNT     DEFB  0
DIGIT         DEFB  0
HW_MODE       DEFB  0
HW_GATEWAY    DEFS  4
HW_NETMASK    DEFS  4
HW_MAC        DEFS  6
HW_IPADDR     DEFS  4
RX_ALLOC      DEFB  0
TX_ALLOC      DEFB  0
RX_BASEHI     DEFB  0
RX_MASKHI     DEFB  0
TX_BASEHI     DEFB  0
TX_MASKHI     DEFB  0
RX_CHAR       DEFB  0
RX_PTRHI      DEFB  0
RX_PTRLO      DEFB  0
TX_PTRHI      DEFB  0
TX_PTRLO      DEFB  0
TX_CHAR       DEFB  0
SEND_COUNT    DEFB  0
SEND_SRCPTR   DEFW  0
SEND_KEYBUF   DEFB  0,0
TN_STATE      DEFB  0
TN_COMMAND    DEFB  0
TN_BUF        DEFB  0FFH,0,0
LINE_BUF      DEFS  64
REC_BUF       DEFS  128
DBG_MR_NOW    DEFB  0
DBG_MR_PORT   DEFB  0
DBG_MR_DEST   DEFB  0
DBG_MR_LAST   DEFB  0
DBG_IMMCR     DEFB  0
DBG_IMMSR     DEFB  0
DBG_IMMIR     DEFB  0
STACK         DEFS  256
STACKTOP
              END
