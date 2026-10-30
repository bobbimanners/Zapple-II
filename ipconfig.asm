; Zapple-II IPCONFIG.COM 6K - W5100 live interface configuration.
; Syntax: IPCONFIG [IP|MASK|GW|ROUTER|DNS a.b.c.d]
; No permanent config storage: re-run commands after cold boot.
; IP/GW/MASK: live W5100 common registers. DNS: shared kernel RAM.
; WARNING: changing hardware IPv4 with established sockets may break them.
; Native W5100 read via Uthernet-II slot 5, F9 MAIN-gateway write.
; Private FD E=6,D=index reads current kernel DNS; FD E=7 sets B=value.
BDOS    EQU 0005H
        ORG 0100H
START   LD SP,STKTOP
        CALL SETPORT
        CALL ARGS
        JP C,USGERR
        LD A,(MODE)
        OR A
        JP Z,SHOW
        CALL SETVAL
        JP C,SETERR
        LD DE,OKMSG
        CALL PRINT
        JP SHOW
USGERR  LD DE,USAGE
        CALL PRINT
        LD C,0                 ; START installed a private stack
        JP BDOS                ; don't RET to an unknown address
SETERR  LD DE,ERRMSG
        CALL PRINT
        LD C,0
        JP BDOS
; Build NUL-terminated uppercase CP/M command tail, max 127 chars.
ARGS    LD A,(0080H)
        CP 127
        JP NC,ARGERR
        LD B,A
        LD HL,0081H
        LD DE,TAIL
ACOPY   LD A,B
        OR A
        JR Z,ACPDON
        LD A,(HL)
        CP 'a'
        JR C,ACOPY1
        CP 'z'+1
        JR NC,ACOPY1
        SUB 32
ACOPY1  LD (DE),A
        INC HL
        INC DE
        DJNZ ACOPY
ACPDON  XOR A
        LD (DE),A
        LD HL,TAIL
        CALL SKIPSP
        LD A,(HL)
        OR A
        RET Z
        LD DE,IPNAME
        LD A,1
        CALL MATKEY
        JR NC,ARGVAL
        LD DE,MASKNAM
        LD A,2
        CALL MATKEY
        JR NC,ARGVAL
        LD DE,GWNAME
        LD A,3
        CALL MATKEY
        JR NC,ARGVAL
        LD DE,ROUTNAM
        LD A,3
        CALL MATKEY
        JR NC,ARGVAL
        LD DE,GATENAM
        LD A,3
        CALL MATKEY
        JR NC,ARGVAL
        LD DE,DNSNAME
        LD A,4
        CALL MATKEY
        JR C,ARGERR
ARGVAL  CALL SKIPSP
        LD A,(HL)              ; missing value?
        OR A
        JR NZ,AVPARSE
        LD A,(MODE)
        CP 4                   ; IPCONFIG DNS with no address is a query
        JR NZ,ARGERR          ; other missing setters print usage
        XOR A
        LD (MODE),A            ; display current configuration
        RET
AVPARSE LD DE,IPV4
        LD B,4
AVLOOP  PUSH BC
        PUSH DE
        CALL OCTET
        POP DE
        POP BC
        JR C,ARGERR
        LD (DE),A
        INC DE
        DEC B
        JR Z,AVLAST
        LD A,(HL)
        CP '.'
        JR NZ,ARGERR
        INC HL
        JR AVLOOP
AVLAST  CALL SKIPSP
        LD A,(HL)
        OR A
        JR NZ,ARGERR
        OR A
        RET
ARGERR  SCF
        RET
; A=mode, HL points at command, DE NUL-terminated keyword.
; On match update MODE and skip keyword; carry clear.
MATKEY  PUSH AF
        PUSH HL
MKLOOP  LD A,(DE)
        OR A
        JR Z,MKEND
        CP (HL)
        JR NZ,MKBAD
        INC DE
        INC HL
        JR MKLOOP
MKEND   LD A,(HL)
        CP ' '
        JR Z,MKOK
        CP 9
        JR NZ,MKBAD
MKOK    POP DE
        POP AF
        LD (MODE),A
        OR A
        RET
MKBAD   POP HL
        POP AF
        SCF
        RET
SKIPSP  LD A,(HL)
        CP ' '
        JR Z,SKIP1
        CP 9
        RET NZ
SKIP1   INC HL
        JR SKIPSP
; Strict octet 0..255, 1-3 digits, no overflow.
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
; Return A=0 success / carry failure. Mode 1 IP,2 mask,3 GW,4 DNS.
SETVAL  LD A,(MODE)
        CP 4
        JR Z,SETDNS
        LD HL,000FH
        CP 1
        JR Z,SETHW
        LD HL,0005H
        CP 2
        JR Z,SETHW
        LD HL,0001H
SETHW   LD DE,IPV4
        LD B,4
SWHLOOP LD A,(DE)
        PUSH BC
        PUSH DE
        CALL WWRITE
        POP DE
        POP BC
        INC HL
        INC DE
        DJNZ SWHLOOP
        OR A
        RET
SETDNS  LD HL,IPV4
        LD D,0
SDLOOP  LD B,(HL)
        LD E,7
        LD C,0FDH
        PUSH HL
        PUSH DE
        CALL BDOS
        POP DE
        POP HL
        CP 0FFH
        JR Z,SDFAIL
        INC HL
        INC D
        LD A,D
        CP 4
        JR NZ,SDLOOP
        OR A
        RET
SDFAIL  SCF
        RET
SHOW    LD DE,TITLE
        CALL PRINT
        LD DE,IPTEXT
        CALL PRINT
        LD HL,000FH
        CALL WIP
        LD DE,MASKTXT
        CALL PRINT
        LD HL,0005H
        CALL WIP
        LD DE,GWTEXT
        CALL PRINT
        LD HL,0001H
        CALL WIP
        LD DE,DNSTEXT
        CALL PRINT
        LD D,0
DNSDIS  LD E,6
        LD C,0FDH
        PUSH DE
        CALL BDOS
        POP DE
        CALL DEC8
        INC D
        LD A,D
        CP 4
        JR Z,DNSEOL
        LD A,'.'
        CALL PUTC
        JR DNSDIS
DNSEOL  LD DE,CRLF
        CALL PRINT
        LD C,0                ; CP/M terminate; START jumped to SHOW
        JP BDOS               ; never RET on the private stack
WIP     LD B,4
WIPLOOP CALL WREAD
        CALL DEC8
        INC HL
        DEC B
        JR Z,WIPEOL
        LD A,'.'
        CALL PUTC
        JR WIPLOOP
WIPEOL  LD DE,CRLF
        CALL PRINT
        RET
; Print unsigned A 0..255, preserving B, DE, HL.
DEC8    PUSH BC
        LD C,A
        LD B,0
        LD A,C
D100    CP 100
        JR C,D100E
        SUB 100
        INC B
        JR D100
D100E   LD C,A
        LD A,B
        LD (DECHUND),A
        OR A
        JR Z,D10SET
        ADD A,'0'
        CALL PUTC
D10SET  LD B,0
        LD A,C
D10     CP 10
        JR C,D10E
        SUB 10
        INC B
        JR D10
D10E    LD C,A
        LD A,B
        OR A
        JR NZ,D10PR
        ; print a zero tens digit if hundreds already printed
        ; We use the original byte saved on stack only via DECOLD.
        LD A,(DECHUND)
        OR A
        JR Z,DONE1
        XOR A
D10PR   ADD A,'0'
        CALL PUTC
DONE1   LD A,C
        ADD A,'0'
        CALL PUTC
        POP BC
        RET
; Print helpers, no console mode special cases.
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
; Uthernet-II slot 5 native direct access reads; F9 for writes.
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
IPNAME  DEFM 'IP'
        DEFB 0
MASKNAM DEFM 'MASK'
        DEFB 0
GWNAME  DEFM 'GW'
        DEFB 0
ROUTNAM DEFM 'ROUTER'
        DEFB 0
GATENAM DEFM 'GATEWAY'
        DEFB 0
DNSNAME DEFM 'DNS'
        DEFB 0
TITLE   DEFM 'Zapple-II IPCONFIG 6K (live W5100)'
        DEFB 13,10,'$'
IPTEXT  DEFM 'IP     : $'
MASKTXT DEFM 'Mask   : $'
GWTEXT  DEFM 'Gateway: $'
DNSTEXT DEFM 'DNS    : $'
OKMSG   DEFM 'Updated (not saved across cold boot)'
        DEFB 13,10,'$'
ERRMSG  DEFM 'Cannot update setting (old kernel?)'
        DEFB 13,10,'$'
USAGE   DEFM 'Usage: IPCONFIG [IP|MASK|GW|ROUTER|GATEWAY|DNS a.b.c.d]'
        DEFB 13,10,'$'
CRLF    DEFB 13,10,'$'
MODE    DEFB 0
IPV4    DEFS 4
WADDR   DEFB 0,0
WVAL    DEFB 0
DECHUND DEFB 0
TAIL    DEFS 128
STACK   DEFS 192
STKTOP
        END
