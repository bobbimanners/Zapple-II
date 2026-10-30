; Zapple-II Phase 6J: start independent resident NETCCP service.
; NETCCP [port]  (default 2323, decimal 1..65535).
; Launch once in each dedicated tab; up to four available W5100 sockets.
; The MAIN service survives disconnect; TAB n KILL stops that tab's service.
; Private BDOS FD: E=4, D=port high byte, B=port low byte.
; Assemble Udo Munk z80asm ORG 0100H; strip FF 00 01 header.
BDOS       EQU       0005H
           ORG       0100H
START      LD        DE,HELLO
           LD        C,9
           CALL      BDOS
           CALL      GETPORT
           JR        C,BADARG
           LD        D,H
           LD        B,L
           LD        E,4
           LD        C,0FDH
           CALL      BDOS
           OR        A
           JR        NZ,FAILED
           LD        DE,READY
           LD        C,9
           CALL      BDOS
           LD        C,7                            ; get this tab's IOBYTE
           CALL      BDOS
           AND       0FCH
           OR        3                            ; CON:=UC1:
           LD        E,A
           LD        C,8
           CALL      BDOS
           LD        C,0                            ; terminate to ordinary CCP
           JP        BDOS
BADARG     LD        DE,USAGE
           LD        C,9
           CALL      BDOS
           RET
FAILED     LD        DE,ERROR
           LD        C,9
           CALL      BDOS
           RET
; Read CP/M command tail. Ignore leading/trailing spaces, decimal only.
; On success HL=port and carry clear; invalid/overflow/0 sets carry.
GETPORT    LD        A,(0080H)
           LD        C,A
           LD        IX,0081H
GPSKIP     LD        A,C
           OR        A
           JR        Z,GPDEF
           LD        A,(IX+0)
           CP        ' '
           JR        NZ,GPBEGIN
           INC       IX
           DEC       C
           JR        GPSKIP
GPDEF      LD        HL,0913H                      ; 2323 default
           OR        A                            ; clear carry
           RET
GPBEGIN    LD        HL,0
GPDIG      LD        A,C
           OR        A
           JR        Z,GPEND
           LD        A,(IX+0)
           CP        ' '
           JR        Z,GPTRAIL
           CP        '0'
           JR        C,GPERR
           CP        03AH                         ; above '9'
           JR        NC,GPERR
           SUB       '0'
           LD        (GPDIGIT),A
           LD        D,H
           LD        E,L
           ADD       HL,HL                        ; x2
           JR        C,GPERR
           ADD       HL,HL                        ; x4
           JR        C,GPERR
           ADD       HL,DE                        ; x5
           JR        C,GPERR
           ADD       HL,HL                        ; x10
           JR        C,GPERR
           LD        A,(GPDIGIT)
           LD        E,A
           LD        D,0
           ADD       HL,DE                        ; + digit
           JR        C,GPERR
           INC       IX
           DEC       C
           JR        GPDIG
GPTRAIL    INC       IX
           DEC       C
GPTAIL     LD        A,C
           OR        A
           JR        Z,GPEND
           LD        A,(IX+0)
           CP        ' '
           JR        NZ,GPERR
           INC       IX
           DEC       C
           JR        GPTAIL
GPEND      LD        A,H
           OR        L
           JR        Z,GPERR
           OR        A
           RET
GPERR      SCF
           RET
GPDIGIT    DEFB      0
HELLO      DEFM      'Zapple-II NETCCP 6J - resident Telnet'
           DEFB      13,10,'$'
READY      DEFM      'Listener enabled for this tab'
           DEFB      13,10,'$'
ERROR      DEFM      'Cannot start (socket, tab, or port already in use)'
           DEFB      13,10,'$'
USAGE      DEFM      'Usage: NETCCP [TCP port 1..65535]'
           DEFB      13,10,'$'
           END
