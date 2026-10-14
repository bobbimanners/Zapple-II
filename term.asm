; BP/M terminal personality selector (Z80 transient, ORG 0100H)
; Assemble with Udo Munk's z80asm; copy TERM.COM to the CP/M drive.
; Usage: TERM VIDEX   or   TERM SOROC  (TERM V / TERM S also work)
; Does not modify the resident Z80 BIOS/BDOS, nor move BDOSADDR.
;
; CCP puts the first argument in FCB1's name field at 005DH.
; Zero-page $07 is mirrored into the Z80 at F007H (6502 AREG).
; Calling a 6502 subroutine: set (F0EBH) to its address, CMD=1
; at F006H, then touch E400H to hand control to the SoftCard host.

            ORG     0100H
TERM        LD      A,(005DH)     ; First character of argument
            CP      'V'
            JR      Z,VIDEX
            CP      'S'
            JR      Z,SOROC
            LD      DE,USAGE
            LD      C,9
            CALL    0005H       ; BDOS print $-terminated message
            RET
VIDEX       XOR     A             ; 0 = Videx
            JR      SETMODE
SOROC       LD      A,1           ; 1 = Soroc IQ-120
SETMODE     LD      (0F007H),A   ; 6502 AREG
            LD      HL,0B80CH    ; Added 6502 VSETMODE public vector
            LD      (0F0EBH),HL  ; 6502 ADDR
            LD      A,1
            LD      (0F006H),A   ; 6502 CMD=1
            LD      (0E400H),A   ; Yield SoftCard to the 6502
            RET                  ; Back to CCP with unchanged TPA
USAGE       DEFB    13
            DEFM    'TERM VIDEX or TERM SOROC'
            DEFB    13,'$'
