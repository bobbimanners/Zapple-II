; Zapple-II NETCCP.COM - Phase 6C initial persistent remote CCP
; Phase 6F: Telnet auto character-mode negotiation, single connection.
; Run in a SEPARATE CP/M tab, e.g. TAB 1 then NETCCP, to retain local CCP.
; Kernel Phase 6C required: FD E=3 arms persistent UC1 binding.
; Port 2323 (0913h). Requires existing kernel-configured W5100.
; Udo Munk Z80ASM, 8-significant-character symbols.
BDOS    EQU 0005H
        ORG 0100H
START   LD SP,STKTOP
        LD A,0FFH
        LD (SOCK),A
        LD DE,HELLO
        CALL PSTR
        LD C,0FAH                ; FA E=0: allocate socket
        LD E,0
        CALL BDOS
        CP 4
        JP NC,FAILED
        LD (SOCK),A
        LD DE,SOCKMSG
        CALL PSTR
        LD A,(SOCK)
        CALL HEXOUT
        CALL NL
        LD B,0                   ; Sn_MR = TCP
        LD A,1
        CALL WSET
        LD B,4                   ; Sn_PORT high: 2323 decimal
        LD A,09H
        CALL WSET
        LD B,5                   ; Sn_PORT low
        LD A,013H
        CALL WSET
        LD E,1                   ; OPEN
        CALL COMMAND
        CP 0FFH
        JP Z,FAILED
        CALL STATUS
        CP 013H                  ; SOCK_INIT
        JP NZ,FAILED
        LD E,2                   ; LISTEN
        CALL COMMAND
        CP 0FFH
        JP Z,FAILED
        LD DE,LISTMSG
        CALL PSTR
WAITCON CALL STATUS
        CP 017H                  ; SOCK_ESTABLISHED
        JP Z,ACCEPT
        CP 014H                  ; SOCK_LISTEN
        JP NZ,FAILED
        LD C,11                  ; local CTRL-C cancels listener
        CALL BDOS
        OR A
        JP Z,WAITCON
        LD C,1
        CALL BDOS
        CP 3
        JP Z,EXIT
        JP WAITCON
ACCEPT  LD DE,CONNMSG
        CALL PSTR
        CALL TNINIT              ; Telnet ECHO/SGA; refuse client LINEMODE
        CP 12                    ; 12-byte handshake must be transmitted
        JP NZ,FAILED
        LD A,(SOCK)
        LD D,A
        LD E,1                   ; FD E=1 bind to this tab's UC1
        LD C,0FDH
        CALL BDOS
        OR A
        JP NZ,FAILED
        LD E,3                   ; FD E=3 persist across child->CCP
        LD C,0FDH
        CALL BDOS
        OR A
        JP NZ,FAILED
        LD C,7                   ; read current IOBYTE
        CALL BDOS
        AND 0FCH
        OR 3                      ; CON:=UC1:, preserve other fields
        LD E,A
        LD C,8                   ; set IOBYTE in current AUX session
        CALL BDOS
        LD DE,WELCOME            ; now output via network UC1
        CALL PSTR
        LD C,0                   ; terminate child; supervisor reloads CCP
        CALL BDOS               ; Phase6C NETCLN preserves bound socket
        RET                     ; should never return
FAILED  LD DE,ERROR
        CALL PSTR
EXIT    LD C,7                   ; ensure physical console on error exit
        CALL BDOS
        AND 0FCH
        OR 1
        LD E,A
        LD C,8
        CALL BDOS
        LD E,0                   ; FD E=0 unbind
        LD C,0FDH
        CALL BDOS
        LD A,(SOCK)
        CP 4
        JP NC,DONE
        LD D,A
        LD E,1                   ; FA E=1 free socket
        LD C,0FAH
        CALL BDOS
DONE    RET
; B=socket register offset, A=value. $F9 AUX-to-MAIN write bridge.
WSET    LD (WPAR+2),A
        LD A,(SOCK)
        ADD A,4
        LD (WPAR),A
        LD A,B
        LD (WPAR+1),A
        LD DE,WPAR
        LD C,0F9H
        CALL BDOS
        RET
COMMAND LD A,(SOCK)
        LD D,A
        LD C,0FBH
        CALL BDOS
        RET
STATUS  LD E,0
        CALL COMMAND
        RET
PSTR    LD C,9
        CALL BDOS
        RET
NL      LD DE,NEWLINE
        JP PSTR
HEXOUT  PUSH AF
        RRCA
        RRCA
        RRCA
        RRCA
        CALL HEXDIG
        POP AF
HEXDIG  AND 0FH
        ADD A,'0'
        CP '9'+1
        JP C,HEXP
        ADD A,7
HEXP    LD E,A
        LD C,2
        CALL BDOS
        RET
HELLO   DEFM 'Zapple-II NETCCP 6F - Telnet console',13,10,'$'
SOCKMSG DEFM 'Socket $'
LISTMSG DEFM 'Listening on 2323 (Ctrl-C to cancel)...',13,10,'$'
CONNMSG DEFM 'Connected: switching this tab to remote CCP',13,10,'$'
WELCOME DEFM '',13,10,'Zapple-II CP/M remote console',13,10,'$'
ERROR   DEFM 'Network/socket error',13,10,'$'
NEWLINE DEFB 13,10,'$'
SOCK    DEFB 0FFH
WPAR    DEFB 0,0,0
STACK   DEFS 512
STKTOP

; Telnet negotiation is sent before binding CON:=UC1:. The resident 6F
; TNFEED filter handles replies (incl. rejecting unsupported LINEMODE).
; DO NOT put this in the network console path: BDOS $FC operates on AUX.
TNINIT  LD A,(SOCK)
        LD (TNPAR),A
        LD B,32                  ; bounded retries; never hang on disconnect
TNSEND  PUSH BC
        LD DE,TNPAR
        LD C,0FCH                ; kernel TCP send, max 16 bytes
        CALL BDOS
        POP BC
        OR A
        RET NZ                   ; 12 = OK, FF = error
        DJNZ TNSEND              ; W5100 TX temporarily full: retry
        XOR A
        RET                      ; 0 = timed out (ACCEPT treats as error)
TNPAR   DEFB 0,0,12             ; socket, TX, count
        DEFW TNSEQ
TNSEQ   DEFB 0FFH,0FBH,1        ; IAC WILL ECHO: server echoes input
        DEFB 0FFH,0FBH,3        ; IAC WILL SGA: interactive full-duplex
        DEFB 0FFH,0FDH,3        ; IAC DO SGA: client suppresses GA
        DEFB 0FFH,0FEH,22H      ; IAC DONT LINEMODE (34)
        END
