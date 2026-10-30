; Zapple-II NETSTAT.COM - read-only W5100 socket table
; Requires Zapple-II kernel Phase 6H.2 or later (FD E=5 query).
; Udo Munk's Z80ASM, ORG 0100H; strip FF 00 01 origin header.
;
; Private BDOS FD: E=5, D=socket(0..3), B=selector.
;   B=00..11h: W5100 Sn register byte; B=FEh: owner tab (FF=none);
;   B=FFh: resident NETCCP state (0=not service, 1=listen, 2=client).
; Read-only: does not allocate, close, negotiate, or modify any socket.

BDOS    EQU 0005H
        ORG 0100H
START   XOR A
        LD (SOCK),A
        LD B,0FFH              ; kernel capability probe: service state
        CALL QUERY
        CP 0FFH
        JR NZ,NSREADY
        LD DE,OLDKERN
        CALL PSTR
        RET
NSREADY LD DE,TITLE
        CALL PSTR
        LD DE,HEADER
        CALL PSTR
SNLOOP  CALL SHOW
        LD A,(SOCK)
        INC A
        LD (SOCK),A
        CP 4
        JR NZ,SNLOOP
        RET

; Show one socket; use memory for the loop index because BDOS may change BC.
SHOW    LD A,(SOCK)
        ADD A,'0'
        CALL PCHR
        LD DE,SP3
        CALL PSTR
        LD B,3                  ; Sn_SR
        CALL QUERY
        LD (SRBYTE),A
        CALL STATE
        LD A,' '
        CALL PCHR
        LD B,0FEH              ; owning tab
        CALL QUERY
        CP 0FFH
        JR NZ,OWNER
        LD DE,NOOWNER
        CALL PSTR
        JR OWNDONE
OWNER   CALL HEX8
OWNDONE LD DE,SP3
        CALL PSTR
        LD A,(SRBYTE)
        OR A
        JR NZ,LOCAL
        LD DE,NOPORT
        CALL PSTR
        JR LOCALEND
LOCAL   LD A,'$'
        CALL PCHR
        LD B,4                  ; Sn_PORT high
        CALL QUERY
        CALL HEX8
        LD B,5                  ; Sn_PORT low
        CALL QUERY
        CALL HEX8
LOCALEND
        LD DE,SP3
        CALL PSTR
        LD A,(SRBYTE)
        CP 017H                ; SOCK_ESTABLISHED
        JR Z,REMOTE
        CP 01CH                ; SOCK_CLOSE_WAIT
        JR Z,REMOTE
        LD DE,NOPEER
        CALL PSTR
        JR REMEND
REMOTE  LD B,0CH                ; Sn_DIPR0..3 (peer IPv4)
REMLP   CALL QUERY
        CALL DEC8
        LD A,B
        CP 0FH
        JR Z,REMLAST
        LD A,'.'
        CALL PCHR
REMLAST INC B
        LD A,B
        CP 10H
        JR NZ,REMLP
        LD A,':'
        CALL PCHR
        LD A,'$'
        CALL PCHR
        LD B,10H                ; Sn_DPORT high
        CALL QUERY
        CALL HEX8
        LD B,11H                ; Sn_DPORT low
        CALL QUERY
        CALL HEX8
REMEND  LD B,0FFH               ; service state
        CALL QUERY
        OR A
        JR Z,ROWEND
        CP 1
        JR NZ,SRVACT
        LD DE,SRVLST
        JR SRVPRINT
SRVACT  LD DE,SRVCON
SRVPRINT CALL PSTR
ROWEND  LD DE,CRLF
        JP PSTR

; B=register selector, D=current socket, E=5. Returns A and L.
; NOTE: Preserve B for loops over Sn_DIPR registers.
QUERY   PUSH BC
        LD A,(SOCK)
        LD D,A
        LD E,5
        LD C,0FDH
        CALL BDOS
        POP BC
        RET

STATE   LD A,(SRBYTE)
        OR A
        JR Z,STCLOSED
        CP 013H
        JR Z,STINIT
        CP 014H
        JR Z,STLISTEN
        CP 017H
        JR Z,STESTAB
        CP 01CH
        JR Z,STCWAIT
        CP 015H
        JR Z,STSYNRC
        CP 016H
        JR Z,STSYNST
        CP 018H
        JR Z,STFIN
        CP 01AH
        JR Z,STCLOS
        CP 01BH
        JR Z,STTIME
        CP 01DH
        JR Z,STLAST
        CP 022H
        JR Z,STUDP
        LD DE,STOTHER
        JP PSTR
STCLOSED
        LD DE,TXTCL
        JP PSTR
STINIT  LD DE,TXTIN
        JP PSTR
STLISTEN
        LD DE,TXTLS
        JP PSTR
STESTAB LD DE,TXTES
        JP PSTR
STCWAIT LD DE,TXTCW
        JP PSTR
STSYNRC LD DE,TXTSR
        JP PSTR
STSYNST LD DE,TXTSS
        JP PSTR
STFIN   LD DE,TXTFN
        JP PSTR
STCLOS  LD DE,TXTCS
        JP PSTR
STTIME  LD DE,TXTWT
        JP PSTR
STLAST  LD DE,TXTLA
        JP PSTR
STUDP   LD DE,TXTUD
        JP PSTR

; Display A as two hex digits, preserving BC (QUERY uses B for register).
HEX8    PUSH AF
        RRCA
        RRCA
        RRCA
        RRCA
        CALL HEXNIB
        POP AF
        AND 0FH
HEXNIB  AND 0FH
        ADD A,'0'
        CP 03AH
        JR C,HEXNUM
        ADD A,7
HEXNUM  JP PCHR

; Decimal unsigned byte A -> 1..3 printable digits, without leading zeros.
; Preserve B for register iteration and other callers.
DEC8    PUSH BC
        LD B,0
DEC100  CP 100
        JR C,D100DONE
        SUB 100
        INC B
        JR DEC100
D100DONE
        PUSH AF
        LD A,B
        LD (DECFLAG),A
        OR A
        JR Z,SKIP100
        ADD A,'0'
        CALL PCHR
SKIP100 POP AF
        LD B,0
DEC10   CP 10
        JR C,D10DONE
        SUB 10
        INC B
        JR DEC10
D10DONE PUSH AF
        LD A,B
        OR A
        JR NZ,PRINT10
        LD A,(DECFLAG)
        OR A
        JR Z,SKIP10
PRINT10 LD A,B
        ADD A,'0'
        CALL PCHR
SKIP10  POP AF
        ADD A,'0'
        CALL PCHR
        POP BC
        RET

PCHR    PUSH BC
        PUSH DE
        LD E,A
        LD C,2
        CALL BDOS
        POP DE
        POP BC
        RET
PSTR    LD C,9
        JP BDOS

SOCK    DEFB 0
SRBYTE  DEFB 0
DECFLAG DEFB 0
OLDKERN DEFM 'NETSTAT requires kernel Phase 6H.2 or later'
        DEFB 13,10,'$'
TITLE   DEFM 'Zapple-II NETSTAT  (ports in hex)'
        DEFB 13,10,'$'
HEADER  DEFM 'S   State        Tab  Local   Remote endpoint / service'
        DEFB 13,10,'$'
SP3     DEFM '   '
        DEFB '$'
CRLF    DEFB 13,10,'$'
NOOWNER DEFM '--'
        DEFB '$'
NOPORT  DEFM '-----'
        DEFB '$'
NOPEER  DEFM '-'
        DEFB '$'
SRVLST  DEFM '  [NETCCP listening]'
        DEFB '$'
SRVCON  DEFM '  [NETCCP connected]'
        DEFB '$'
TXTCL   DEFM 'CLOSED      '
        DEFB '$'
TXTIN   DEFM 'INIT        '
        DEFB '$'
TXTLS   DEFM 'LISTEN      '
        DEFB '$'
TXTES   DEFM 'ESTABLISHED '
        DEFB '$'
TXTCW   DEFM 'CLOSE_WAIT  '
        DEFB '$'
TXTSR   DEFM 'SYN_RECV    '
        DEFB '$'
TXTSS   DEFM 'SYN_SENT    '
        DEFB '$'
TXTFN   DEFM 'FIN_WAIT    '
        DEFB '$'
TXTCS   DEFM 'CLOSING     '
        DEFB '$'
TXTWT   DEFM 'TIME_WAIT   '
        DEFB '$'
TXTLA   DEFM 'LAST_ACK    '
        DEFB '$'
TXTUD   DEFM 'UDP         '
        DEFB '$'
STOTHER DEFM 'OTHER       '
        DEFB '$'
        END
