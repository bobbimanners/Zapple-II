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
S1D001       EQU   0510H
S1T001       EQU   0520H
S1TXWR        EQU   0524H
S1R001       EQU   0526H
S1RXRD        EQU   0528H
; TX/RX socket 1 buffer addresses are determined at run time.

              ORG   0100H
START         LD    SP,STACKTOP
              LD    DE,MSG001
              CALL  PRINT
              CALL  ARG001
              JP    C,FAT001
              CALL  CON001
              JP    C,FAT002
              CALL  ARG015
              CALL  PRI003
              CALL  VAL001
              JP    C,FAT002
              LD    A,(CFG025)
              CP    5
              JP    NZ,FAT002
              LD    A,(CFG026)
              OR    A
              JP    NZ,FAT002
              CALL  SET001
              LD    DE,MSG_HW
              CALL  PRINT
              CALL  HW_001
              JP    C,FAT003
              CALL  SOC001
              JP    C,FAT004
              LD    DE,MSG059
              CALL  PRINT
              CALL  SOC003
              JP    C,FAT005
              LD    DE,MSG067
              CALL  PRINT
              JP    MAI001
FAT001    LD    DE,MSG002
              JP    ERR001
FAT002     LD    DE,MSG013
              JP    ERR001
FAT003      LD    DE,MSG036
              JP    ERR001
FAT004    LD    DE,MSG058
              JP    ERR001
FAT005    LD    DE,MSG064
              CALL  PRINT
              LD    DE,MSG063
              CALL  PRINT
              LD    A,010H                 ; we own socket 1 after successful OPEN
              CALL  COM002              ; close failed connection before leaving
              JP    EXIT
ERR001    CALL  PRINT
              JP    EXIT
EXIT          LD    DE,MSG071
              CALL  PRINT
              LD    C,0
              JP    BDOS

; BDOS 9 '$'-terminated message. Preserve the working caller's BC/HL.
PRINT         PUSH  BC
              PUSH  AF
              CALL  PRI002
              POP   AF
              PUSH  HL
              LD    A,(QUI001)
              OR    A
              JP    NZ,PRI001
              LD    C,9
              CALL  BDOS
PRI001    POP   HL
              POP   BC
              RET
PUTC          PUSH  BC
              PUSH  AF
              LD    A,(QUI001)
              OR    A
              JP    NZ,PUT001
              POP   AF
              PUSH  HL
              LD    E,A
              LD    C,2
              CALL  BDOS
              POP   HL
              POP   BC
              RET
PUT001     POP   AF
              POP   BC
              RET
NEW001       LD    A,13
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

; Verbose output is controlled by -v. Keep diagnostic HEX/NEWLINE silent
; by retaining QUIET_MUTE across their follow-on calls; clear each RX poll.
PRI002    LD    A,(VER001)
              OR    A
              JP    NZ,PG_002
              PUSH  HL
              LD    HL,PG_004
PG_001       LD    A,(HL)
              INC   HL
              LD    C,A
              LD    A,(HL)
              INC   HL
              LD    B,A
              LD    A,B
              OR    C
              JP    Z,PG_003
              LD    A,E
              CP    C
              JP    NZ,PG_001
              LD    A,D
              CP    B
              JP    NZ,PG_001
              POP   HL
PG_002       XOR   A
              LD    (QUI001),A
              RET
PG_003       POP   HL
              LD    A,1
              LD    (QUI001),A
              RET
PG_004      DEFW  MSG001,MSG067,MSG068,MSG013
              DEFW  MSG036,MSG058,MSG064,MSG002
              DEFW  MSG069,MSG070,MSG071,MSG042
              DEFW  MSG020,MSG061,MSG062,MSG024
              DEFW  MSG044,MSG065,MSG015
              DEFW  0

; CP/M command tail length at 0080h, text at 0081h.
; Syntax TELNET [IPv4-address [port]] [-v], flags in any position.
; Preserve overrides until after configuration is loaded.
ARG001     LD    A,(0080H)
              CP    120
              JP    NC,ARG014
              LD    B,A
              LD    HL,0081H
              LD    DE,ARG022
ARG002      LD    A,B
              OR    A
              JP    Z,ARG003
              LD    A,(HL)
              LD    (DE),A
              INC   HL
              INC   DE
              DJNZ  ARG002
ARG003    XOR   A
              LD    (DE),A
              LD    HL,ARG022
ARG004      LD    A,(HL)
              CP    ' '
              JP    Z,ARG013
              CP    9
              JP    Z,ARG013
              OR    A
              RET   Z
              LD    (ARG020),HL
ARG005      LD    A,(HL)
              OR    A
              JP    Z,ARG007
              CP    ' '
              JP    Z,ARG006
              CP    9
              JP    Z,ARG006
              INC   HL
              JP    ARG005
ARG006  XOR   A
              LD    (HL),A
              INC   HL
              LD    (ARG021),HL
              JP    ARG008
ARG007      LD    (ARG021),HL
ARG008    LD    HL,(ARG020)
              LD    A,(HL)
              CP    '-'
              JP    NZ,ARG010
              INC   HL
              LD    A,(HL)
              CP    'v'
              JP    Z,ARG009
              CP    'V'
              JP    NZ,ARG014
ARG009      INC   HL
              LD    A,(HL)
              OR    A
              JP    NZ,ARG014
              LD    A,1
              LD    (VER001),A
              JP    ARG012
ARG010  LD    A,(ARG018)
              OR    A
              JP    NZ,ARG011
              LD    DE,ARG_IP
              CALL  IPV4
              JP    C,ARG014
              LD    A,1
              LD    (ARG018),A
              JP    ARG012
ARG011      CP    1
              JP    NZ,ARG014
              CALL  DEC16
              JP    C,ARG014
              LD    A,H
              OR    L
              JP    Z,ARG014
              LD    A,H
              LD    (ARG019),A
              LD    A,L
              LD    (ARG019+1),A
              LD    A,2
              LD    (ARG018),A
ARG012      LD    HL,(ARG021)
              JP    ARG004
ARG013     INC   HL
              JP    ARG004
ARG014       SCF
              RET
ARG015     LD    A,(ARG018)
              OR    A
              RET   Z
              LD    HL,ARG_IP
              LD    DE,CFG022
              LD    BC,4
ARG016      LD    A,(HL)
              LD    (DE),A
              INC   HL
              INC   DE
              DEC   BC
              LD    A,B
              OR    C
              JP    NZ,ARG016
              LD    A,(ARG018)
              CP    2
              RET   NZ
              LD    HL,ARG019
              LD    DE,CFG024
              LD    BC,2
ARG017    LD    A,(HL)
              LD    (DE),A
              INC   HL
              INC   DE
              DEC   BC
              LD    A,B
              OR    C
              JP    NZ,ARG017
              RET

; -------- CONFIG FILE ----------------------------------------------------
; File is read as sequential CP/M 128-byte records (up to EOF), line-by-line.
; No comments on key=value lines; '#' or ';' at line beginning = comment.
CON001   LD    DE,MSG003
              CALL  PRINT
              ; Udo Z80ASM may fill DEFS with $FF: zero writable FCB fields.
              LD    HL,CON006+12
              LD    B,24
              XOR   A
CFG001   LD    (HL),A
              INC   HL
              DJNZ  CFG001
              LD    DE,CON006
              LD    C,15
              CALL  BDOS
              CP    0FFH
              JP    Z,CON002
              LD    DE,REC001
              LD    C,26
              CALL  BDOS
              XOR   A
              LD    (LIN001),A
CFG002   LD    DE,CON006
              LD    C,20
              CALL  BDOS
              OR    A
              JP    NZ,CFG006
              LD    HL,REC001
              LD    B,128
CFG003   LD    A,(HL)
              CP    01AH
              JP    Z,CFG006
              CP    13
              JP    Z,CFG004
              CP    10
              JP    Z,CFG004
              PUSH  HL
              PUSH  BC
              CALL  CFG007
              POP   BC
              POP   HL
              JP    CFG005
CFG004   PUSH  HL
              PUSH  BC
              CALL  CFG009
              POP   BC
              POP   HL
CFG005       INC   HL
              DJNZ  CFG003
              JP    CFG002
CFG006       CALL  CFG009
              LD    DE,CON006
              LD    C,16
              CALL  BDOS
              OR    A
              RET
CON002   SCF
              RET
CFG007    PUSH  HL
              PUSH  DE
              LD    E,A
              LD    A,(LIN001)
              CP    62
              JP    NC,CFG008
              LD    L,A
              LD    H,0
              LD    BC,LIN002
              ADD   HL,BC
              LD    (HL),E
              LD    A,(LIN001)
              INC   A
              LD    (LIN001),A
CFG008   POP   DE
              POP   HL
              RET
CFG009      LD    A,(LIN001)
              OR    A
              RET   Z
              LD    L,A
              LD    H,0
              LD    DE,LIN002
              ADD   HL,DE
              LD    (HL),0
              XOR   A
              LD    (LIN001),A
              LD    A,(LIN002)
              CP    '#'
              RET   Z
              CP    03BH
              RET   Z
              LD    HL,LIN002
              LD    DE,K_IP
              CALL  PREFIX
              JP    NC,CFG_IP
              LD    HL,LIN002
              LD    DE,K_N001
              CALL  PREFIX
              JP    NC,CFG010
              LD    HL,LIN002
              LD    DE,K_MASK
              CALL  PREFIX
              JP    NC,CFG010
              LD    HL,LIN002
              LD    DE,K_GW
              CALL  PREFIX
              JP    NC,CFG_GW
              LD    HL,LIN002
              LD    DE,K_HOST
              CALL  PREFIX
              JP    NC,CFG011
              LD    HL,LIN002
              LD    DE,K_MAC
              CALL  PREFIX
              JP    NC,CFG013
              LD    HL,LIN002
              LD    DE,K_SLOT
              CALL  PREFIX
              JP    NC,CFG014
              LD    HL,LIN002
              LD    DE,K_PORT
              CALL  PREFIX
              JP    NC,CFG016
              LD    HL,LIN002
              LD    DE,K_R001
              CALL  PREFIX
              JP    NC,CFG015
              LD    DE,MSG014
              CALL  PRINT
              JP    CFG018
CFG_IP        LD    DE,CFG019
              JP    CFG012
CFG010      LD    DE,CFG020
              JP    CFG012
CFG_GW        LD    DE,CFG021
              JP    CFG012
CFG011      LD    DE,CFG022
CFG012     CALL  IPV4
              JP    C,CFG017
              RET
CFG013    LD    DE,CFG023
              CALL  MAC001
              JP    C,CFG017
              RET
CFG014      CALL  DEC8
              JP    C,CFG017
              CP    1
              JP    C,CFG017
              CP    8
              JP    NC,CFG017
              CP    4                        ; slot 4 contains the SoftCard
              JP    Z,CFG017
              LD    (CFG025),A
              RET
CFG015     CALL  DEC8
              JP    C,CFG017
              CP    2
              JP    NC,CFG017
              LD    (CFG026),A
              RET
CFG016      CALL  DEC16
              JP    C,CFG017
              LD    A,H
              OR    L
              JP    Z,CFG017
              LD    A,H
              LD    (CFG024),A
              LD    A,L
              LD    (CFG024+1),A
              RET
CFG017   LD    DE,MSG015
              CALL  PRINT
CFG018      LD    HL,LIN002
CFG_EL        LD    A,(HL)
              OR    A
              JP    Z,NEW001
              PUSH  HL
              CALL  PUTC
              POP   HL
              INC   HL
              JP    CFG_EL
; PREFIX: HL=line, DE=literal 0-terminated prefix.
; success carry clear and HL points just after prefix.
PREFIX        LD    A,(DE)
              OR    A
              JP    Z,PRE001
              CP    (HL)
              JP    NZ,PRE002
              INC   DE
              INC   HL
              JP    PREFIX
PRE001     OR    A
              RET
PRE002    SCF
              RET
; MACADDR: parse HH:HH:HH:HH:HH:HH; HL=input, DE=six bytes.
MAC001       LD    A,6
              LD    (MAC005),A
MAC002      PUSH  DE
              CALL  HEX001
              POP   DE
              RET   C
              LD    (DE),A
              INC   DE
              LD    A,(MAC005)
              DEC   A
              LD    (MAC005),A
              JP    Z,MAC003
              LD    A,(HL)
              CP    ':'
              JP    NZ,MAC004
              INC   HL
              JP    MAC002
MAC003       LD    A,(HL)
              OR    A
              JP    NZ,MAC004
              RET
MAC004       SCF
              RET
HEX001       LD    A,(HL)
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
              JP    C,MAC004
              CP    '9'+1
              JP    NC,HEX002
              SUB   '0'
              RET
HEX002      CP    'A'
              JP    C,MAC004
              CP    'F'+1
              JP    NC,MAC004
              SUB   'A'-10
              RET
; DEC8: HL->digits, returns A and HL->NUL; CY on syntax/overflow.
DEC8          LD    B,0
              LD    E,0
D8_001       LD    A,(HL)
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
              JP    D8_001
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
              LD    (IP_003),A
IP_001       PUSH  DE
              CALL  DEC001
              POP   DE
              RET   C
              LD    (DE),A
              INC   DE
              LD    A,(IP_003)
              DEC   A
              LD    (IP_003),A
              JP    Z,IP_002
              LD    A,(HL)
              CP    '.'
              JP    NZ,IP_BAD
              INC   HL
              JP    IP_001
IP_002       LD    A,(HL)
              OR    A
              JP    NZ,IP_BAD
              RET
IP_BAD        SCF
              RET
; Similar to DEC8 but stops on '.' and leaves HL on delimiter.
DEC001     LD    B,0
              LD    E,0
D8P001      LD    A,(HL)
              CP    '.'
              JP    Z,D8P002
              OR    A
              JP    Z,D8P002
              CP    '0'
              JP    C,D8P003
              CP    '9'+1
              JP    NC,D8P003
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
              JP    D8P001
D8P002       LD    A,E
              OR    A
              JP    Z,D8P003
              LD    A,B
              OR    A
              RET
D8P003       SCF
              RET
; Decimal 16-bit port parsing, HL->digit string, returns HL=port.
; Uses a temporary byte to simplify the Z80 multiply-by-ten.
DEC16         EX    DE,HL
              LD    HL,0
              LD    A,0
              LD    (DIG001),A
D16001      LD    A,(DE)
              OR    A
              JP    Z,D16002
              CP    '0'
              JP    C,D16003
              CP    '9'+1
              JP    NC,D16003
              SUB   '0'
              LD    (DIGIT),A
              ADD   HL,HL
              JP    C,D16003
              LD    B,H
              LD    C,L
              ADD   HL,HL
              JP    C,D16003
              ADD   HL,HL
              JP    C,D16003
              ADD   HL,BC
              JP    C,D16003
              LD    A,(DIGIT)
              LD    C,A
              LD    B,0
              ADD   HL,BC
              JP    C,D16003
              LD    A,(DIG001)
              INC   A
              LD    (DIG001),A
              INC   DE
              JP    D16001
D16002       LD    A,(DIG001)
              OR    A
              JP    Z,D16003
              OR    A
              RET
D16003       SCF
              RET

VAL001  LD    A,(CFG019)
              OR    A
              JP    Z,VAL002
              LD    A,(CFG020)
              OR    A
              JP    Z,VAL002
              LD    A,(CFG022)
              OR    A
              JP    Z,VAL002
              OR    A
              RET
VAL002     SCF
              RET

PRI003     LD    DE,MSG004
              CALL  PRINT
              LD    DE,MSG005
              CALL  PRINT
              LD    A,(CFG025)
              ADD   A,'0'
              CALL  PUTC
              CALL  NEW001
              LD    DE,MSG006
              CALL  PRINT
              LD    HL,CFG023
              CALL  PRINT_MAC_BYTES
              LD    DE,MSG007
              LD    HL,CFG019
              CALL  PRI004
              LD    DE,MSG008
              LD    HL,CFG020
              CALL  PRI004
              LD    DE,MSG009
              LD    HL,CFG021
              CALL  PRI004
              LD    DE,MSG010
              LD    HL,CFG022
              CALL  PRI004
              LD    DE,MSG011
              CALL  PRINT
              LD    A,(CFG024)
              CALL  HEX
              LD    A,(CFG024+1)
              CALL  HEX
              CALL  NEW001
              LD    DE,MSG012
              CALL  PRINT
              LD    A,(CFG026)
              ADD   A,'0'
              CALL  PUTC
              JP    NEW001
PRINT_MAC_BYTES
              LD    B,6
PRMAC         LD    A,(HL)
              CALL  HEX
              INC   HL
              DEC   B
              JP    Z,PRM001
              LD    A,':'
              CALL  PUTC
              JP    PRMAC
PRM001     JP    NEW001
PRI004      PUSH  HL
              CALL  PRINT
              POP   HL
              LD    B,4
PIP001      LD    A,(HL)
              CALL  HEX
              INC   HL
              DEC   B
              JP    Z,NEW001
              LD    A,'.'
              CALL  PUTC
              JP    PIP001

; -------- HARDWARE PORTS -------------------------------------------------
; v0.9 on real hardware proved LD (BC),A works for DATA_WR, while
; LD (nn),A did not. v1.0 incorrectly changed pointer writes as well.
; Preserve v0.9's known-working address-pointer routines, and use
; register-indirect write ONLY for the W5100 data port.
SET001   LD    A,(CFG025)
              ADD   A,A
              ADD   A,A
              ADD   A,A
              ADD   A,A
              ADD   A,084H
              LD    (MOD001+1),A
              LD    (MOD002+1),A
              INC   A
              LD    (ADD001+1),A
              LD    (ADD003+1),A
              INC   A
              LD    (ADD002+1),A
              LD    (ADD004+1),A
              INC   A
              LD    (DAT001+1),A
              RET
MOD001       LD    A,(0E0B4H)
              RET
ADD001     LD    A,(0E0B5H)
              RET
ADD002     LD    A,(0E0B6H)
              RET
DAT001       LD    A,(0E0B7H)
              RET
; Preserve the mode register write form from v0.9 (RESET=0 never uses it).
MOD002       LD    (0E0B4H),A
              RET
; These two routines were working in the v0.9 opcode-comparison test.
ADD003     LD    (0E0B5H),A
              RET
ADD004     LD    (0E0B6H),A
              RET
; Only data-port writes use the experimentally confirmed indirect form.
; Mirror the exact proven v0.9 LD (HL),A hardware write sequence.
; Save the W5100 register address in HL because WBLOCK needs it intact.
; A is the byte to write; all BC/DE/HL preserved.
DAT002       PUSH  HL
              PUSH  AF
              LD    A,(DAT001+1)
              LD    L,A
              LD    H,0E0H
              POP   AF
              LD    (HL),A
              POP   HL
              RET
; Set W5100 16-bit internal pointer HL high then low, preserve HL.
WSEL          PUSH  AF
              LD    A,H
              CALL  ADD003
              LD    A,L
              CALL  ADD004
              POP   AF
              RET
; TELNET v1.5: hybrid W5100 access. Native Z80 reads, native 6502 writes.
; The v1.4 first 6502 READ handoff hung after W5100 mode display.
; Preserve working v1.3 read path; use 6502 only for writes.
WREAD         CALL  WSEL
              JP    DAT001
; Read B consecutive bytes into (DE) without BDOS or other interrupts.
; Mode $03/$13: hardware auto-increments W5100 indirect address.
; Mode $01/$11: pointer does NOT auto-increment; explicitly reselect for
; every byte. Never change VEDRIVE's mode register merely for efficiency.
WRE001    LD    A,(HW_009)
              AND   002H
              JP    Z,WRB002
              CALL  WSEL
WRB001      CALL  DAT001
              LD    (DE),A
              INC   DE
              DJNZ  WRB001
              RET
WRB002    CALL  WREAD
              LD    (DE),A
              INC   DE
              INC   HL
              DJNZ  WRB002
              RET
; WWRITE: HL=W5100 address, A=data. Never switch CPUs directly
; from an AUX transient: private BDOS $F9 travels via AXGATE.
WWRITE        PUSH  AF
              PUSH  BC
              PUSH  DE
              PUSH  HL
              LD    A,H
              LD    (W5P001),A
              LD    A,L
              LD    (W5P001+1),A
              POP   HL
              POP   DE
              POP   BC
              POP   AF
              LD    (W5P001+2),A
              PUSH  AF
              PUSH  BC
              PUSH  DE
              PUSH  HL
              LD    DE,W5P001
              LD    C,0F9H
              CALL  BDOS
              POP   HL
              POP   DE
              POP   BC
              POP   AF
              RET
W5P001       DEFB  0,0,0
; All W5100 reads use the v1.3 native Z80 path proven on hardware.
; All writes use one native 6502 handoff per byte, with explicit address.
; Avoid BDOS inside individual W5100 transactions.
WBLOCK        LD    A,(DE)
              CALL  WWRITE
              INC   DE
              INC   HL
              DJNZ  WBLOCK
              RET

HW_001       LD    A,(CFG026)
              OR    A
              JP    Z,HW_002
              LD    DE,MSG016
              CALL  PRINT
              LD    A,080H
              CALL  MOD002
HW_002   LD    A,(CFG026)
              OR    A
              JP    Z,HW_003
; Fresh reset only: program our preferred mode.  With VEDRIVE active,
; use the pre-existing mode without writing even a single byte to MR.
              LD    A,003H
              CALL  MOD002
HW_003 CALL  MOD001
              LD    (HW_009),A
; Always print *actual* mode, even for a failed probe (v0.3 omitted it).
              LD    DE,MSG017
              CALL  PRINT
              LD    A,(HW_009)
              CALL  HEX
              CALL  NEW001
; W5100 MR bit 0 = indirect addressing, the only mandatory bit.
; $03 is normal, $13 enables ping-block; $01/$11 omit auto-increment.
              LD    A,(HW_009)
              AND   001H
              JP    NZ,HW_INDIRECT_OK
              LD    DE,MSG024
              CALL  PRINT
              SCF
              RET
HW_INDIRECT_OK
              LD    A,(HW_009)
              AND   002H
              JP    NZ,HW_004
              LD    DE,MSG025
              CALL  PRINT
              JP    HW_005
HW_004      LD    DE,MSG026
              CALL  PRINT
HW_005     LD    HL,001AH
              CALL  WREAD
              LD    (RX_007),A
              LD    DE,MSG018
              CALL  PRINT
              LD    A,(RX_007)
              CALL  HEX
              CALL  NEW001
              LD    HL,001BH
              CALL  WREAD
              LD    (TX_001),A
              LD    DE,MSG019
              CALL  PRINT
              LD    A,(TX_001)
              CALL  HEX
              CALL  NEW001
; With RESET=1, force standard 2KB per socket. With RESET=0 preserve
; existing layout (including $06 used with a 4KB socket 0) and derive
; socket-1 bases and circular-buffer masks without modifying allocation.
              LD    A,(CFG026)
              OR    A
              JP    Z,HW_CHECK_BUFFERS
              LD    HL,001AH
              LD    A,055H
              CALL  WWRITE
              LD    HL,001BH
              LD    A,055H
              CALL  WWRITE
              LD    A,055H
              LD    (RX_007),A
              LD    (TX_001),A
HW_CHECK_BUFFERS
              LD    A,(TX_001)
              CALL  WBU004
              JP    C,HW_007
              LD    A,(RX_007)
              CALL  WBU005
              JP    C,HW_007
              LD    DE,MSG021
              CALL  PRINT
              LD    A,(TX_002)
              CALL  HEX
              LD    A,0
              CALL  HEX
              LD    DE,MSG023
              CALL  PRINT
              LD    A,(TX_003)
              CALL  HEX
              CALL  NEW001
              LD    DE,MSG022
              CALL  PRINT
              LD    A,(RX_008)
              CALL  HEX
              LD    A,0
              CALL  HEX
              LD    DE,MSG023
              CALL  PRINT
              LD    A,(RX_009)
              CALL  HEX
              CALL  NEW001
; Print socket states before touching socket 1, so VEDRIVE ownership is
; evident on a real Apple //e.  SR codes 00=CLOSED, 22=UDP, 17=TCP.
              LD    DE,MSG027
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
              CALL  NEW001
              LD    A,(CFG026)
              OR    A
              JP    NZ,HW_006
; VEDRIVE-safe attach: read live hardware IP/netmask/GW/MAC and compare
; to TELNET.CFG.  NEVER change these shared registers in attach mode.
              LD    DE,MSG028
              CALL  PRINT
              LD    HL,0001H
              LD    DE,HW_010
              LD    B,4
              CALL  WRE001
              LD    HL,0005H
              LD    DE,HW_011
              LD    B,4
              CALL  WRE001
              LD    HL,0009H
              LD    DE,HW_MAC
              LD    B,6
              CALL  WRE001
              LD    HL,000FH
              LD    DE,HW_012
              LD    B,4
              CALL  WRE001
              LD    DE,MSG029
              LD    HL,HW_010
              CALL  PRI004
              LD    DE,MSG030
              LD    HL,HW_011
              CALL  PRI004
              LD    DE,MSG031
              LD    HL,HW_012
              CALL  PRI004
              LD    DE,MSG032
              CALL  PRINT
              LD    HL,HW_MAC
              CALL  PRINT_MAC_BYTES
              LD    HL,HW_010
              LD    DE,CFG021
              LD    B,4
              CALL  COM001
              JP    C,HW_NET_MISMATCH
              LD    HL,HW_011
              LD    DE,CFG020
              LD    B,4
              CALL  COM001
              JP    C,HW_NET_MISMATCH
              LD    HL,HW_012
              LD    DE,CFG019
              LD    B,4
              CALL  COM001
              JP    C,HW_NET_MISMATCH
              LD    HL,HW_MAC
              LD    DE,CFG023
              LD    B,6
              CALL  COM001
              JP    C,HW_NET_MISMATCH
              LD    DE,MSG033
              CALL  PRINT
              OR    A
              RET
HW_NET_MISMATCH
              LD    DE,MSG034
              CALL  PRINT
              OR    A                     ; warning only: use live chip config
              RET
; Fresh setup is ONLY legal with RESET=1.  RESET tears down VEDRIVE.
HW_006  LD    DE,MSG035
              CALL  PRINT
              LD    HL,0001H
              LD    DE,CFG021
              LD    B,4
              CALL  WBLOCK
              LD    HL,0005H
              LD    DE,CFG020
              LD    B,4
              CALL  WBLOCK
              LD    HL,0009H
              LD    DE,CFG023
              LD    B,6
              CALL  WBLOCK
              LD    HL,000FH
              LD    DE,CFG019
              LD    B,4
              CALL  WBLOCK
              OR    A
              RET
; A=(DE) is expected config; (HL) is active W5100 byte.
COM001 LD    A,(DE)
              CP    (HL)
              JP    NZ,CMP001
              INC   DE
              INC   HL
              DJNZ  COM001
              OR    A
              RET
CMP001    SCF
              RET
HW_007 LD    DE,MSG020
              CALL  PRINT
HW_008      SCF
              RET

; Derive socket-1 buffer base (high address byte) and mask (high byte)
; from one W5100 allocation register (RX or TX).  Each socket's two-bit
; field encodes 1, 2, 4 or 8 KB; socket 1 starts after socket 0.
; B = size of socket 0 in 256-byte pages (4,8,16,32),
; C = (size of socket 1 in pages)-1 (3,7,15,31).
; Reject only arrangements that put socket 1 past the 8KB RX/TX space.
WBU001     PUSH  AF
              AND   003H
              LD    L,A
              LD    H,0
              LD    DE,WBU003
              ADD   HL,DE
              LD    B,(HL)
              POP   AF
              RRCA
              RRCA
              AND   003H
              LD    L,A
              LD    H,0
              LD    DE,WBU003
              ADD   HL,DE
              LD    C,(HL)
              LD    A,B
              ADD   A,C
              CP    021H                 ; 32 pages = 8KB, inclusive
              JP    NC,WBU002
              DEC   C                     ; bit mask for ring address high
              OR    A                     ; carry clear
              RET
WBU002  SCF
              RET
WBU003    DEFB  004H,008H,010H,020H

WBU004       CALL  WBU001
              RET   C
              LD    A,B
              ADD   A,040H               ; transmit memory starts at $4000
              LD    (TX_002),A
              LD    A,C
              LD    (TX_003),A
              OR    A
              RET
WBU005       CALL  WBU001
              RET   C
              LD    A,B
              ADD   A,060H               ; receive memory starts at $6000
              LD    (RX_008),A
              LD    A,C
              LD    (RX_009),A
              OR    A
              RET

; -------- SOCKET 1: TCP --------------------------------------------------
SOC001    LD    DE,MSG041
              CALL  PRINT
              LD    HL,S1SR
              CALL  WREAD
              PUSH  AF
              CALL  HEX
              CALL  NEW001
              POP   AF
              OR    A
              JP    NZ,SOC002
              LD    DE,MSG039
              CALL  PRINT
              LD    HL,S1MR
              LD    A,1
              CALL  WWRITE
              LD    DE,MSG040
              CALL  PRINT
              ; Check the TCP mode write immediately, before block writes.
              LD    HL,S1MR
              CALL  WREAD
              LD    (DBG006),A
              LD    HL,S1PORT
              LD    DE,LOC001
              LD    B,2
              CALL  WBLOCK
              ; Determine whether the PORT block write changed Sn_MR.
              LD    HL,S1MR
              CALL  WREAD
              LD    (DBG007),A
              LD    HL,S1DIP
              LD    DE,CFG022
              LD    B,4
              CALL  WBLOCK
              LD    HL,S1D001
              LD    DE,CFG024
              LD    B,2
              CALL  WBLOCK
              ; Detect whether destination block writes changed Sn_MR.
              LD    HL,S1MR
              CALL  WREAD
              LD    (DBG008),A
              ; Read out checkpoints now (after the critical writes).
              LD    DE,MSG045
              CALL  PRINT
              LD    A,(DBG006)
              CALL  HEX
              CALL  NEW001
              LD    DE,MSG046
              CALL  PRINT
              LD    A,(DBG007)
              CALL  HEX
              CALL  NEW001
              LD    DE,MSG047
              CALL  PRINT
              LD    A,(DBG008)
              CALL  HEX
              CALL  NEW001
              ; Reassert TCP mode LAST, to isolate mode-write problems from
              ; subsequent WBLOCK address-pointer/buffer operations.
              LD    HL,S1MR
              LD    A,1
              CALL  WWRITE
              LD    HL,S1MR
              CALL  WREAD
              LD    (DBG009),A
              LD    DE,MSG048
              CALL  PRINT
              LD    A,(DBG009)
              CALL  HEX
              CALL  NEW001
              ; Do not issue OPEN if mode still isn't TCP: avoid changing
              ; socket state when we already know initialization failed.
              LD    A,(DBG009)
              CP    1
              JP    NZ,DBG005
              ; Do not clear Sn_IR before opening: inspect its old value.
              ; Read all setup fields back, including the source port.
              LD    DE,MSG049
              CALL  PRINT
              LD    HL,S1MR
              CALL  WREAD
              CALL  HEX
              CALL  NEW001
              LD    DE,MSG050
              CALL  PRINT
              LD    HL,S1PORT
              CALL  WREAD
              CALL  HEX
              LD    HL,S1PORT+1
              CALL  WREAD
              CALL  HEX
              CALL  NEW001
              LD    DE,MSG051
              CALL  PRINT
              LD    HL,S1CR
              CALL  WREAD
              CALL  HEX
              CALL  NEW001
              LD    DE,MSG052
              CALL  PRINT
              LD    HL,S1IR
              CALL  WREAD
              CALL  HEX
              CALL  NEW001
              ; No BDOS calls between command write and immediate CR sample.
              LD    HL,S1CR
              LD    A,1
              CALL  WWRITE
              LD    HL,S1CR
              CALL  WREAD
              LD    (DBG010),A
              ; Poll Sn_CR; do not rely on one immediate Sn_SR sample.
              LD    BC,8000
DBG001    LD    HL,S1CR
              CALL  WREAD
              OR    A
              JP    Z,DBG002
              DEC   BC
              LD    A,B
              OR    C
              JP    NZ,DBG001
              LD    DE,MSG065
              CALL  PRINT
              SCF
              RET
DBG002    LD    HL,S1SR
              CALL  WREAD
              LD    (DBG011),A
              LD    HL,S1IR
              CALL  WREAD
              LD    (DBG012),A
              LD    DE,MSG053
              CALL  PRINT
              LD    A,(DBG010)
              CALL  HEX
              CALL  NEW001
              LD    DE,MSG054
              CALL  PRINT
              LD    HL,S1CR
              CALL  WREAD
              CALL  HEX
              CALL  NEW001
              LD    DE,MSG055
              CALL  PRINT
              LD    A,(DBG011)
              CALL  HEX
              CALL  NEW001
              LD    DE,MSG056
              CALL  PRINT
              LD    A,(DBG012)
              CALL  HEX
              CALL  NEW001
              ; Probe status repeatedly before declaring failure.
              LD    BC,16000
DBG003    LD    HL,S1SR
              CALL  WREAD
              CP    013H
              JP    Z,DBG004
              DEC   BC
              LD    A,B
              OR    C
              JP    NZ,DBG003
              LD    DE,MSG057
              CALL  PRINT
              LD    HL,S1MR
              CALL  WREAD
              CALL  HEX
              CALL  NEW001
              JP    SOC002
DBG004     LD    HL,S1SR
              CALL  WREAD
              LD    DE,MSG043
              PUSH  AF
              CALL  PRINT
              POP   AF
              CALL  HEX
              CALL  NEW001
              OR    A
              RET
DBG005   LD    DE,MSG044
              CALL  PRINT
              SCF
              RET
SOC002     LD    DE,MSG042
              CALL  PRINT
              SCF
              RET

SOC003  LD    A,4
              CALL  COM002
              RET   C
              LD    BC,30000
              LD    DE,0
CON003  LD    HL,S1SR
              CALL  WREAD
              CP    017H
              JP    Z,CON004
              CP    000H
              JP    Z,CON005
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
              JP    NZ,CON003
              PUSH  BC
              LD    DE,MSG060
              CALL  PRINT
              LD    HL,S1SR
              CALL  WREAD
              CALL  HEX
              CALL  NEW001
              LD    C,11
              CALL  BDOS
              POP   BC
              JP    CON003
CON004    OR    A
              RET
CON005   LD    DE,MSG062
              CALL  PRINT
              SCF
              RET
CONNECT_TIMEOUT
              LD    DE,MSG_IR
              CALL  PRINT
              LD    HL,S1IR
              CALL  WREAD
              CALL  HEX
              CALL  NEW001
              LD    DE,MSG061
              CALL  PRINT
              SCF
              RET
; A=command, waits for CR to clear with finite counter.
COM002       LD    HL,S1CR
              CALL  WWRITE
              LD    BC,8000
CMD001      LD    HL,S1CR
              CALL  WREAD
              OR    A
              RET   Z
              DEC   BC
              LD    A,B
              OR    C
              JP    NZ,CMD001
              LD    DE,MSG065
              CALL  PRINT
              SCF
              RET

; v1.8b conservative batching: use the EXACT verified v1.7 WREAD
; for every incoming byte. Only defer RX_RD/RECV acknowledgment to once
; per batch. No W5100 sequential-auto-increment assumptions.
; At most 16 bytes buffered: a deliberately small first experiment.
RX_ONE        LD    A,(RX_011)
              OR    A
              JP    Z,RX_001
RX_POP        LD    A,(RX_012)
              LD    E,A
              LD    D,0
              LD    HL,RX_014
              ADD   HL,DE
              LD    A,(HL)
              LD    (RX_010),A
              LD    A,(RX_012)
              INC   A
              LD    (RX_012),A
              LD    A,(RX_011)
              DEC   A
              LD    (RX_011),A
              LD    A,(RX_010)
              OR    A
              RET
RX_001     LD    HL,S1R001
              CALL  WREAD
              LD    B,A
              INC   HL
              CALL  WREAD
              LD    C,A
              LD    A,B
              OR    A
              JP    NZ,RX_002
              LD    A,C
              OR    A
              JP    Z,RX_006
              CP    17
              JP    C,RX_003
RX_002      LD    A,16
RX_003      LD    (RX_013),A
              LD    HL,S1RXRD
              CALL  WREAD
              LD    (RX_015),A
              INC   HL
              CALL  WREAD
              LD    (RX_016),A
              XOR   A
              LD    (RX_012),A
RX_004  ; Each byte recomputes its W5100 ring address and WREAD
              ; selects that address explicitly, as v1.7 did.
              LD    A,(RX_015)
              LD    H,A
              LD    A,(RX_009)
              AND   H
              LD    H,A
              LD    A,(RX_008)
              OR    H
              LD    H,A
              LD    A,(RX_016)
              LD    L,A
              CALL  WREAD
              PUSH  AF
              LD    A,(RX_012)
              LD    E,A
              LD    D,0
              LD    HL,RX_014
              ADD   HL,DE
              POP   AF
              LD    (HL),A
              LD    A,(RX_016)
              INC   A
              LD    (RX_016),A
              JP    NZ,RX_005
              LD    A,(RX_015)
              INC   A
              LD    (RX_015),A
RX_005   LD    A,(RX_012)
              INC   A
              LD    (RX_012),A
              LD    B,A
              LD    A,(RX_013)
              CP    B
              JP    NZ,RX_004
              ; Both pointer bytes are now ready, one RECV per batch.
              LD    HL,S1RXRD
              LD    DE,RX_015
              LD    B,2
              CALL  WBLOCK
              LD    A,040H
              CALL  COM002
              JP    C,RX_006
              XOR   A
              LD    (RX_012),A
              LD    A,(RX_013)
              LD    (RX_011),A
              JP    RX_POP
RX_006      SCF
              RET

; Send B bytes from DE: Sn_TX_WR, ring wrap according to TMSR.
; Never call BDOS while an indirect W5100 pointer is active.
SEN001    LD    A,B
              OR    A
              RET   Z
              LD    (SEN005),A
              LD    (SEN006),DE
              LD    HL,S1T001
              CALL  WREAD
              LD    C,A
              INC   HL
              CALL  WREAD
              LD    B,A
              LD    A,C
              OR    A
              JP    NZ,SEN002       ; available >=256
              LD    A,(SEN005)
              CP    B
              JP    C,SEN002
              JP    Z,SEN002
              LD    DE,MSG069
              CALL  PRINT
              SCF
              RET
SEN002 LD    HL,S1TXWR
              CALL  WREAD
              LD    B,A
              INC   HL
              CALL  WREAD
              LD    C,A
              LD    A,B
              LD    (TX_004),A
              LD    A,C
              LD    (TX_005),A
SEN003     LD    DE,(SEN006)
              LD    A,(DE)
              LD    (TX_006),A
              INC   DE
              LD    (SEN006),DE
              LD    A,(TX_004)
              LD    H,A
              LD    A,(TX_003)
              AND   H
              LD    H,A
              LD    A,(TX_002)
              OR    H
              LD    H,A
              LD    A,(TX_005)
              LD    L,A
              LD    A,(TX_006)
              CALL  WWRITE
              LD    A,(TX_005)
              INC   A
              LD    (TX_005),A
              JP    NZ,SEND_NEXT
              LD    A,(TX_004)
              INC   A
              LD    (TX_004),A
SEND_NEXT
              LD    A,(SEN005)
              DEC   A
              LD    (SEN005),A
              JP    NZ,SEN003
              LD    HL,S1TXWR
              LD    DE,TX_004
              LD    B,2
              CALL  WBLOCK
              LD    A,020H
              JP    COM002
; Send one keyboard byte (CR as CR LF); IAC $FF escaped as $FF $FF.
SEN004      LD    (SEN007),A
              LD    B,1
              CP    13
              JP    NZ,SK_001
              LD    A,10
              LD    (SEN007+1),A
              LD    B,2
SK_001    LD    A,(SEN007)
              CP    0FFH
              JP    NZ,SK_002
              LD    A,0FFH
              LD    (SEN007+1),A
              LD    B,2
SK_002       LD    DE,SEN007
              JP    SEN001

; Basic TELNET IAC: accept remote ECHO/SGA; reject other options.
; Reply to every incoming WILL/WONT/DO/DONT; ignore subnegotiations.
TEL_IN        LD    B,A
              LD    A,(TN_013)
              OR    A
              JP    Z,TN_001
              CP    1
              JP    Z,TN_IAC
              CP    2
              JP    Z,TN_008
              CP    3
              JP    Z,TN_SUB
              CP    4
              JP    Z,TN_006
              XOR   A
              LD    (TN_013),A
              RET
TN_001       LD    A,B
              CP    0FFH
              JP    NZ,TN_002
              LD    A,1
              LD    (TN_013),A
              RET
TN_002     LD    E,A
              LD    C,6                      ; BDOS 6: raw console output
              JP    BDOS
TN_IAC        LD    A,B
              CP    0FFH
              JP    Z,TN_003
              CP    0FAH                    ; SB
              JP    Z,TN_004
              CP    0FBH                    ; WILL
              JP    Z,TN_005
              CP    0FCH                    ; WONT
              JP    Z,TN_005
              CP    0FDH                    ; DO
              JP    Z,TN_005
              CP    0FEH                    ; DONT
              JP    Z,TN_005
              XOR   A
              LD    (TN_013),A
              RET
TN_003  XOR   A
              LD    (TN_013),A
              LD    A,'?'                  ; BDOS 6 uses $FF as CONIN, not output
              JP    TN_002
TN_004   LD    A,3
              LD    (TN_013),A
              RET
TN_005     LD    (TN_014),A
              LD    A,2
              LD    (TN_013),A
              RET
TN_SUB        LD    A,B
              CP    0FFH
              RET   NZ
              LD    A,4
              LD    (TN_013),A
              RET
TN_006     LD    A,B
              CP    0F0H                    ; SE
              JP    Z,TN_007
              LD    A,3
              LD    (TN_013),A
              RET
TN_007    XOR   A
              LD    (TN_013),A
              RET
TN_008     XOR   A
              LD    (TN_013),A
              LD    A,B
              LD    (TN_BUF+2),A
              LD    A,(TN_014)
              CP    0FBH                    ; WILL -> DO or DONT
              JP    Z,TN_009
              CP    0FDH                    ; DO -> WILL or WONT
              JP    Z,TN_DO
              RET                            ; WONT/DONT: accept silently
TN_009       LD    A,B
              CP    1                       ; ECHO
              JP    Z,TN_010
              CP    3                       ; SUPPRESS-GO-AHEAD
              JP    Z,TN_010
              LD    A,0FEH                   ; DONT
              JP    TN_012
TN_010    LD    A,0FDH                   ; DO
              JP    TN_012
TN_DO         LD    A,B
              CP    3
              JP    Z,TN_011
              LD    A,0FCH                   ; WONT
              JP    TN_012
TN_011  LD    A,0FBH                   ; WILL
TN_012      LD    (TN_BUF+1),A
              LD    DE,TN_BUF
              LD    B,3
              CALL  SEN001
              RET

MAI001     XOR   A
              LD    (QUI001),A
              CALL  RX_ONE
              JP    C,MAI002
              CALL  TEL_IN
MAI002    LD    HL,(POL001)
              INC   HL
              LD    (POL001),HL
              LD    A,H
              AND   00FH
              OR    L
              JP    NZ,MAI003
              LD    DE,MSG066
              CALL  PRINT
              LD    HL,S1SR
              CALL  WREAD
              CALL  HEX
              CALL  NEW001
MAI003    XOR   A
              LD    (QUI001),A
              LD    HL,S1SR
              CALL  WREAD
              CP    017H
              JP    Z,MAI004
              CP    01CH                    ; CLOSE_WAIT: drain outstanding data first
              JP    Z,MAI004
              LD    DE,MSG068
              CALL  PRINT
              JP    CLO001
MAI004      LD    C,11                    ; cooperative scheduler+keyboard status
              CALL  BDOS
              OR    A
              JP    Z,MAI001
              LD    E,0FFH
              LD    C,6                     ; non-blocking read
              CALL  BDOS
              AND   07FH
              CP    01DH                    ; Ctrl-] leaves telnet
              JP    Z,CLO001
              ; Ctrl-C (03h) is forwarded to the remote host.
              CALL  SEN004
              JP    C,CLO001
              JP    MAI001
CLO001    LD    DE,MSG070
              CALL  PRINT
              LD    A,010H
              CALL  COM002               ; CLOSE socket 1 only
              JP    EXIT

; --- Data and ASCII diagnostics ------------------------------------------
MSG001    DEFB  13,10
              DEFM  'Zapple-II TELNET/W5100 v1.9'
              DEFB  13,10
              DEFB  '$'
MSG002    DEFB  13,10
              DEFM  'Usage: TELNET [a.b.c.d [port]] [-v]'
              DEFB  13,10,'$'
MSG003   DEFM  '[01] opening TELNET.CFG'
              DEFB  13,10
              DEFB  '$'
MSG004       DEFM  '[02] configuration (IPs shown as HEX octets)'
              DEFB  13,10
              DEFB  '$'
MSG005      DEFM  ' slot = $'
MSG006       DEFM  ' MAC = $'
MSG007     DEFM  ' local IP = $'
MSG008      DEFM  ' netmask  = $'
MSG009   DEFM  ' gateway  = $'
MSG010    DEFM  ' remote IP= $'
MSG011      DEFM  ' remote port HEX = $'
MSG012     DEFM  ' reset W5100 = $'
MSG013    DEFM  'ERROR: TELNET.CFG missing or IP/MASK/HOST invalid'
              DEFB  13,10
              DEFB  '$'
MSG014   DEFM  '[CFG] unknown key: $'
MSG015   DEFM  '[CFG] INVALID value: $'
MSG_HW        DEFM  '[03] probing W5100 / attach or reset mode'
              DEFB  13,10
              DEFB  '$'
MSG016 DEFM  '[WARN] RESET=1: resetting ALL W5100 sockets!'
              DEFB  13,10
              DEFB  '$'
MSG017    DEFM  ' [W5100] mode readback = $'
MSG018   DEFM  ' [W5100] RMSR = $'
MSG019   DEFM  ' [W5100] TMSR = $'
MSG020    DEFM  ' [W5100] socket 1 TX/RX allocation invalid (over 8KB)'
              DEFB  13,10
              DEFB  '$'
MSG021     DEFM  ' [W5100] socket 1 TX base = $'
MSG022     DEFM  ' [W5100] socket 1 RX base = $'
MSG023  DEFM  ' mask high = $'
MSG024  DEFM  ' [SAFE] mode bit 0 (IND) is OFF, cannot access W5100 safely'
              DEFB  13,10
              DEFB  '$'
MSG025    DEFM  ' [W5100] auto-increment OFF, using per-byte addressing'
              DEFB  13,10
              DEFB  '$'
MSG026     DEFM  ' [W5100] auto-increment ON, using block transfers'
              DEFB  13,10
              DEFB  '$'
MSG027   DEFM  ' [W5100] sockets 0/1/2/3 status = $'
MSG028    DEFM  ' [SAFE] RESET=0: keeping VEDRIVE network configuration'
              DEFB  13,10
              DEFB  '$'
MSG029     DEFM  '  active GW  = $'
MSG030   DEFM  '  active MASK= $'
MSG031     DEFM  '  active IP  = $'
MSG032    DEFM  '  active MAC = $'
MSG033     DEFM  ' [SAFE] config matches, shared registers untouched'
              DEFB  13,10
              DEFB  '$'
MSG034 DEFM  ' [SAFE] CONFIG MISMATCH: using active W5100 config (no writes)'
              DEFB  13,10
              DEFB  '$'
MSG035  DEFM  ' [WARN] RESET=1: programming GW/MASK/MAC/IP'
              DEFB  13,10
              DEFB  '$'
MSG036     DEFM  'ERROR: W5100 mode or socket 1 buffer layout invalid'
              DEFB  13,10
              DEFB  '$'
MSG037 DEFM '[BRIDGE] Calling existing 6502 B809 bell...' 
               DEFB 13,10,'$'
MSG038 DEFM '[BRIDGE] Existing 6502 B809 returned'
               DEFB 13,10,'$'
MSG039 DEFM '[BRIDGE] Entering AUX BDOS F9 write'
               DEFB 13,10,'$'
MSG040 DEFM '[BRIDGE] AUX BDOS F9 returned'
               DEFB 13,10,'$'
MSG041      DEFM  '[04] socket 1 previous status = $'
MSG042  DEFM  ' [W5100] socket 1 busy / TCP OPEN failed'
              DEFB  13,10
              DEFB  '$'
MSG043 DEFM  ' [W5100] after OPEN status = $'
MSG044   DEFM  ' [DBG] TCP mode readback failed, OPEN skipped'
              DEFB  13,10
              DEFB  '$'
MSG045    DEFM  ' [DBG] MR right after write = $'
MSG046 DEFM  ' [DBG] MR after PORT block = $'
MSG047 DEFM  ' [DBG] MR after destination = $'
MSG048 DEFM  ' [DBG] MR last re-write = $'
MSG049     DEFM  ' [DBG] Sn_MR = $'
MSG050   DEFM  ' [DBG] Sn_PORT = $'
MSG051    DEFM  ' [DBG] Sn_CR before OPEN = $'
MSG052    DEFM  ' [DBG] Sn_IR before OPEN = $'
MSG053    DEFM  ' [DBG] Sn_CR immediate = $'
MSG054    DEFM  ' [DBG] Sn_CR after poll = $'
MSG055    DEFM  ' [DBG] Sn_SR after poll = $'
MSG056    DEFM  ' [DBG] Sn_IR after poll = $'
MSG057  DEFM  ' [DBG] timeout: Sn_MR = $'
MSG058   DEFM  'ERROR: socket setup'
              DEFB  13,10
              DEFB  '$'
MSG059   DEFM  '[05] CONNECT / wait for ESTABLISHED'
              DEFB  13,10
              DEFB  '$'
MSG060      DEFM  ' [WAIT] socket status = $'
MSG_IR        DEFM  ' [W5100] socket IR = $'
MSG061   DEFM  ' [TIMEOUT] SYN not established (check host/port/gateway)'
              DEFB  13,10
              DEFB  '$'
MSG062    DEFM  ' [W5100] CLOSED before ESTABLISHED'
              DEFB  13,10
              DEFB  '$'
MSG063 DEFM  ' [cleanup] closing socket 1 after failed CONNECT'
              DEFB  13,10
              DEFB  '$'
MSG064   DEFM  'ERROR: failed to connect'
              DEFB  13,10
              DEFB  '$'
MSG065   DEFM  ' [W5100] socket command never cleared'
              DEFB  13,10
              DEFB  '$'
MSG066     DEFM  '[POLL] socket status = $'
MSG067 DEFM  '[06] CONNECTED - Ctrl-] to exit'
              DEFB  13,10
              DEFB  '$'
MSG068 DEFB  13,10
              DEFM  '[TCP] socket disconnected'
              DEFB  13,10
              DEFB  '$'
MSG069    DEFM  '[TX] free buffer low, send aborted'
              DEFB  13,10
              DEFB  '$'
MSG070     DEFB  13,10
              DEFM  '[07] closing socket 1'
              DEFB  13,10
              DEFB  '$'
MSG071      DEFM  '[08] exit to CCP'
              DEFB  13,10
              DEFB  '$'
K_IP          DEFM  'IP='
              DEFB  0
K_N001     DEFM  'NETMASK='
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
K_R001       DEFM  'RESET='
              DEFB  0

VER001       DEFB  0
QUI001    DEFB  0
ARG018     DEFB  0
ARG_IP        DEFS  4
ARG019    DEFS  2
ARG020     DEFW  0
ARG021      DEFW  0
ARG022       DEFS  121
CON006    DEFB  0
              DEFM  'TELNET  CFG'
              DEFS  24
LOC001    DEFB  0C0H,0DEH
CFG019    DEFB  0,0,0,0
CFG020   DEFB  0,0,0,0
CFG021   DEFB  0,0,0,0
CFG022    DEFB  0,0,0,0
CFG023       DEFB  002H,05AH,050H,04CH,045H,001H
CFG024    DEFB  0,23
CFG025   DEFB  3
CFG026 DEFB  0
LIN001      DEFB  0
POL001    DEFW  0
IP_003      DEFB  0
MAC005     DEFB  0
DIG001     DEFB  0
DIGIT         DEFB  0
HW_009       DEFB  0
HW_010    DEFS  4
HW_011    DEFS  4
HW_MAC        DEFS  6
HW_012     DEFS  4
RX_007      DEFB  0
TX_001      DEFB  0
RX_008     DEFB  0
RX_009     DEFB  0
TX_002     DEFB  0
TX_003     DEFB  0
RX_010       DEFB  0
RX_011       DEFB  0
RX_012      DEFB  0
RX_013      DEFB  0
RX_014     DEFS  16
RX_015      DEFB  0
RX_016      DEFB  0
TX_004      DEFB  0
TX_005      DEFB  0
TX_006       DEFB  0
SEN005    DEFB  0
SEN006   DEFW  0
SEN007   DEFB  0,0
TN_013      DEFB  0
TN_014    DEFB  0
TN_BUF        DEFB  0FFH,0,0
LIN002      DEFS  64
REC001       DEFS  128
DBG006    DEFB  0
DBG007   DEFB  0
DBG008   DEFB  0
DBG009   DEFB  0
DBG010     DEFB  0
DBG011     DEFB  0
DBG012     DEFB  0
STACK         DEFS  256
STACKTOP
              END
