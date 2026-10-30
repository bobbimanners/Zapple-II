; Zapple-II NETCCP.COM Phase 6H: enable MAIN-resident Telnet service.
; The listener is owned by the kernel. This executable is never restarted.
; Launch in a dedicated tab; TAB <n> KILL disables the service.
; Assemble with Udo Munk z80asm; strip three-byte origin header as usual.
BDOS    EQU 0005H
        ORG 0100H
START   LD DE,HELLO
        LD C,9
        CALL BDOS
        LD E,4                   ; private $FD: start resident TCP listener
        LD C,0FDH
        CALL BDOS
        OR A
        JR NZ,FAILED
        LD DE,READY
        LD C,9
        CALL BDOS
        LD C,7                   ; IOBYTE current tab
        CALL BDOS
        AND 0FCH
        OR 3                     ; CON:=UC1:
        LD E,A
        LD C,8
        CALL BDOS
        LD C,0                   ; terminate child -> ordinary CCP
        JP BDOS
FAILED  LD DE,ERROR
        LD C,9
        CALL BDOS
        RET
HELLO   DEFM 'Zapple-II NETCCP 6H - resident Telnet service'
        DEFB 13,10,'$'
READY   DEFM 'Listening on 2323 (kernel-managed)'
        DEFB 13,10,'$'
ERROR   DEFM 'Cannot enable listener (socket busy or service active)'
        DEFB 13,10,'$'
        END
