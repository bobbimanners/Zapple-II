; Zapple-II TELNET.COM - Phase 4C cleanup of working Phase 4B client
; Udo Munk Z80ASM dialect, labels <= 8 significant characters.
; Kernel owns network configuration (ZAPPLE2.CNF) and sockets (BDOS FA).
; BDOS FB dispatches socket commands, BDOS FC transfers TCP payloads.
; TELNET owns TCP destination setup, Telnet negotiation and console I/O.
; No TELNET.CFG, W5100 reset, application socket scanner or ring arithmetic.
; Do not disturb busy sockets, including those owned by external programs.
; The existing verified W5100 control-register reads and F9 writes remain.
; Uthernet-II and F9 bridge presently expect slot 5.

BDOS          EQU   0005H
S1MR          EQU   0500H
S1CR          EQU   0501H
S1IR          EQU   0502H
S1SR          EQU   0503H
S1PORT        EQU   0504H
S1DIP         EQU   050CH
S1D001       EQU   0510H
; Socket 1 register window is remapped to the acquired hardware socket.

              ORG   0100H
START         LD    SP,STACKTOP
              LD    DE,MSG001
              CALL  PRINT
              CALL  ARG001
              JP    C,FAT001
              ; Phase 2C: network hardware initialized by kernel at boot.
              ; Server IP is required on command line; optional TCP port.
              LD    A,(ARG018)
              OR    A
              JP    Z,FAT001
              CALL  ARG015
              CALL  SET001                  ; fixed slot 5, matches F9 bridge
              LD    DE,MSG_HW
              CALL  PRINT
              CALL  HW_001                  ; probe existing card read-only
              JP    C,FAT003
              CALL  NET_PICK
              JP    C,FAT004
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
FAT003      LD    DE,MSG036
              JP    ERR001
FAT004    LD    DE,MSG058
              JP    ERR001
FAT005    LD    DE,MSG064
              CALL  PRINT
              LD    DE,MSG063
              CALL  PRINT
              LD    A,010H                 ; close our selected socket after OPEN
              CALL  COM002              ; close failed connection before leaving
              JP    EXIT
ERR001    CALL  PRINT
              JP    EXIT
EXIT          CALL  NET_DROP
              LD    DE,MSG071
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
PG_004        DEFW  MSG001,MSG067,MSG068,MSG002
              DEFW  MSG036,MSG058,MSG064,MSG069
              DEFW  MSG070,MSG071,MSG042,MSG061
              DEFW  MSG062,MSG024,MSG044,MSG065
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

; Command-line numeric IP parser (used by ARG001).
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

; -------- HARDWARE PORTS -------------------------------------------------
; v0.9 on real hardware proved LD (BC),A works for DATA_WR, while
; LD (nn),A did not. v1.0 incorrectly changed pointer writes as well.
; Preserve v0.9's known-working address-pointer routines, and use
; register-indirect write ONLY for the W5100 data port.
SET001        LD    A,5                     ; same fixed slot as kernel F9
              ADD   A,A
              ADD   A,A
              ADD   A,A
              ADD   A,A
              ADD   A,084H
              LD    (MOD001+1),A
              INC   A
              LD    (ADD003+1),A
              INC   A
              LD    (ADD004+1),A
              INC   A
              LD    (DAT001+1),A
              RET
MOD001        LD    A,(0E0B4H)
              RET
DAT001        LD    A,(0E0B7H)
              RET
ADD003        LD    (0E0B5H),A
              RET
ADD004        LD    (0E0B6H),A
              RET
; Map socket-1 register references ($0500-$052F) to selected socket.
; Leave all global registers and TX/RX RAM addresses unchanged.
; Input A=high byte, L=low byte; output A=translated high byte.
MAPREG        CP    005H
              RET   NZ
              PUSH  AF
              LD    A,L
              CP    030H
              JP    NC,MAPNO
              POP   AF
              LD    A,(SOCK_HI)
              RET
MAPNO         POP   AF
              RET
; Set W5100 16-bit internal pointer HL high then low, preserve HL.
WSEL          PUSH  AF
              LD    A,H
              CALL  MAPREG
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
; WWRITE: HL=W5100 address, A=data. Never switch CPUs directly
; from an AUX transient: private BDOS $F9 travels via AXGATE.
WWRITE        PUSH  AF
              PUSH  BC
              PUSH  DE
              PUSH  HL
              LD    A,H
              CALL  MAPREG
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

; Attach read-only to the kernel-configured W5100. Never write globals.
; Keep the same indirect-mode check as the working Phase 4B client.
HW_001        CALL  MOD001
              LD    (HW_009),A
              LD    DE,MSG017
              CALL  PRINT
              LD    A,(HW_009)
              CALL  HEX
              CALL  NEW001
              LD    A,(HW_009)
              AND   001H                    ; indirect register access required
              JP    NZ,HW_OK
              LD    DE,MSG024
              CALL  PRINT
              SCF
              RET
HW_OK         LD    DE,MSG027
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
              OR    A
              RET

; Phase 3: kernel-managed socket ownership. No hardware socket scanning.
; E=0 ALLOC, returns A=socket or FF. E=1 FREE, D=socket.
NET_PICK      LD    E,0
              LD    C,0FAH
              CALL  BDOS
              CP    4
              JR    NC,NPKERR
              LD    (SOCK_NO),A
              LD    A,1
              LD    (NET_HELD),A
              LD    A,(SOCK_NO)
              ADD   A,4
              LD    (SOCK_HI),A
              LD    DE,MSG_PICK
              CALL  PRINT
              LD    A,(SOCK_NO)
              CALL  HEX
              CALL  NEW001
              LD    A,(SOCK_NO)
              ADD   A,0DEH                  ; unique local source port
              LD    (LOC001+1),A
              OR    A
              RET
NPKERR        LD    DE,MSG_NOS
              CALL  PRINT
              SCF
              RET
NET_DROP      LD    A,(NET_HELD)
              OR    A
              RET   Z
              XOR   A
              LD    (NET_HELD),A
              LD    A,(SOCK_NO)
              LD    D,A
              LD    E,1
              LD    C,0FAH
              CALL  BDOS
              RET
NET_HELD      DEFB  0

; -------- SELECTED SOCKET: TCP --------------------------------------------------
; OPEN setup remains the exact working register-write path.
; F9 for the control registers, then legacy OPEN command and status polls.
SOC001        LD    DE,MSG041
              CALL  PRINT
              LD    HL,S1SR
              CALL  WREAD
              PUSH  AF
              CALL  HEX
              CALL  NEW001
              POP   AF
              OR    A
              JP    NZ,SOC002
              LD    HL,S1MR
              LD    A,1
              CALL  WWRITE
              LD    HL,S1PORT
              LD    DE,LOC001
              LD    B,2
              CALL  WBLOCK
              LD    HL,S1DIP
              LD    DE,CFG022
              LD    B,4
              CALL  WBLOCK
              LD    HL,S1D001
              LD    DE,CFG024
              LD    B,2
              CALL  WBLOCK
              ; Reassert TCP mode AFTER parameter writes, as in Phase 4B.
              LD    HL,S1MR
              LD    A,1
              CALL  WWRITE
              LD    HL,S1MR
              CALL  WREAD
              CP    1
              JP    NZ,DBG005
              ; Preserve the working direct OPEN and bounded CR/SR polls.
              LD    HL,S1CR
              LD    A,1
              CALL  WWRITE
              LD    BC,8000
DBG001        LD    HL,S1CR
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
DBG002        LD    BC,16000
DBG003        LD    HL,S1SR
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
DBG004        LD    DE,MSG043
              CALL  PRINT
              LD    HL,S1SR
              CALL  WREAD
              CALL  HEX
              CALL  NEW001
              OR    A
              RET
DBG005        LD    DE,MSG044
              CALL  PRINT
              SCF
              RET
SOC002        LD    DE,MSG042
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
              JP    NZ,CNTMO
              DEC   BC
              LD    A,B
              OR    C
              JP    Z,CNTMO
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
CNTMO
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
; Phase 4A.1: $FB with E=command (0 means STATUS), D=socket.
; Avoid passing command via B across BDOS/scheduler.
COM002       PUSH  BC
              PUSH  DE
              PUSH  HL
              LD    E,A
              LD    A,(SOCK_NO)
              LD    D,A
              LD    C,0FBH
              CALL  BDOS
              POP   HL
              POP   DE
              POP   BC
              OR    A
              RET   Z
              LD    DE,MSG065
              CALL  PRINT
              SCF
              RET

; FC receive batches up to 16 bytes; Telnet consumes the cached bytes
; one character at a time for IAC negotiation.
RX_ONE        LD    A,(RX_011)
              OR    A
              JR    Z,RX_FETCH
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
RX_FETCH      LD    A,(SOCK_NO)
              LD    (NXP001),A
              LD    A,1
              LD    (NXP001+1),A              ; RX operation
              LD    A,16
              LD    (NXP001+2),A
              LD    HL,RX_014
              LD    (NXP001+3),HL
              LD    DE,NXP001
              LD    C,0FCH
              CALL  BDOS
              CP    0FFH
              JR    Z,RX_EMPTY
              OR    A
              JR    Z,RX_EMPTY
              LD    (RX_011),A
              XOR   A
              LD    (RX_012),A
              JP    RX_POP
RX_EMPTY      SCF
              RET

; Phase 4B: send 1..16 bytes through kernel-managed W5100 TX ring.
; On insufficient free space, $FC returns zero (same error behaviour as before).
SEN001        LD    A,B
              OR    A
              RET   Z
              CP    17
              JR    NC,SEN_ERR
              LD    (NXP001+2),A
              LD    (NXP001+3),DE
              LD    A,(SOCK_NO)
              LD    (NXP001),A
              XOR   A
              LD    (NXP001+1),A
              LD    DE,NXP001
              LD    C,0FCH
              CALL  BDOS
              LD    B,A
              LD    A,(NXP001+2)
              CP    B
              RET   Z
SEN_ERR       LD    DE,MSG069
              CALL  PRINT
              SCF
              RET

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
              CALL  COM002               ; CLOSE selected socket only
              JP    EXIT

; --- Active diagnostics and state ----------------------------------------
MSG_PICK      DEFM  '[NET] selected socket = $'
MSG_NOS    DEFM  '[NET] no free CLOSED socket'
              DEFB  13,10,'$'
SOCK_NO       DEFB  1
SOCK_HI       DEFB  5
MSG001        DEFB  13,10
              DEFM  'Zapple-II TELNET v4C'
              DEFB  13,10,'$'
MSG002        DEFB  13,10
              DEFM  'Usage: TELNET a.b.c.d [port] [-v]'
              DEFB  13,10,'$'
MSG_HW        DEFM  '[03] attaching to kernel-configured W5100'
              DEFB  13,10,'$'
MSG017        DEFM  ' [W5100] mode readback = $'
MSG024        DEFM  ' [SAFE] indirect mode OFF, cannot access W5100'
              DEFB  13,10,'$'
MSG027        DEFM  ' [W5100] sockets 0/1/2/3 status = $'
MSG036        DEFM  'ERROR: W5100 not in indirect mode'
              DEFB  13,10,'$'
MSG041        DEFM  '[04] selected socket previous status = $'
MSG042        DEFM  ' [W5100] selected socket busy / TCP OPEN failed'
              DEFB  13,10,'$'
MSG043        DEFM  ' [W5100] after OPEN status = $'
MSG044        DEFM  ' [DBG] TCP mode readback failed, OPEN skipped'
              DEFB  13,10,'$'
MSG057        DEFM  ' [DBG] timeout: Sn_MR = $'
MSG058        DEFM  'ERROR: socket setup'
              DEFB  13,10,'$'
MSG059        DEFM  '[05] CONNECT / wait for ESTABLISHED'
              DEFB  13,10,'$'
MSG060        DEFM  ' [WAIT] socket status = $'
MSG_IR        DEFM  ' [W5100] socket IR = $'
MSG061        DEFM  ' [TIMEOUT] SYN not established (check host/port/gateway)'
              DEFB  13,10,'$'
MSG062        DEFM  ' [W5100] CLOSED before ESTABLISHED'
              DEFB  13,10,'$'
MSG063        DEFM  ' [cleanup] closing selected socket after failed CONNECT'
              DEFB  13,10,'$'
MSG064        DEFM  'ERROR: failed to connect'
              DEFB  13,10,'$'
MSG065        DEFM  ' [W5100] socket command never cleared'
              DEFB  13,10,'$'
MSG066        DEFM  '[POLL] socket status = $'
MSG067        DEFM  '[06] CONNECTED - Ctrl-] to exit'
              DEFB  13,10,'$'
MSG068        DEFB  13,10
              DEFM  '[TCP] socket disconnected'
              DEFB  13,10,'$'
MSG069        DEFM  '[TX] free buffer low, send aborted'
              DEFB  13,10,'$'
MSG070        DEFB  13,10
              DEFM  '[07] closing selected socket'
              DEFB  13,10,'$'
MSG071        DEFM  '[08] exit to CCP'
              DEFB  13,10,'$'
VER001        DEFB  0
QUI001        DEFB  0
ARG018        DEFB  0
ARG_IP        DEFS  4
ARG019        DEFS  2
ARG020        DEFW  0
ARG021        DEFW  0
ARG022        DEFS  121
LOC001        DEFB  0C0H,0DEH
CFG022        DEFB  0,0,0,0              ; remote IPv4
CFG024        DEFB  0,23                 ; remote port
POL001        DEFW  0
IP_003        DEFB  0
DIG001        DEFB  0
DIGIT         DEFB  0
HW_009        DEFB  0
RX_010        DEFB  0
RX_011        DEFB  0
RX_012        DEFB  0
RX_014        DEFS  16
NXP001        DEFS  5
SEN007        DEFB  0,0
TN_013        DEFB  0
TN_014        DEFB  0
TN_BUF        DEFB  0FFH,0,0
STACK         DEFS  256
STACKTOP
              END
