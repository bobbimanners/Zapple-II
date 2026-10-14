;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Z80 code running on Softcard
; Implements CP/M style BDOS interface
; Requires the companion SOFTCARD65 6502 code
; Assemble using Udo Munk's Z80asm.
; Tabstops every 4 chars.
; Bobbi 2019, 2026
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; References:
; 1) BDOS System Calls
;    https://www.seasip.info/Cpm/bdos.html
; 2) Programmer's CP/M Handbook - Johnson-Laird
; 3) ProDOS 8 Technical Reference Manual
;    http://www.easy68k.com/paulrsm/6502/PDOS8TRM.HTM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; TODO: Exploit aux memory to gain a larger TPA (48K instead of 32K)
; TODO: Prodos file handling is SLOW. Would be good to cache file handles rather than
;       closing/reopening every time.
; TODO: Sector-level BIOS calls.
; TODO: Implement missing BDOS system calls:
;        - F_ATTRIB (needs to support wildcards, leave FCB at DMAADDR)
;        - RS232 (A_READ, A_WRITE)
;        - Printer (LWRITE)
; TODO: IOBYTE doesn't do anything
; TODO: User number doesn't do anything
; TODO: Software R/O disk setting is not respected

BDOSADDR	EQU		08100H			; 
STCKTOP		EQU		0A800H			; Dedicated 1K stack $A400-$A7FF

SOFTCARD	EQU		0E400H			; Softcard in slot 4 ($C400)


OFFSET		EQU		01000H			; Offset to add to Z80 addr to get 6502
									; address. Correct for Z80 addr <= 0AFFFH

; 6502 zero page, in Z80 address space
CMD			EQU		0F006H			; 6502 $06
AREG		EQU		0F007H			; 6502 $07
XREG		EQU		0F008H			; 6502 $08
YREG		EQU		0F009H			; 6502 $09
ADDR		EQU		0F0EBH			; 6502 $EB (LSB)
ADDRH		EQU		0F0ECH			; 6502 $EC (MSB)

; Addresses of 6502 routines, in 6502 address space
COUT		EQU		0B803H			; Direct video output entry (B803)
RDKEY		EQU		0B806H			; Direct keyboard/cursor entry (B806)
BELL		EQU		0B809H			; Direct speaker click entry (B809)
RAWOUT		EQU		0B80FH			; Raw BIOS console entry (B80F)
; TERM.COM (separate transient utility) calls 6502 B80C to switch terminal.
; Only a 6-byte raw-output shim is added to the resident BDOS.

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Entry point when Z80 cold starts is 0000H
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

			ORG		0000H
			JP		BDOSINIT		; Initialize BDOS

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; See obsolescence.wix.com/obsolescence/cpm-internals for info
; on low storage usage ...
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

IOBYTE		DEFB	0				; Maps virtual to real devices

CURDRV		DEFB	0				; LS 4 bits; Current drive 0=A: etc
									; MS 4 bits: Current user number

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; BDOS entry point must be at address 0005H for CP/M compatibility
; Function to invoke is passed in C
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

BDOS		JP		BDOSENTRY		; Keep page-zero BDOS vector within $81xx

RVEC1		DEFW	0000H			; Restart vector 1
RVEC2		DEFW	0000H			; Restart vector 2
RVEC3		DEFW	0000H			; Restart vector 3
RVEC4		DEFW	0000H			; Restart vector 4
RVEC5		DEFW	0000H			; Restart vector 5
RVEC6		DEFW	0000H			; Restart vector 6
RVEC7		DEFW	0000H			; Restart vector 7

; Space for private BDOS data (implementation dependent) up to 005BH
DMAADDR		DEFW	0080H			; DMA address defaults to FILEBUF (0080H)
LOGVEC		DEFW	0000H			; Vector of logged in drives
ROVEC		DEFW	0000H			; Vector of read-only drives
TEMPWORD	DEFW	0000H			; Used by routines as a scratch space
TEMPBYTE	DEFB	0				; Used by routines as a scratch space
; End of private, implementation dependent space

			ORG		005CH			; Standard addr of 32 byte FCB1
FCB1								; File control block #1
FCB1DRV		DEFB	00H				; FCB Drive (0 current, 1 A:, 2 B: etc)
FCB1NAM		DEFM	'FILENAMEEXT'	; FCB filename and extension
FCB1EX		DEFB	00H				; FCB extent field
FCB1S1		DEFB	00H				; FCB S1 field
FCB1S2		DEFB	00H				; FCB S2 field
FCB1RC		DEFB	00H				; FCB RC field (# recs used this extent)
FCB1MAP								; Map of blocks in file (overlaps FCB2)

			ORG		006CH			; Standard addr of 32 byte FCB2
FCB2								; File control block #2
FCB2DRV		DEFB	00H				; FCB Drive (0 current, 1 A:, 2 B: etc)
FCB2NAM		DEFM	'FILENAMEEXT'	; FCB filename and extension
FCB2EX		DEFB	00H				; FCB extent field
FCB2S1		DEFB	00H				; FCB S1 field
FCB2S2		DEFB	00H				; FCB S2 field
FCB2RC		DEFB	00H				; FCB RC field (# recs used this extent)
FCB2MAP								; Map of blocks in file (overlaps buffer)

			ORG		0080H			; Standard addr of 128 byte File Buffer
FILEBUF		DEFS	128				; Command args go here too (Pascal string)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; The application program proper starts at 0100H
; in order to be compatible with CP/M .COM programs
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

			ORG		0100H

PROGSTRT	CALL	CCP				; Run the CCP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Implementation of CP/M STYLE BDOS
; Function to invoke is passed in C, as follows:
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
B_C_TERMCPM		EQU		00H			; System reset
B_C_READ		EQU		01H			; Console read
B_C_WRITE		EQU		02H			; Console write
B_C_RAWIO		EQU		06H			; Direct console I/O
B_GET_IOB		EQU		07H			; Get IOBYTE
B_SET_IOB		EQU		08H			; Set IOBYTE
B_C_WRTSTR		EQU		09H			; Console write string
B_C_RDSTR		EQU		0AH			; Read console string
B_C_STAT		EQU		0BH			; Console status
B_S_BDOSVER		EQU		0CH			; Return version number
B_DRV_ALLRST	EQU		0DH			; Reset disks
B_DRV_SET		EQU		0EH			; Select disk
B_F_OPEN		EQU		0FH			; Open file
B_F_CLOSE		EQU		10H			; Close file
B_F_SFIRST		EQU		11H			; Search for first match in directory
B_F_SNEXT		EQU		12H			; Search for next match in directory
B_F_DELETE		EQU		13H			; Delete file
B_F_READ		EQU		14H			; Read file sequentially
B_F_WRITE 		EQU		15H			; Write file sequentially
B_F_MAKE		EQU		16H			; Create and open file
B_F_RENAME		EQU		17H			; Rename file 
B_DRV_LOGVEC	EQU		18H			; Return bitmap of logged-in drives
B_DRV_GET		EQU		19H			; Return current drive
B_F_DMAOFF		EQU		1AH			; Set DMA address
B_DRV_AVEC		EQU		1BH			; Return address of allocation map
B_DRV_SRO		EQU		1CH			; Software write-protect current drive
B_DRV_ROVEC		EQU		1DH			; Return bitmap of read-only drives
B_DRV_DPB		EQU		1FH			; Get Drive Parameter Block address
B_F_USERNUM		EQU		20H			; Get/set user number
B_F_RDRAND		EQU		21H			; Random access read record
B_F_WRTRAND		EQU		22H			; Random access write record
B_F_SIZE		EQU		23H			; Compute file size
B_F_RANDREC		EQU		24H			; Update random access pointer
B_DRV_RESET		EQU		25H			; Selectively reset disk drives
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

			ORG		BDOSADDR

; CP/M 2.2 BIOS jump table (17 entries, three bytes each).
; Applications discover the BIOS WBOOT entry from the 16-bit operand
; at 0001H. The following three JP instructions must be CONST, CONIN,
; CONOUT in that order; TE_APPLE.COM copies exactly those nine bytes.
; Keep this table contiguous. The disk-sector entries are safe stubs,
; NOT a ProDOS block/sector BIOS (BP/M files continue through BDOS).
BIOS		JP		BDOSINIT		; BOOT    +00H
BIOSWBOOT	JP		BDOSWARM		; WBOOT   +03H
BIOSCSTAT	JP		BIOSCONST		; CONST   +06H
BIOSCKBD	JP		BIOSCONIN		; CONIN   +09H
BIOSCTTY	JP		BIOSCONOUT		; CONOUT  +0CH
			JP		BIOSLIST		; LIST    +0FH
			JP		BIOSPUNCH		; PUNCH   +12H
			JP		BIOSRDR			; READER  +15H
			JP		BIOSHOME		; HOME    +18H
			JP		BIOSSELDSK		; SELDSK  +1BH
			JP		BIOSSETTRK		; SETTRK  +1EH
			JP		BIOSSETSEC		; SETSEC  +21H
			JP		BIOSSETDMA		; SETDMA  +24H
			JP		BIOSREAD		; READ    +27H
			JP		BIOSWRITE		; WRITE   +2AH
			JP		BIOSLSTST		; LISTST  +2DH
			JP		BIOSSECTRAN	; SECTRAN +30H

; Public BDOS entry must be in the FIRST page of resident memory.
; MESCC-based .COM programs (including TE_APPLE.COM) calculate their
; stack top by rounding down the address at CP/M $0006 to a page
; boundary. An address in $82xx would place SP at $8200 INSIDE BP/M!
; 17 BIOS JP vectors = 51 bytes, so this is $8100 + $33 = $8133.
BDOSENTRY	JP		BDOSIMP

; Fixed exit/resume point at $8136, immediately after the $8133 BDOS JP.
; The Z80 is *suspended*, not reset, when CMD=0 switches to the 6502.
; On a later ProDOS launch the new image resumes at the instruction after
; LD (SOFTCARD),A. Jump via the freshly reloaded cold vector at $0000.
; Keep this stub at $8136 in future releases (BIOS ABI + 3-byte BDOS JP).
BYERESUME	LD		(SOFTCARD),A	; CCPBYE already set CMD=0 and A=0
			JP		0000H			; Execute only after ProDOS relaunch

; CP/M BIOS console: unlike the cooked BDOS C_READ, CONIN does not
; echo or treat Ctrl-C specially. CONOUT takes its byte in C, and
; must not suppress LF at the Z80 layer (C_WRITE deliberately does).
; Neither routine touches the alternate Z80 register set.
BIOSCONST	LD		A,3			; 6502 keyboard peek
			LD		(CMD),A
			LD		(SOFTCARD),A
			LD		A,(AREG)
			OR		A
			RET		Z
			LD		A,0FFH		; CP/M CONST: FF=ready, 00=not
			RET

BIOSCONIN	PUSH	HL
			LD		HL,RDKEY		; VGET waits but doesn't echo
			LD		(ADDR),HL
			LD		A,1
			LD		(CMD),A
			LD		(SOFTCARD),A
			LD		A,(AREG)
			AND		7FH			; 6502 keyboard sets bit 7
			POP		HL
			RET

BIOSCONOUT	PUSH	DE			; C contains character
			PUSH	HL
			LD		E,C
			CALL	C_RAWPUT	; Uncooked output to VRAWPUT
			POP		HL
			POP		DE
			RET

; No auxiliary I/O devices yet. READER must return CP/M EOF (^Z).
BIOSLIST	RET				; no printer attached
BIOSPUNCH	RET				; no punch attached
BIOSRDR		LD		A,1AH
			RET
BIOSLSTST	XOR		A			; printer not ready
			RET

; Sector BIOS is deliberately unimplemented: don't tell applications
; that reads or writes succeeded when no data was transferred.
; BDOS's existing ProDOS file-based interface remains unchanged.
BIOSHOME	RET
BIOSSELDSK	LD		HL,0000H	; no sector-level DPH available
			RET
BIOSSETTRK	RET
BIOSSETSEC	RET
BIOSSETDMA	LD		(DMAADDR),BC
			RET
BIOSREAD	LD		A,1			; error, not success
			RET
BIOSWRITE	LD		A,1			; error, not success
			RET
BIOSSECTRAN	LD		H,B			; identity mapping
			LD		L,C
			RET

; Entry at 0000H is a COLD start only until the first initialization.
; Repoint its JP operand to the real BIOS WBOOT jump (BIOS+3),
; so CP/M applications can discover CONST/CONIN/CONOUT via (0001H).
; Subsequent RST 0 / JP 0000H runs an ordinary warm boot.
BDOSINIT	DI
			LD		SP,STCKTOP		; Valid stack for BPMSIGN
			LD		HL,BIOSWBOOT
			LD		(0001H),HL		; 0000H -> BIOS WBOOT JP (CP/M ABI)
			CALL	BPMSIGN			; Print TPA banner exactly once

; Warm-boot path for BDOS 0, RST 0, JP 0000H and Ctrl-C.
; Keep the existing BDOS reset semantics, but do not print BPMSIGN.
BDOSWARM	DI					; Make sure interrupts are off
			LD		SP,STCKTOP		; Discard transient's stack

			; Applications such as Apple CP/M MBASIC 5.2 replace the
			; warm-start address at $0001 with an address in the TPA.
			; CP/M WBOOT must restore the page-zero system jump vectors.
			; $0000: JP BIOSWBOOT, $0005: JP BDOSENTRY.
			LD		A,0C3H			; Opcode for JP absolute
			LD		(0000H),A
			LD		(0005H),A
			LD		HL,BIOSWBOOT
			LD		(0001H),HL
			LD		HL,BDOSENTRY
			LD		(0006H),HL

			XOR		A				; A=0
			LD		(IOBYTE),A		; Initialize IOBYTE
			LD		(CURDRV),A		; Drive A:, User 0
			LD		(FILEBUF),A		; Zero chars in command tail
			XOR		A				; A=0 means close all files
			LD		(FCMLIN),A		; Store in parameter list
			LD		HL,FCMLI		; Pass address of 6502 JSR instruction
			CALL	PRODOS			; Invoke ProDOS MLI to close all files
			LD		(FRN1),A		; Initialize FRNs to zero
			LD		(FRN2),A		; ...
			LD		(FRN3),A		; ...
			LD		(FRN4),A		; Reserved unused slot (legacy)
			LD		HL,FILEBUF		; Initialize DMAADDR to 0080H
			LD		(DMAADDR),HL	; ...
			LD		HL,0000H		; Initialize LOGVEC & ROVEC to 0000H
			LD		(LOGVEC),HL		; ...
			LD		(ROVEC),HL		; ...
			JP		CCP				; Start the CCP

; The TPA is 0100H..BDOSADDR-1. Derive KiB from BDOSADDR at
; assembly time, then turn it into decimal at run time. 10 right shifts
; convert a byte count to KiB; valid for any sensible BDOS placement.
; We print two digits (CP/M's TPA cannot exceed 63 KiB).
BPMSIGN		LD		DE,BPMSG
			CALL	C_WRITESTR
			LD		HL,BDOSADDR-0100H
			LD		B,10
BPMSHIFT	SRL		H
			RR		L
			DJNZ	BPMSHIFT
			LD		A,L
			LD		B,'0'
BPMTENS		CP		10
			JR		C,BPMDIGITS
			SUB		10
			INC		B
			JR		BPMTENS
BPMDIGITS	PUSH	AF
			LD		E,B
			CALL	C_WRITE
			POP		AF
			ADD		A,'0'
			LD		E,A
			CALL	C_WRITE
			LD		DE,BPMSUFF
			JP		C_WRITESTR

BPMSG		DEFB	13
			DEFM	'BP/M TPA '
			DEFB	'$'
BPMSUFF		DEFM	'K'
			DEFB	13,'$'

BDOSIMP
;;			CALL	PRHEX			; Print sys call number

			LD		A,C				; Prepare to check C is in range
			CP		41				; Max syscall# for CP/M 2.2 is 40
			JP		NC,UNIMP		; If >41 then call UNIMP
			LD		HL,BDOSVEC		; Start of vector table
			SLA		C				; Multiply C by 2
			LD		B,0				; MSB of BC is zero
			ADD		HL,BC			; Address of vector in HL
			LD		C,(HL)			; Read LSB of address to jump to
			INC		HL				; Read MSB of address to jump to
			LD		H,(HL)			; ...
			LD		L,C				; Address needs to be in HL
			JP		(HL)			; Jump to it!

; Vector table
BDOSVEC		DEFW	C_TERMCPM		; C=00H
			DEFW	C_READ			; C=01H
			DEFW	C_WRITE			; C=02H
			DEFW	UNIMP			; C=03H  (A_READ)   AUX
			DEFW	UNIMP			; C=04H  (A_WRITE)  AUX
			DEFW	UNIMP			; C=05H  (L_WRITE)  PRN
			DEFW	C_RAWIO			; C=06H
			DEFW	GET_IOB			; C=07H
			DEFW	SET_IOB			; C=08H
			DEFW	C_WRITESTR		; C=09H
			DEFW	C_READSTR		; C=0AH
			DEFW	C_STAT			; C=0BH
			DEFW	S_BDOSVER		; C=0CH
			DEFW	DRV_ALLRST		; C=0DH
			DEFW	DRV_SET			; C=0EH
			DEFW	F_OPEN			; C=0FH
			DEFW	F_CLOSE			; C=10H
			DEFW	F_SFIRST		; C=11H
			DEFW	F_SNEXT			; C=12H
			DEFW	F_DELETE		; C=13H
			DEFW	F_READ			; C=14H
			DEFW	F_WRITE			; C=15H
			DEFW	F_MAKE			; C=16H
			DEFW	F_RENAME		; C=17H
			DEFW	DRV_LOGVEC		; C=18H
			DEFW	DRV_GET			; C=19H
			DEFW	F_DMAOFF		; C=1AH
			DEFW	DRV_AVEC		; C=1BH
			DEFW	DRV_SETRO		; C=1CH
			DEFW	DRV_ROVEC		; C=1DH
			DEFW	UNIMP			; C=1EH  (F_ATTRIB)
			DEFW	DRV_DPB			; C=1FH
			DEFW	F_USERNUM		; C=20H
			DEFW	F_READRAND		; C=21H
			DEFW	F_WRITERAND		; C=22H
			DEFW	F_SIZE			; C=23H
			DEFW	F_RANDREC		; C=24H
			DEFW	DRV_RESET		; C=25H
			DEFW	UNIMP			; C=26H  (*nothing* in CP/M 2.2)
			DEFW	UNIMP			; C=27H  (*nothing* in CP/M 2.2)
			DEFW	F_WRITERAND		; C=28H  (F_WRITEZF)

; Unimplemented BDOS call, just ring the bell
UNIMP		LD		HL,BELL			; We are going to call BELL
			LD		(ADDR),HL		; ...
			LD		A,1				; CMD=1 means call 6502 sub
			LD		(CMD),A			; ...
			LD 		(SOFTCARD),A	; Do it!
			RET						; Return to calling program

; System reset.  Jump to $0000 - doesn't return
C_TERMCPM	RST		0				; Quick jump to zero

; Wait for a character from the console, return it in A and L
; Also echoes the char to the console
C_READ		LD		HL,RDKEY		; We are going to call RDKEY
			LD		(ADDR),HL		; ...
			LD		A,1				; CMD=1 means call 6502 sub
			LD		(CMD),A			; ...
			LD		(SOFTCARD),A	; Do it!
			LD		A,(AREG)		; Grab the return value
			CP		83H				; See if it is Ctrl-C
			JP		Z,BDOSWARM		; Ctrl-C is a warm boot (no banner)
			PUSH	AF				; Preserve A (and F)
			LD		HL,COUT			; Echo the character using COUT
			LD		(ADDR),HL		; ...
			LD		A,1				; CMD=1 means call 6502 sub
			LD		(CMD),A			; ...
			LD		(SOFTCARD),A	; Do it!
			POP		AF				; Restore A (and F)
			AND		7FH				; Mask high bit
			LD		L,A				; Copy A to L
			RET						; Return to calling program

; BDOS console output.  The 6502 driver handles tabs, CR, backspace,
; clear-screen and the other minimal console controls.  Ignore LF because
; the direct video driver's CR already moves to the next line.
C_WRITE		LD		A,E
			CP		0AH
			RET		Z
			JR		C_PUT

; Shared low-level output path for cooked and direct console writes.
; E = ASCII character; 6502 console driver accepts bit 7 set or clear.
C_RAWPUT	LD		A,E			; Raw output retains correct CR/LF meaning
			LD		HL,RAWOUT	; B80F raw 6502 vector
			JR		C_SENDA
C_PUT		LD		A,80H			; Cooked BDOS function 2
			OR		E
			LD		HL,COUT		; B803 cooked 6502 vector
C_SENDA		LD		(AREG),A
			LD		(ADDR),HL
			LD		A,1
			LD		(CMD),A
			LD		(SOFTCARD),A
			RET

; CP/M BDOS function 6: E=FF nonblocking read, else raw output.
; This route uses the raw 6502 entry (CR and LF independent).
C_RAWIO		LD		A,E
			CP		0FFH
			JR		Z,RIS1
			JR		C_RAWPUT

			; If character is waiting, read from console & return in A
			; Otherwise, return 00H in A
RIS1		LD		A,3				; CMD=3 means peek at keyboard
			LD		(CMD),A			; ...
			LD		(SOFTCARD),A	; Do it
			LD		A,(AREG)		; Grab the return value
			CP		0				; If zero, no chars are waiting
			JR		Z,RIS2			; ...
			LD		HL,RDKEY		; We are going to call RDKEY
			LD		(ADDR),HL		; ...
			LD		A,1				; CMD=1 means call 6502 sub
			LD		(CMD),A			; ...
			LD		(SOFTCARD),A	; Do it!
			LD		A,(AREG)		; Grab the return value
			AND		7FH				; Mask high bit
			LD		L,A				; Copy A to L
			RET						; 
RIS2		XOR		A				; No chars waiting, A=0
			LD		L,A				; Return in L also
			RET

; Get the IOBYTE in A and L
GET_IOB		LD		A,(IOBYTE)		;
			LD		L,A				; Copy to L
			RET

; Set the IOBYTE
; E contains the IOBYTE value to set
SET_IOB		LD		A,E				;
			LD		(IOBYTE),A		;
			RET

; Write ASCII string to console. '$' is the terminator
; DE contains the address of the string
C_WRITESTR	LD		A,(DE)			; Fetch character from string
			CP		'$'				; Is it '$'?
			RET		Z				; If so, we are done
			PUSH	DE				; We are gonna need E
			LD		E,A				; For C_WRITE
			CALL	C_WRITE			; Sent char to console
			POP		DE				; Recover the pointer
			INC		DE				; Advance pointer
			JR		C_WRITESTR		; Handle the next char

; Read console string
; DE points to the string buffer. First byte of the buffer is the capacity
; of the buffer. This function writes the number of bytes written in second
; byte.  Entry finishes on CR or when the buffer is filled up.
; Supports ^H, DEL for deleting a character
; Supports ^Z for deleting entire line (since ^X doesn't work with RDKEY
C_READSTR	LD		H,D				; HL will be the working pointer
			LD		L,E				; ...
			INC		HL				; Advance to first character ...
			INC		HL				; ... 3rd byte of the buffer
			PUSH	DE				; Put DE into IX
			POP		IX				; ...
			XOR		A				; Set number of chars read to zero
			LD		(IX+1),A		; ...
CRSL1		PUSH	HL				; Preserve HL
			CALL	C_READ			; Read a character into A
			POP		HL				; Restore HL
			CP		13				; Carriage return ^M pressed?
			RET		Z				; If so, we are done
			CP		10				; Line feed ^J pressed?
			RET		Z				; If so, we are done
			CP		8				; Backspace ^H pressed?
			JP		Z,CRSS2			; Handle backspace
			CP		7FH				; Delete key pressed?
			JR		Z,CRSS1			; Handle delete
			CP		26				; ^X pressed?
			JP		Z,CRSS3			; Handle ^X
			LD		B,A				; Stash character in B
			LD		A,(IX+0)		; Buffer capacity -> A
			SUB		(IX+1)			; Subtract characters read
			CP		0				; If no space left ...
			RET		Z				;  ... we are done
			LD		(HL),B			; Write character to buffer
			INC		HL				; Advance to next character
			INC		(IX+1)			; Increment character count
			JR		CRSL1			; Loop
			RET						;
CRSS1		PUSH	HL
			LD		E,8				; Print two backspaces (^H)
			CALL	C_WRITE			; ...
			CALL	C_WRITE			; ...
			LD		E,' '			; Print two spaces to erase chars
			CALL	C_WRITE			; ...
			CALL	C_WRITE			; ...
			LD		E,8				; Print two backspaces (^H)
			CALL	C_WRITE			; ...
			CALL	C_WRITE			; ...
			POP		HL
CRSS2		PUSH	HL
			LD		E,' '			; Print space to erase character
			CALL	C_WRITE			; ...
			LD		E,8				; Print backspace (^H)
			CALL	C_WRITE			; ...
			LD		A,(IX+1)		; Get character count
			CP		0				; See if it is zero
			POP		HL
			JP		Z,CRSL1			; If so, back to top of loop
			DEC		HL				; Delete previously-entered character
			DEC		(IX+1)			; Decrement character count
			JP		CRSL1			; Back to top of loop
CRSS3		LD		A,0				; Set character count to zero to ...
			LD		(IX+1),A		; ... cancel the entire entry
			LD		E,13			; Print a carriage return
			CALL 	C_WRITE			; ...
			RET						; Done

; Returns 0 in A and L if no chars waiting, non zero otherwise
C_STAT		LD		A,3				; CMD=3 means peek at keyboard
			LD		(CMD),A			; ...
			LD		(SOFTCARD),A	; Do it
			LD		A,(AREG)		; Grab the return value
			LD		L,A				; Copy A to L
			RET

; Returns system type in B and H, BDOS version in A and L
S_BDOSVER	LD		B,0				; System is 8080 CP/M
			LD		H,B				; Also in H
			LD		A,22H			; Pretend to v2.2
			LD		L,A				; Also in A
			RET

; Reset disks
; Makes A: drive the default
DRV_ALLRST	LD		A,(CURDRV)		; Contains both user & current drive
			AND		0F0H			; Set drive to 0, meaning A:
			LD		(CURDRV),A		; Store in CURDRV
			LD		BC,FILEBUF		; FILEBUF is at 0080H
			LD		(DMAADDR),BC	; Reset DMA address
			LD		HL,FLMLI		; Pass address of 6502 JSR instruction
			CALL	PRODOS			; Invoke ProDOS MLI to flush all files
			RET

; Select disk
; Disk to select is passed in E (A: is 0, B: is 1 etc.)
; Return 00 for success, 0FFH for error in A and L
DRV_SET		LD		A,E				; Prepare to compare disk number
			CP		16				; Support 16 'drives' A: - P:
			JR		NC,DSERR		; If A>15 ... error
			LD		B,A				; Stash in B for now
			LD		A,(CURDRV)		; Has both user number & current drive
			AND		0F0H			; Mask out old drive number
			OR		B				; Replace with new drive number
			LD		(CURDRV),A		; Store the requested drive number
			XOR		A				; A=0: Return code meaning success
			JR		DSRET			; 
DSERR		LD		A,0FFH			; Return code for error
DSRET		LD		L,A				; Return code in L too
			RET

; Open file
; DE is the address of the FCB describing the file to open
; Returns error codes in A and L:
; Returns 0 for success.  The FCB for the file opened is left at DMAADDR (slot 0)
; Returns 0FFH if file not found
; Opening a file must NOT replace an ongoing BDOS wildcard directory search.
; ProDOS OPEN already checks existence; F_SFIRST is not needed here.
F_OPEN		CALL	_F_OPEN			; Open physical ProDOS file
			OR		A
			RET		NZ				; Error (already in A and L)
			CALL	F_CLOSE			; Release ProDOS handle immediately
			OR		A
			RET		NZ
			PUSH	DE
			POP		IX
			LD		(IX+0EH),0FEH	; Logical CP/M open, no host handle
			XOR		A
			LD		L,A
			RET

; Alternative entrypoint used for opening ProDOS directory files
; and used by the CCP to load .COM files.  No directory lookup.
_F_OPEN		LD		IX,PATHBUF		; Destination buffer
			CALL	FCB2PATH		; Populate PATHLEN and PATH

			PUSH	DE				; Copy pointer to FCB ...
			POP		IY				; ... into IY

			; Work out which IOBUF to allocate for this file
			XOR		A				; Looking for FRN slot with value 0
			CALL	GETIOADDR		; Returns FRN slot in A, IOBUF in HL
			CP		0FFH			; Check for error
			JP		Z,FOFULL		; If no slots available, diagnostic

			LD		(TEMPBYTE),A	; Record the buffer index in local var
			LD		BC,OFFSET		; Add offset to convert to 6502 address
			ADD		HL,BC			; ...
			LD		(FOMLII),HL		; Store in parameter list

			LD		HL,FOMLI		; Pass address of 6502 JSR instruction
			CALL	PRODOS			; Invoke ProDOS MLI
			CP		0				; See if there was an error
			JP		NZ,FOERR		; Handle error

			; Do not publish S2/claim an FRN slot before GET_EOF succeeds.
			; On failure, OPEN has nevertheless allocated a ProDOS handle:
			; close it using the ref number from FOMLIN, then return error.
			LD		A,(FOMLIN)
			LD		(GEMLIN),A
			LD		(FCMLIN),A		; Prepare cleanup CLOSE (no slot yet)
			LD		HL,GEMLI
			CALL	PRODOS			; GET_EOF (24-bit size)
			OR		A
			JR		Z,FO_EOF_OK
			LD		HL,FCMLI
			CALL	PRODOS			; CLOSE even if GET_EOF failed
			JP		FOERR			; Do not trust GEMLIE1..3 or FCB S2
FO_EOF_OK	LD		A,(FOMLIN)
			LD		(IY+0EH),A		; Publish physical reference only now

			; CP/M RC counts records in extent zero (maximum 128).
			; Round partial 128-byte records up; honour ProDOS's 24-bit EOF.
			LD		A,(GEMLIE3)
			OR		A
			JR		NZ,FO_RC_FULL
			LD		A,(GEMLIE2)
			CP		40H			; >= $4000 bytes (16 KiB)?
			JR		NC,FO_RC_FULL
			; ceil(EOF/128) for EOF < $4000, with no 16-bit wrap.
			LD		HL,(GEMLIE1)
			LD		BC,127
			ADD		HL,BC
			LD		A,L
			RLCA
			AND		1
			LD		B,A
			LD		A,H
			ADD		A,A
			OR		B
			JR		FO_RC_STORE
FO_RC_FULL	LD		A,80H
FO_RC_STORE	LD		(IY+0FH),A

			; Set sequential record number to zero
			XOR		A				; Zero the sequential record number
			LD		(IY+20H),A		; ...

			; Store ProDOS FRN in slot FRN1 or FRN2
			LD		A,(TEMPBYTE)	; Obtain IOBUF idx (1,2)
			LD		HL,FRN1-1		; Compute address of FRN slot to use
			LD		B,0				; ...
			LD		C,A				; ...
			ADD		HL,BC			; ...
			LD		A,(FOMLIN)		; Get ProDOS file reference number
			LD		(HL),A			; Store in FRN slot

			XOR		A				; Success
			LD		L,A				; Copy to L
			RET						; Done

; Retain diagnostic on genuine buffer exhaustion while testing.
FOFULL		PUSH	DE
			LD		DE,FOFULLMSG
			CALL	C_WRITESTR
			POP		DE
			JR		FOERR
FOFULLMSG	DEFM	'NO IOBUF'
			DEFB	13,'$'

FOERR		LD		A,0FFH			; Error return status
			LD		L,A				; Copy to L
			RET						; Done (error)

; Close file
; DE is the address of the FCB describing the file to close
; Returns error codes in A and L:
F_CLOSE		LD		H,D				; Pointer to FCB ...
			LD		L,E				; ... into HL
			LD		BC,0EH			; Offset to S2 field (reserved field)
			ADD		HL,BC			; Compute address
			LD		A,(HL)			; Obtain file reference num from FCB S2
			CP		0FEH			; Virtual CP/M open, no ProDOS ref
			JR		NZ,FCPHYS
			LD		(HL),0			; Mark CP/M file closed
			JP		FCSUCC
FCPHYS		CP		0				; If file reference number is zero ...
			JR		Z,FCSUCC		; ... Nothing to do, just return
			LD		(FCMLIN),A		; Store in parameter list
			LD		HL,FCMLI		; Pass address of 6502 JSR instruction
			CALL	PRODOS			; Invoke ProDOS MLI
			CP		0				; See if there was an error
			JR		NZ,FCERR		; Handle error

			LD		A,(FCMLIN)		; Obtain file reference number again
			CALL	GETIOADDR		; Returns FRN slot in A, IOBUF in HL
			CP		0FFH			; Check for error
			JR		Z,FCERR			; If FRN not found, error out

			LD		HL,FRN1-1		; Compute addr of FRN slot to set to zero
			LD		B,0				; ...
			LD		C,A				; ...
			ADD		HL,BC			; ...
			XOR		A				; And zero it
			LD		(HL),A			; ...

			PUSH	DE				; Copy pointer to FCB ...
			POP		IX				; ... into IX
			XOR		A				; Zero out the S2 field
			LD		(IX+0EH),A		; ...

FCSUCC		XOR		A				; Return zero for error
			LD		L,A				; Return in L also
			RET

FCERR		LD		A,0FFH			; 0FFH for error
			LD		L,A				; Return code in L also
			RET

DIRHDSZ		EQU		2BH				; Size of ProDOS directory header
FILEENTSZ	EQU		27H				; Size of ProDOS file entry
ENTPERBLK	EQU		0DH				; Number of file entries per block

; Search for first match of filename in directory
; DE is the address of the FCB describing the file to look for
; Returns error codes in A and L: 0 for success, 0FFH for not found
; The matching FCB is always in slot 0, so success return code always 0
F_SFIRST 	LD		(TEMPWORD),DE	; Store pointer to search FCB
			LD		A,(DE)			; Obtain drive number
			LD		(DFCBDRV),A		; Copy to directory FCB
			LD		DE,DFCB			; Use this FCB to open the directory
			CALL	F_CLOSE			; Close the directory, if open
			LD		DE,DFCB			; Use this FCB to open the directory
			CALL	_F_OPEN			; Open the directory (avoiding recursion!)
			OR		A			; _F_OPEN returns status in A, not flags
			JR		NZ,FSFS2		; OPEN failed: return no match, no stale DFCB read

FSFL1		LD		A,0FFH			; Init CDBEXT to 0FFH (see CHKDIRBLK)
			LD		(CDBEXT),A		; ...
			CALL	RDDIRBLK		; Read first 512 byte block
			CP		0				; See if it was an error
			JR		NZ,FSFS2		; If error, assume EOF & just return

			; RDDIRBLK sets CDBPTR/CDBCOUNT based on the link pointer.
			LD		DE,(TEMPWORD)	; Get ptr to search FCB back
			CALL	CHKDIRBLK		; Search directory block
			CP		0				; See if it was a match
			JR		Z,FSFS1			; If so, return
			JR		FSFL1			; Loop

FSFS1		LD		DE,(TEMPWORD)	; Get ptr to search FCB back
			LD		A,(DE)			; Obtain drive number
			LD		HL,(DMAADDR)	; Pointer to FCB we are returning
			LD		(HL),A			; Copy drive number to FCB
			XOR		A				; Match
			RET						;
FSFS2		JR		FSNS2			; Shared EOF cleanup (also OPEN failure)

; Search for next match of filename in directory
; The address of the FCB describing the file to look for is in TEMPWORD
; Returns error codes in A and L: 0 for success, 0FFH for not found
; The matching FCB is always in slot 0, so success return code always 0
F_SNEXT		LD		A,(CDBCOUNT)	; Entries already consumed
			CP		ENTPERBLK		; Last entry returned on previous search?
			JR		NC,FSNNEW		; Advance block before dereferencing
FSNL1		LD		DE,(TEMPWORD)	; Get ptr to search FCB back
			CALL	CHKDIRBLK		; Search directory block
			CP		0				; See if it was a match
			JR		Z,FSNS1			; If so, return

FSNNEW		LD		A,0FFH			; Init CDBEXT to 0FFH (see CHKDIRBLK)
			LD		(CDBEXT),A		; ...
			CALL	RDDIRBLK		; Read next 512 byte block
			CP		0				; See if it was an error
			JR		NZ,FSNS2		; If error, assume EOF & just return

			; RDDIRBLK sets CDBPTR/CDBCOUNT based on the link pointer.
			JR		FSNL1			; Loop

FSNS1		LD		DE,(TEMPWORD)	; Get ptr to search FCB back
			LD		A,(DE)			; Obtain drive number
			LD		HL,(DMAADDR)	; Pointer to FCB we are returning
			LD		(HL),A			; Copy drive number to FCB
			XOR		A				; Match
			RET						;
FSNS2		JP		SEARCH_EOF		; Release directory FRN on end-of-search

; Delete file
; DE is the address of the FCB describing the file to delete
; Returns error codes in A and L:
; For an exact name, destroy directly; don't clobber the caller's
; F_SFIRST/F_SNEXT enumeration.  Preserve old logic for wildcards.
F_DELETE	LD		H,D
			LD		L,E
			INC		HL				; Skip FCB drive byte
			LD		B,11			; 8 + 3 filename characters
FD_CHKWILD	LD	A,(HL)
			CP		'?'
			JR		Z,FD_WILD
			INC		HL
			DJNZ	FD_CHKWILD
			LD		IX,PATHBUF
			CALL	FCB2PATH
			LD		HL,FDMLI
			CALL	PRODOS
			OR		A
			JR		Z,FD_OK
			LD		A,0FFH
FD_OK		LD		L,A
			RET
; Wildcard delete: never mutate an open ProDOS directory while using
; its cached search state.  Delete ONE match, close the directory before
; DESTROY, then restart F_SFIRST against the updated directory.
; The first search distinguishes "no matches" from "all matches deleted".
FD_WILD		PUSH	DE				; Save original wildcard FCB
			CALL	F_SFIRST		; Find the first matching file
			CP		0FFH
			JR		Z,FDS2			; Nothing matched initially
FDL1		LD		DE,DFCB
			CALL	F_CLOSE			; Release directory before DESTROY
			OR		A
			JR		NZ,FDS2
			LD		DE,FILEBUF		; Matching FCB from F_SFIRST
			LD		IX,PATHBUF
			CALL	FCB2PATH
			LD		HL,FDMLI
			CALL	PRODOS			; ProDOS DESTROY
			OR		A
			JR		NZ,FDS2
			POP		DE				; Restore original wildcard
			PUSH	DE
			CALL	F_SFIRST		; Re-read directory after deletion
			CP		0FFH
			JR		NZ,FDL1		; Another match
FDS1		XOR		A				; Success: at least one file deleted
			JR		FDSDONE
FDS2		LD		A,0FFH			; No match / ProDOS error
FDSDONE		PUSH	AF				; Preserve deletion status
			LD		DE,DFCB
			CALL	F_CLOSE			; Release directory on every exit
			POP		AF
			POP		DE				; Balance saved wildcard FCB
			LD		L,A
			RET

; CP/M files are logically open even while their ProDOS handle is closed.
; We use S2=$FE as a virtual-open marker. _F_OPEN is deliberately used
; here to avoid disturbing the global directory search in F_SFIRST.
; The current extent, RC and sequential record are saved because _F_OPEN
; refreshes the FCB size and resets the sequential record number.
; Internal directory and CCP loader handles remain physical (S2=FRN).
IO_BEGIN	XOR		A
			LD		(IOVIRT),A
			LD		A,(IX+0EH)
			CP		0FEH
			JR		Z,IO_REOPEN
			OR		A				; Zero means not open
			JR		Z,IO_BAD
			XOR		A
			RET
IO_BAD		LD		A,9				; Invalid FCB
			RET
IO_REOPEN	LD		A,1
			LD		(IOVIRT),A
			LD		A,(IX+0FH)
			PUSH	AF				; RC
			LD		A,(IX+0CH)
			PUSH	AF				; Extent
			LD		A,(IX+20H)
			PUSH	AF				; Current record
			PUSH	DE
			PUSH	IX
			CALL	_F_OPEN
			LD		C,A				; Preserve status across POP AFs
			POP		IX
			POP		DE
			POP		AF
			LD		(IX+20H),A
			POP		AF
			LD		(IX+0CH),A
			POP		AF
			LD		(IX+0FH),A
			LD		A,C
			OR		A
			RET		Z
			PUSH	AF				; Failed to open: no close needed
			XOR		A
			LD		(IOVIRT),A
			POP		AF
			RET

; Preserve BDOS status while releasing the transient ProDOS handle.
IO_END		PUSH	AF
			LD		A,(IOVIRT)
			OR		A
			JR		Z,IO_DONE
			PUSH	IX
			POP		DE
			CALL	F_CLOSE
			OR		A
			JR		NZ,IO_CERR
			LD		(IX+0EH),0FEH	; Still logically open to CP/M
IO_DONE		POP		AF
			LD		L,A
			RET
IO_CERR		POP		AF				; Discard saved result
			LD		A,0FFH
			LD		L,A
			RET
IOVIRT		DEFB	0

; Read next record
; DE is the address of the FCB describing the file from which to read
; Returns error codes in A and L:
; 0 OK, 1 EOF, 9 invalid FCB, 10 media changed, 0FFH h/w error
F_READ		PUSH	DE				; Copy pointer to FCB ...
			POP		IX				; ... into IX
			CALL	IO_BEGIN		; Reopen logical CP/M FCB if needed
			OR		A
			JR		Z,F_READ_GO
			LD		L,A				; Invalid/open-error FCB
			JR		IO_END			; Close transient handle
F_READ_GO
			LD		A,(IX+0EH)		; Obtain file reference num from FCB S2
			LD		(SMMLIN),A		; Store in parameter list for SET_MARK
			LD		(FRMLIN),A		; Store in parameter list for READ

			LD		A,(IX+20H)		; Obtain sequential record number
			LD		B,(IX+0CH)		; Obtain extent from FCB
			CALL	EXRC2MARK		; Set all three ProDOS position bytes
			LD		HL,SMMLI		; Pass address of 6502 JSR instruction
			CALL	PRODOS			; Invoke ProDOS MLI - SET_MARK
			CP		4DH				; See if position was out of range
			JP		Z,FREOF			; If so, return EOF (1)
			CP		43H				; See if it was a bad file ref number
			JP		Z,FRBFCB		; If so, return invalid FCB code (9)
			CP		0				; See if there was some other error
			JP		NZ,FRERR		; If so, return code 0FFH (h/w error)

			LD		HL,(DMAADDR)	; Write data starting at DMA buffer addr
			LD		BC,OFFSET		; Convert to 6502 address
			ADD		HL,BC			; ...
			LD		(FRMLIDB),HL	; Store I/O buffer address in parm list

			CALL	READ128		; READ and pad a short record with ^Z
			CP		4CH				; See if it was EOF
			JR		Z,FREOF			; If so, return EOF code (1)
			CP		43H				; See if it was a bad file ref number
			JR		Z,FRBFCB		; If so, return invalid FCB code (9)
			CP		0				; See if there was some other error
			JR		NZ,FRERR		; If so, return code 0FFH (h/w error)

			LD		A,(IX+20H)		; Get sequential rec num from FCB
			INC		(IX+20H)		; Increment sequential record number
			CP		127				; Accumulator before increment
			JR		NZ,FRS1			; If not, then nothing else to do
			XOR		A				; Set sequential rec num to zero
			LD		(IX+20H),A		; ...
			INC		(IX+0CH)		; Increment the extent

FRS1		XOR		A				; Zero for success
			JP		IO_END			; Close transient handle
FREOF		LD		A,1				; EOF return code
			JP		IO_END			; Close transient handle
FRBFCB		LD		A,9				; Invalid FCB return code
			JP		IO_END			; Close transient handle
FRERR		LD		A,0FFH			; All other errors are 0FFH
			JP		IO_END			; Close transient handle

; Write next record
; DE is the address of the FCB describing the file to which to write
; Returns error codes in A and L:
; 0 OK, 1 dir full, 2 disk full, 9 invalid FCB, 10 media changed, 0FFH h/w error
F_WRITE		PUSH	DE				; Copy pointer to FCB ...
			POP		IX				; ... into IX
			CALL	IO_BEGIN		; Reopen logical CP/M FCB if needed
			OR		A
			JR		Z,F_WRITE_GO
			JP		IO_END			; Close transient handle
F_WRITE_GO
			LD		A,(IX+0EH)		; Obtain file reference num from FCB S2
			LD		(SMMLIN),A		; Store in parameter list for SET_MARK
			LD		(FWMLIN),A		; Store in parameter list for WRITE

			LD		A,(IX+20H)		; Obtain sequential record number
			LD		B,(IX+0CH)		; Obtain extent from FCB
			CALL	EXRC2MARK		; Set full 24-bit ProDOS position

;;			; DEBUG
;;			PUSH	HL
;;			LD		DE,HEXBUF		; (obsolete diagnostic)
;;			CALL	NUM2HEX			; (obsolete diagnostic)
;;			LD		DE,HEXBUF		; Write hex value to console
;;			CALL	C_WRITESTR		;
;;			POP		HL
;;			; END DEBUG

			LD		HL,SMMLI		; Pass address of 6502 JSR instruction
			CALL	PRODOS			; Invoke ProDOS MLI - SET_MARK
			CP		4DH				; See if position was out of range
			JP		Z,FWBFCB		; If so, return invalid FCB code (9)
			CP		43H				; See if it was a bad file ref number
			JP		Z,FWBFCB		; If so, return invalid FCB code (9)
			CP		0				; See if there was some other error
			JP		NZ,FWERR		; If so, return code 0FFH (h/w error)

			LD		HL,(DMAADDR)	; Write data at DMA address
			LD		BC,OFFSET		; Convert to 6502 address
			ADD		HL,BC			; ...
			LD		(FWMLIDB),HL	; Store I/O buffer address in parm list

			LD		HL,FWMLI		; Pass address of 6502 JSR instruction
			CALL	PRODOS			; Invoke ProDOS MLI - WRITE
			CP		43H				; See if it is a bad reference number
			JR		Z,FWBFCB		; If so, return invalid FCB code (9)
			CP		48H				; See if it was an overrun error
			JR		Z,FWDF			; If so, return disk full code (2)
			CP		0				; See if there was some other error
			JR		NZ,FWERR		; If so, return code 0FFH (h/w error)

			LD		A,(IX+20H)		; Get sequential rec num from FCB
			INC		(IX+20H)		; Increment sequential record number
			CP		127				; Accumulator before increment
			JR		NZ,FWS1			; If not, then nothing else to do
			XOR		A				; Set sequential rec num to zero
			LD		(IX+20H),A		; ...
			INC		(IX+0CH)		; Increment the extent

FWS1		XOR		A				; Zero for success
			JP		IO_END			; Close transient handle
FWBFCB		LD		A,9				; Invalid FCB return code
			JP		IO_END			; Close transient handle
FWDF		LD		A,2				; Disk full return code
			JP		IO_END			; Close transient handle
FWERR		LD		A,0FFH			; All other errors are 0FFH
			JP		IO_END			; Close transient handle

; Create (and open) file
; DE is the address of the FCB describing the file to create
; Returns error codes in A and L:
; 0 for success, 0FFH if file could not be created
F_MAKE		LD		IX,PATHBUF		; Destination buffer
			CALL	FCB2PATH		; Populate PATHLEN and PATH
			LD		HL,FMMLI		; Pass address of 6502 JSR instruction
			CALL	PRODOS			; Invoke ProDOS MLI
			CP		0				; See if there was an error
			JR		NZ,FMERR		; Handle error
			CALL	F_OPEN			; Open same FCB without touching search state
			OR		A
			RET		Z
			PUSH	AF				; Diagnostic for post-CREATE OPEN failure
			PUSH	BC
			PUSH	DE
			LD		C,A
			LD		DE,FMOPENMSG
			CALL	C_WRITESTR
			CALL	PRHEX			; Underlying Zapple-II error code
			POP		DE
			POP		BC
			POP		AF
			RET
FMERR		PUSH	AF
			PUSH	BC
			PUSH	DE
			LD		C,A
			LD		DE,FMCRMSG
			CALL	C_WRITESTR
			CALL	PRHEX			; Show true ProDOS CREATE error
			POP		DE
			POP		BC
			POP		AF
			LD		A,0FFH			; 0FFH for error
			LD		L,A				; Return code in L also
			RET
FMCRMSG		DEFM	'Zapple-II CREATE error: '
			DEFB	'$'
FMOPENMSG	DEFM	'Zapple-II OPEN-after-CREATE error: '
			DEFB	'$'

; Rename file
; DE is the address of the FCB describing the file to be renamed. The new name
; is stuffed into FCB+16 (where the allocation map usually goes)
; Returns error codes in A and L - 0 for success, 0FFH for file not found
; ProDOS RENAME checks that the old file exists.  Doing F_SFIRST here
; would clobber a wildcard enumeration in progress (notably PIP).
F_RENAME	LD		IX,PATHBUF		; Destination buffer 1
			CALL	FCB2PATH		; Populate PATHLEN and PATH for first file
			LD		IX,PATHBUF2		; Destination buffer 2
			LD		H,D				; DE -> HL for addition
			LD		L,E				; ...
			LD		BC,16			; Increment by 16 bytes to 2nd part of FCB
			ADD		HL,BC			; ...
			LD		D,H				; HL back to DE
			LD		E,L				; ...
			CALL	FCB2PATH		; Populate PATHLEN and PATH for second file
			LD		HL,FRNMLI		; Pass address of 6502 JSR instruction
			CALL	PRODOS			; Invoke ProDOS MLI
			CP		0				; See if there was an error
			JR		NZ,FRNERR		; Handle error
			XOR		A				; Success
			LD		L,A				; Return code in L also
			RET
FRNERR		LD		A,0FFH			; 0FFH for error
			LD		L,A				; Return code in L also
			RET

; Return bitmap of logged-in drives in HL
DRV_LOGVEC	LD		HL,(LOGVEC)		;
			RET

; Return current drive in A
DRV_GET		LD		A,(CURDRV)		; Contains user number & current drive
			AND		0FH				; Mask out user number
			RET

; Set DMA address
; DMA address is passed in DE
F_DMAOFF	LD		(DMAADDR),DE	;
			RET

; Return CP/M allocation map. Build it from the actual ProDOS volume bitmap.
DRV_AVEC	CALL	V_GETFREE
			LD		HL,ALLOCVEC
			RET

; Scan every ProDOS bitmap block, up to the full 65535-block (~32 MiB)
; volume limit. Set DSM to the actual volume capacity in 2 KiB CP/M blocks.
; The CP/M allocation vector is held in 6502 $0800-$0FFF (Z80 $F800-$FFFF)
; and built only AFTER all ProDOS READ_BLOCK calls are finished: the input
; block buffer and the returned allocation vector intentionally overlap.
;
; Volume directory block 2 has:
;  $04 = $Fx storage type, $23 = $27 entry length, $24 = $0D entries
;  $27/$28 = volume bitmap start, $29/$2A = number of 512-byte blocks.
; ProDOS bitmap: 1 = free, MSB first. CP/M bitmap: 0 = free, MSB first.
; NOTE: one bit per *virtual* 2K block; the bitmap only conveys a free
; space count. Block identities are synthetic (see N2FMAP).
;
; On errors, leave a fully allocated map, i.e. report zero free space.
; Last ProDOS READ_BLOCK error is recorded in VERR (for MAME debugger).
; ProDOS unit discovered from current prefix or drive directory by V_FINDUNIT.
V_GETFREE	XOR		A
			LD		(VERR),A

			; Discover the physical unit containing the CP/M directories.
			; This must precede READ_BLOCK of the volume header.
			CALL	V_FINDUNIT
			JP		NZ,V_ERROR

			LD		HL,2
			LD		(VRBLK),HL
			CALL	V_READ
			JP		NZ,V_ERROR

			; Validate that READ_BLOCK returned a volume header.
			LD		A,(VOLBUF+04H)
			AND		0F0H
			CP		0F0H
			JP		NZ,V_BADHDR
			LD		A,(VOLBUF+23H)
			CP		027H
			JP		NZ,V_BADHDR
			LD		A,(VOLBUF+24H)
			CP		00DH
			JP		NZ,V_BADHDR

			; How big is the actual volume? Retain this for debugging.
			LD		HL,(VOLBUF+29H)
			LD		(VTOTAL),HL
			LD		A,H
			OR		L
			JP		Z,V_BADHDR

			; All 16-bit ProDOS block numbers are representable.
			; 65535 blocks require 16 consecutive bitmap blocks.
			LD		(VLEFT),HL

			; CP/M virtual capacity: floor(number_of_512B_blocks / 4).
			SRL		H
			RR		L
			SRL		H
			RR		L
			LD		A,H
			OR		L
			JP		Z,V_BADHDR
			LD		(VNBLOCKS),HL
			DEC		HL
			LD		(DPBDSM),HL	; Correct DSM, e.g. 399 for 800 KiB

			; Last CP/M block uses byte DSM/8 and mask $80 >> (DSM%8).
			LD		A,L
			AND		07H
			LD		B,A
			LD		A,080H
V_SETMASK	LD		C,A
			LD		A,B
			OR		A
			LD		A,C
			JR		Z,V_MASKDONE
			SRL		A
			DEC		B
			JR		V_SETMASK
V_MASKDONE	LD		(VFMASK),A
			LD		HL,(DPBDSM)
			SRL		H
			RR		L
			SRL		H
			RR		L
			SRL		H
			RR		L
			LD		DE,ALLOCVEC
			ADD		HL,DE
			LD		(VFEND),HL

			; Reserve blocks 0..8 for CP/M directory / synthetic IDs.
			LD		HL,(VNBLOCKS)
			LD		DE,9
			OR		A
			SBC		HL,DE
			JR		NC,V_BUDGETOK
			LD		HL,0
V_BUDGETOK	LD		(VBUDGET),HL

			; Bitmap pointer must be a real volume block.
			LD		HL,(VOLBUF+27H)
			LD		A,H
			OR		L
			JP		Z,V_BADHDR
			LD		(VRBLK),HL
			LD		DE,(VTOTAL)
			OR		A
			SBC		HL,DE
			JP		NC,V_BADHDR
			LD		HL,0
			LD		(VFREE),HL

V_NEXTMAP	LD		HL,(VLEFT)
			LD		A,H
			OR		L
			JP		Z,V_READY
			CALL	V_READ
			JP		NZ,V_ERROR
			LD		HL,VOLBUF
			LD		BC,512
V_MAPBYTE	LD		E,(HL)
			LD		D,8
V_MAPBIT	PUSH	HL
			LD		HL,(VLEFT)
			LD		A,H
			OR		L
			JR		Z,V_DONEPOP
			DEC		HL
			LD		(VLEFT),HL
			POP		HL
			LD		A,E
			ADD		A,A
			LD		E,A
			JR		NC,V_USED
			PUSH	HL
			LD		HL,(VFREE)
			INC		HL
			LD		(VFREE),HL
			POP		HL
V_USED		DEC		D
			JR		NZ,V_MAPBIT
			INC		HL
			DEC		BC
			LD		A,B
			OR		C
			JR		NZ,V_MAPBYTE
			LD		HL,(VRBLK)
			INC		HL
			LD		(VRBLK),HL
			JP		V_NEXTMAP

V_DONEPOP	POP		HL
			JR		V_READY

; All input READ_BLOCK calls have finished. Reuse the $0800-$0FFF
; main-memory scratch area as the complete 2048-byte CP/M allocation map.
; 65535 ProDOS blocks / 4 = 16383 virtual 2K allocation blocks.
; Fill with $FF (occupied), then clear the free bits from the high end.
V_READY		CALL	V_CLEARVEC
			LD		HL,(VFREE)
			SRL		H
			RR		L
			SRL		H
			RR		L
			LD		B,H
			LD		C,L

V_MARK		LD		A,B
			OR		C
			RET		Z
			LD		HL,(VBUDGET)
			LD		A,H
			OR		L
			RET		Z		; Cannot exceed actual disk capacity
			DEC		HL
			LD		(VBUDGET),HL
			LD		HL,(VFEND)
			LD		A,(VFMASK)
			CPL
			AND		(HL)
			LD		(HL),A
			LD		A,(VFMASK)
			SRL		A
			JR		NZ,V_NEXTBIT
			LD		A,080H
			DEC		HL
V_NEXTBIT	LD		(VFMASK),A
			LD		(VFEND),HL
			DEC		BC
			JR		V_MARK

V_BADHDR	LD		A,0FEH		; Invalid/misread volume header
V_ERROR	LD		(VERR),A	; Capture MLI status for MAME debug
			; On failure advertise zero free blocks.
			CALL	V_CLEARVEC
			RET

; Fill the full 2K vector with $FF, not just 64 bytes. A $FF in the
; CP/M allocation bitmap means all blocks are used. LDIR copies the first
; $FF forward into each following location, taking 2047 transfers.
V_CLEARVEC	LD		HL,ALLOCVEC
			LD		(HL),0FFH
			LD		DE,ALLOCVEC+1
			LD		BC,2047
			LDIR
			RET

V_READ		LD		HL,VRMLI
			CALL	PRODOS
			OR		A
			RET

; Find the ProDOS unit containing the CP/M drive directories.
; Zapple-II uses relative paths such as "A/FILE.COM", so a nonempty
; ProDOS prefix identifies the volume.  GET_PREFIX provides /VOLUME/...;
; ON_LINE provides (unit + name length) and volume names in search order.
;
; If the prefix is null, find the first on-line volume with a directory
; named for the selected CP/M drive (A..P), following ProDOS search order.
; All MLI scratch space is in 6502 main $0800-$097F; the direct console
; uses text page 1, and READ_BLOCK overwrites this scratch area later.
; Returns A=0 on success, else an MLI error or $FD (no matching volume).
V_FINDUNIT	XOR		A
			LD		(VRUNIT),A	; Invalidate stale unit on failure
			LD		HL,VPMLI		; GET_PREFIX -> $0800
			CALL	PRODOS
			OR		A
			RET		NZ
			LD		A,(VOLBUF)	; Pascal prefix length
			OR		A
			JP		Z,V_NOPREFIX
			LD		B,A
			LD		HL,VOLBUF+1
			LD		A,(HL)
			CP		'/'
			JP		NZ,V_NOMATCH
			INC		HL
			DEC		B
			LD		C,0
V_PFXNAME	LD		A,B
			OR		A
			JP		Z,V_NOMATCH
			LD		A,(HL)
			CP		'/'
			JR		Z,V_PFXDONE
			INC		C
			LD		A,C
			CP		16		; ProDOS volume name is <= 15 chars
			JP		NC,V_NOMATCH
			INC		HL
			DEC		B
			JR		V_PFXNAME
V_PFXDONE	LD		A,C
			OR		A
			JP		Z,V_NOMATCH
			LD		(V_NAMELEN),A
			LD		A,1
			LD		(V_HASPFX),A
			JR		V_ENUM
V_NOPREFIX	XOR		A
			LD		(V_HASPFX),A

V_ENUM		LD		HL,VOMLI		; ON_LINE all units -> $0880
			CALL	PRODOS
			OR		A
			RET		NZ
			LD		IX,VOLBUF+080H
			LD		B,16		; Up to sixteen 16-byte records
V_SCAN		LD		A,(IX+0)
			OR		A		; End of returned list
			JP		Z,V_NOMATCH
			AND		0FH
			JP		Z,V_NEXT	; Device error; no name
			LD		C,A		; Name length from ON_LINE
			LD		A,(V_HASPFX)
			OR		A
			JR		Z,V_TRYDIR
			LD		A,(V_NAMELEN)
			CP		C
			JP		NZ,V_NEXT
			PUSH	BC
			PUSH	IX
			POP		DE
			INC		DE		; First character of ON_LINE name
			LD		HL,VOLBUF+2 ; After leading '/' in prefix
			LD		B,C
V_CMPNAME	LD		A,(DE)
			AND		0DFH		; Case-insensitive ProDOS name
			LD		C,A
			LD		A,(HL)
			AND		0DFH
			CP		C
			JR		NZ,V_DIFFER
			INC		DE
			INC		HL
			DJNZ	V_CMPNAME
			POP		BC
			JP		V_FOUND
V_DIFFER	POP		BC
			JP		V_NEXT

; Null prefix: see whether /VOLUME/<driveletter> is a ProDOS directory.
; The volume search order from ON_LINE mirrors relative pathname search.
V_TRYDIR	PUSH	BC
			LD		A,C
			ADD		A,3		; '/' + volume + '/' + drive
			LD		(VOLBUF),A
			LD		HL,VOLBUF+1
			LD		(HL),'/'
			INC		HL
			PUSH	IX
			POP		DE
			INC		DE
			LD		B,C
V_MKPATH	LD		A,(DE)
			LD		(HL),A
			INC		HL
			INC		DE
			DJNZ	V_MKPATH
			LD		(HL),'/'
			INC		HL
			LD		A,(CURDRV)
			AND		0FH
			ADD		A,'A'
			LD		(HL),A
			LD		HL,VFMLI		; GET_FILE_INFO on absolute path
			CALL	PRODOS
			OR		A
			JR		NZ,V_TRYNEXT
			LD		A,(VFTYPE)
			CP		0FH		; $0F is a ProDOS subdirectory
			JR		NZ,V_TRYNEXT
			POP		BC
			JR		V_FOUND
V_TRYNEXT	POP		BC
V_NEXT		LD		DE,16
			ADD		IX,DE
			DEC		B
			JP		NZ,V_SCAN
V_NOMATCH	LD		A,0FDH		; Prefix volume / CP/M dir not found
			RET
V_FOUND		LD		A,(IX+0)
			AND		0F0H		; Strip ON_LINE volume-name length
			LD		(VRUNIT),A	; ProDOS unit DSSS0000
			XOR		A
			RET

; Software write-protect current disk
DRV_SETRO	LD		B,80H			; Set MS-bit in B, will rotate this below
			LD		A,(CURDRV)		; Current drive (0 A:, 1 B: ...)
			AND		0FH				; Mask out user number
			INC		A				; It is easier if A: is 1, B is 2 etc.
			CP		9				; See if it in LS-byte or MS-byte of ROVEC
			JR		NC,DSRMSB		; If A>8 then drive bit in in MS-byte
DSRL1		RL		B				; 
			DEC		A				;
			JR		NZ,DSRL1		;
			LD		A,(ROVEC)		; Fetch the LS-byte of ROVEC
			OR		B				; Set the bit using OR
			LD		(ROVEC),A		; Store LS-byte back to ROVEC
			RET						; We're done
DSRMSB		LD		C,8				; Subtract 8 from the drive number
			SUB		C				; A = A-8
DSRL2		RL		B				;
			DEC		A				;
			JR		NZ,DSRL2		;
			LD		A,(ROVEC+1)		; Fetch the MS-byte of ROVEC
			OR		B				; Set the bit using OR
			LD		(ROVEC+1),A		; Store MS-byte back to ROVEC
			RET

; Return bitmap of read-only drives in HL
DRV_ROVEC	LD		HL,(ROVEC)		; Bit 0 of L is A:, bit 7 of H is P:
			RET

; Return pointer to Drive Parameter Block in HL
DRV_DPB		CALL	V_GETFREE		; Set DSM from real volume first
			LD		HL,DPB			; Pointer to drive parameter block
			RET

; Get/set user number
; E contains the user number to set, or 0FFH to get current user number
; If E is 0FFH then user number is returned in A
F_USERNUM	LD		A,E				; See if it is get or set
			CP		0FFH			; 0FFH means 'get'
			JR		Z,FUNS1			; It is 'get'
			LD		B,A				; Stash the user number to set in B
			SLA		B				; Left shift four times
			SLA		B				; ...
			SLA		B				; ...
			SLA		B				; ...
			LD		A,(CURDRV)		; Contains user number & current drive
			AND		0FH				; Mask out current user number
			OR		B				; OR in the new user number
			LD		(CURDRV),A		; Store updated user number & curr drv
			RET						;
FUNS1		LD		A,(CURDRV)		; Contains user number & current drive
			AND		0F0H			; Mask out current drive
			SRA		A				; Right shift the user number 4 times
			SRA		A				; ...
			SRA		A				; ...
			SRA		A				; ...
			RET

; Random access read record
; DE contains address of FCB describing the file to read
; Return code in A and L:
; 0 success, 1 reading unwritten data, 4 reading unwritten extent,
; 6 rec number out of range, 9 invalid FCB, 10 media changed, 0FFH h/w err
F_READRAND	PUSH	DE				; Copy pointer to FCB ...
			POP		IX				; ...
			CALL	IO_BEGIN		; Reopen logical CP/M FCB if needed
			OR		A
			JR		Z,F_READR_GO
			JP		IO_END			; Close transient handle
F_READR_GO
			LD		A,(IX+0EH)		; Obtain file reference num from FCB S2
			LD		(SMMLIN),A		; Store in parameter list for SET_MARK
			LD		(FRMLIN),A		; Store in parameter list for READ

			CALL	RAND2MARK		; Set full 24-bit ProDOS position
			JR		NC,FRR_MARK_OK
			LD		A,6				; Record outside ProDOS's 24-bit range
			JP		IO_END
FRR_MARK_OK
			LD		HL,SMMLI		; Pass address of 6502 JSR instruction
			CALL	PRODOS			; Invoke ProDOS MLI - SET_MARK
			CP		4DH				; See if position was out of range
			JP		Z,FRRRUD		; If so, return reading unwritten data (1)
			CP		43H				; See if it was a bad file ref number
			JP		Z,FRRBFCB		; If so, return invalid FCB code (9)
			CP		0				; See if there was some other error
			JP		NZ,FRRERR		; If so, return code 0FFH (h/w error)

			LD		HL,(DMAADDR)	; Write data starting at DMA buffer addr
			LD		BC,OFFSET		; Convert to 6502 address
			ADD		HL,BC			; ...
			LD		(FRMLIDB),HL	; Store I/O buffer address in parm list
			CALL	READ128		; READ and pad a short record with ^Z
			CP		4CH				; See if it was EOF
			JR		Z,FRRRUD		; If so, return EOF code (1)
			CP		43H				; See if it was a bad file ref number
			JP		Z,FRBFCB		; If so, return invalid FCB code (9)
			CP		0				; See if there was some other error
			JR		NZ,FRRERR		; If so, return code 0FFH (h/w error)

			LD		L,(IX+21H)		; Load random record number (LSB)
			LD		H,(IX+22H)		; Load random record number (MSB)
			CALL	RECS2EXRC		; Puts extent in B, recs in A
			LD		(IX+20H),A		; Update sequential record number
			LD		(IX+0CH),B		; Update sequential extent number

			XOR		A				; Zero for success
			JP		IO_END			; Close transient handle
FRRRUD		LD		A,1				; Reading unwritten data return code
			JP		IO_END			; Close transient handle
FRRBFCB		LD		A,9				; Invalid FCB return code
			JP		IO_END			; Close transient handle
FRRERR		LD		A,0FFH			; All other errors are 0FFH
			JP		IO_END			; Close transient handle

; Random access write record
; DE contains address of FCB describing the file to write
; Return code in A and L:
; 0 success, 1 reading unwritten data, 4 reading unwritten extent,
; 6 rec number out of range, 9 invalid FCB, 10 media changed, 0FFH h/w err
F_WRITERAND	PUSH	DE				; Copy pointer to FCB ...
			POP		IX				; ...
			CALL	IO_BEGIN		; Reopen logical CP/M FCB if needed
			OR		A
			JR		Z,F_WRTR_GO
			JP		IO_END			; Close transient handle
F_WRTR_GO
			LD		A,(IX+0EH)		; Obtain file reference num from FCB S2
			LD		(GEMLIN),A		; Store in parameter list for GET_EOF
			LD		(SEMLIN),A		; Store in parameter list for SET_EOF
			LD		(SMMLIN),A		; Store in parameter list for SET_MARK
			LD		(FWMLIN),A		; Store in parameter list for WRITE

			LD		HL,GEMLI		; Pass address of 6502 JSR instruction
			CALL	PRODOS			; Invoke ProDOS MLI - GET_EOF
			OR		A			; A nonzero means GEMLIE1..3 are invalid
			JP		NZ,FWRERR		; IO_END releases transient handle

			CALL	RAND2MARK		; Full 24-bit offset, carry if out of range
			JR		NC,FWR_MARK_OK
			LD		A,6
			JP		IO_END
FWR_MARK_OK
			; Compare 24-bit EOF against requested position.
			LD		A,(GEMLIE1)
			LD		HL,SMMLIP1
			SUB		(HL)
			INC		HL
			LD		A,(GEMLIE2)
			SBC		A,(HL)
			INC		HL
			LD		A,(GEMLIE3)
			SBC		A,(HL)
			JR		NC,FWRS1

			LD		HL,(SMMLIP1)
			LD		(SEMLIE1),HL
			LD		A,(SMMLIP3)
			LD		(SEMLIE3),A
			LD		HL,SEMLI		; Pass address of 6502 JSR instruction
			CALL	PRODOS			; Invoke ProDOS MLI - SET_EOF
			OR		A			; On failure, do NOT attempt SET_MARK/WRITE
			JP		NZ,FWRERR		; IO_END releases transient handle

FWRS1		LD		HL,SMMLI		; Pass address of 6502 JSR instruction
			CALL	PRODOS			; Invoke ProDOS MLI - SET_MARK
			CP		4DH				; See if position was out of range
			JP		Z,FWRBFCB		; If so, return invalid FCB code (9)
			CP		43H				; See if it was a bad file ref number
			JP		Z,FWRBFCB		; If so, return invalid FCB code (9)
			CP		0				; See if there was some other error
			JP		NZ,FWRERR		; If so, return code 0FFH (h/w error)

			LD		HL,(DMAADDR)	; Get DMA buffer address
			LD		BC,OFFSET		; Convert to 6502 address
			ADD		HL,BC			; ...
			LD		(FWMLIDB),HL	; Store I/O buffer address in parm list
			LD		HL,FWMLI		; Pass address of 6502 JSR instruction
			CALL	PRODOS			; Invoke ProDOS MLI - WRITE
			CP		43H				; See if it was a bad file ref number
			JR		Z,FWRBFCB		; If so, return invalid FCB code (9)
			CP		48H				; See if it was a bad file ref number
			JR		Z,FWRDF			; If so, return invalid FCB code (9)
			CP		0				; See if there was some other error
			JR		NZ,FWRERR		; If so, return code 0FFH (h/w error)

			LD		L,(IX+21H)		; Load random record number (LSB)
			LD		H,(IX+22H)		; Load random record number (MSB)
			CALL	RECS2EXRC		; Puts extent in B, recs in A
			LD		(IX+20H),A		; Update sequential record number
			LD		(IX+0CH),B		; Update sequential extent number

			XOR		A				; Zero for success
			JP		IO_END			; Close transient handle
FWRBFCB		LD		A,9				; Invalid FCB return code
			JP		IO_END			; Close transient handle
FWRDF		LD		A,2				; Disk fill return code
			JP		IO_END			; Close transient handle
FWRERR		LD		A,0FFH			; All other errors are 0FFH
			JP		IO_END			; Close transient handle


; Compute file size (BDOS function 35) from the exact ProDOS EOF.
; DE points to the caller's FCB.  On success, update FCB offsets
; 21H..23H with ceil(EOF/128), little endian (24-bit record count).
; A=L=0 on success, A=L=FFH on error.  Do not alter the FCB otherwise.
;
; GET_FILE_INFO does not return EOF, so temporarily OPEN the file,
; GET_EOF, then CLOSE it.  Reuse a free I/O buffer from the two usable slots,
; but do not claim a slot or alter the caller's S2 / open-file state.
; Only the randomly accessed file's FCB is updated; DMAADDR is untouched.
F_SIZE		PUSH	DE				; Keep FCB pointer across ProDOS calls
			LD		IX,PATHBUF		; FCB2PATH needs its destination in IX
			CALL	FCB2PATH

			XOR		A				; Look for an unused FRN/IOBUF slot
			CALL	GETIOADDR		; HL=free IOBUF, or A=FFH
			CP		0FFH
			JP		Z,FSERRPOP
			LD		BC,OFFSET		; Convert Z80 to 6502 buffer address
			ADD		HL,BC
			LD		(FOMLII),HL
			LD		HL,FOMLI		; ProDOS OPEN
			CALL	PRODOS
			OR		A
			JP		NZ,FSERRPOP	; No file opened: nothing to close

			LD		A,(FOMLIN)		; Temporary ProDOS reference number
			LD		(GEMLIN),A
			LD		(FCMLIN),A
			LD		HL,GEMLI		; ProDOS GET_EOF, 24-bit byte count
			CALL	PRODOS
			PUSH	AF				; Save GET_EOF result across CLOSE
			LD		HL,FCMLI		; Always CLOSE the temporary file
			CALL	PRODOS
			LD		B,A				; CLOSE error, if any
			POP		AF
			OR		A
			JP		NZ,FSERRPOP	; GET_EOF failed
			LD		A,B
			OR		A
			JP		NZ,FSERRPOP	; CLOSE failed

			; Shift 24-bit EOF right 7 to obtain 128-byte records.
			; A:H:L is the 24-bit value (high:middle:low).
			; E remembers whether the discarded low 7 bits are nonzero.
			LD		A,(GEMLIE1)
			LD		L,A
			AND		7FH
			LD		E,A
			LD		A,(GEMLIE2)
			LD		H,A
			LD		A,(GEMLIE3)
			LD		B,7
FS_SHIFT	SRL		A
			RR		H
			RR		L
			DJNZ	FS_SHIFT
			LD		C,A				; High byte of record count
			LD		A,E				; Round up partial final record
			OR		A
			JR		Z,FS_STORE
			INC		HL
			LD		A,H
			OR		L
			JR		NZ,FS_STORE
			INC		C				; Carry into 3rd record-count byte
FS_STORE	POP		DE				; Original caller's FCB
			PUSH	DE
			POP		IX
			LD		(IX+21H),L		; R0 (LSB)
			LD		(IX+22H),H		; R1
			LD		(IX+23H),C		; R2 (MSB)
			XOR		A
			LD		L,A
			RET
FSERRPOP	POP		DE				; Leave FCB unchanged on failure
			LD		A,0FFH
			LD		L,A
			RET

; Update random access pointer
; DE contains the pointer to the FCB to update
; Sets the random access record of the FCB to the value of the last record
; read or written sequentially
F_RANDREC	PUSH	DE				; Copy pointer to FCB ...
			POP		IX				; ... into IX
			LD		A,(IX+20H)		; Obtain sequential record number
			LD		B,(IX+0CH)		; Obtain extent from FCB
			CALL	EXRC2RECS		; Leaves the length in records in HL
			DEC		HL				; Because F_READ/F_WRITE advance this
			LD		(IX+21H),L		; Store in random access pointer ...
			LD		(IX+22H),H		; ... In little endian format
			LD		(IX+23H),0		; Upper record-count byte
			RET

; Selectively reset disk drives
; DE contains bitmap of drives to reset (bit 0 of E if A:, bit 7 of D is P:)
; Returns A=00H if okay, A=FFH if error
; Resetting means removing the read-only status
DRV_RESET	LD		A,(ROVEC)		; Do the LSB ...
			XOR		E				; ... with E
			LD		(ROVEC),A		;
			LD		A,(ROVEC+1)		; Then the MSB ...
			XOR		D				; ... with D
			LD		(ROVEC+1),A		;
			RET

; Make a ProDOS MLI call
; Address of 6502 JSR instruction in front of ProDOS parameter list is
; passed in in register pair HL, in Z80 address space
; Return code is passed back in A
PRODOS		LD		BC,OFFSET		; Add offset to convert Z80->6502 address
			ADD		HL,BC			; ...
			LD		(ADDR),HL		; Store it for 6502
			LD		A,2				; CMD=2 means ProDOS MLI call
			LD		(CMD),A			; ...
			LD 		(SOFTCARD),A	; Do it!
			LD		A,(AREG)		; Get return code from the MLI call
			RET

; Populate the PATH buffer (and PATHLEN) by copying from FCB
; If the FCB contains A:TEST____.TXT then the PATH buffer will be A/TEST.TXT
; Any '$' character in extension is converted to '8' so ProDOS can handle it
; DE contains a pointer to the FCB
; IX contains pointer to the path buffer into which to write
FCB2PATH	PUSH	IX				; Copy IX->IY
			POP		IY				; So IY keeps track of size byte at start
			INC		IX				; Advance past the size byte before writing
			LD		A,(DE)			; Get drive number from FCB
			CP		0				; See if it is zero (default drive)
			JR		NZ,F2PS1		; If drive explicit
			LD		A,(CURDRV)		; If default drive use CURDRV
			AND		0FH				; Mask out user number
			INC		A				; CURDRV is zero based
F2PS1		ADD		A,'A'-1			; Convert to drive letter
			LD		(IX+0),A		; Store as first char of path
			INC		IX				; Advance IX to next char of path to write
			LD		A,'/'			; Second char of path is '/'
			LD		(IX+0),A		; Store as second char of path
			INC		IX				; Advance IX to next char of path to write
			LD		C,2				; Use C to count chars in filename
			LD		H,D				; Copy address of FCB from DE ...
			LD		L,E				; ... to HL
			INC		HL				; HL points to filename in FCB

			LD		A,(HL)			; First character of filename
			CP		' '				; Is it space? ie: no file specified
			JP		Z,F2PS7			; Don't handle filename or extension

F2PL1		; Handle the filename - up to 8 characters
			LD		A,C				; Already copied 8 filename characters?
			CP		10				; 2 for drive/slash, plus 8
			JR		Z,F2PS3			; No need to save A in alternate AF
			LD		A,(HL)			; Obtain filename character
			CP		' '				; End of filename?
			JR		Z,F2PS3
			LD		(IX+0),A		; Copy to PATH buffer
			INC		C				; Increment filename char count
			INC		HL				; Next byte of filename in FCB
			INC		IX				; Next byte of PATH buffer
			JR		F2PL1

F2PS3		; Eat any space characters at end of filename
F2PL2		LD		A,(HL)			; Read next character from FCB
			CP		' '				; Is it space?
			JR		NZ,F2PS4		; If not, we are done eating!
			INC		HL				; Otherwise advance to next char
			JR		F2PL2			; And loop

F2PS4		LD		A,'.'			; Separator is a period
			LD		(IX+0),A		; Write to buffer
			INC		C				; Count the character!
			INC		IX				; Advance to next character in buffer
			LD		B,0				; Use B to track num chars in extension

			; Handle the extension - up to 3 characters
F2PL3		LD		A,B				; Number of extension chars copied
			CP		3				; Maximum of three
			JR		Z,F2PS7
			LD		A,(HL)			; Obtain extension character
			CP		' '				; End of extension?
			JR		Z,F2PS7
			CP		'$'				; ProDOS filename translation
			JR		NZ,F2PS5
			LD		A,'8'			; Replace '$' with '8'
F2PS5		LD		(IX+0),A		; Copy to PATH buffer
			INC		C				; Overall character count
			INC		B				; Extension character count
			INC		HL				; Next byte of filename in FCB
			INC		IX				; Next byte of PATH buffer
			JR		F2PL3

F2PS7		LD		A,C				; Store length of string
			LD		(IY+0),A		; We kept size byte in IY at start
			RET						;

; Clear FCB pointed to by DMAADDR
CLRFCB		LD		HL,(DMAADDR)	; 16-byte CP/M FCB header to zero
			LD		C,16
			XOR		A
CFL1		LD		(HL),A
			INC		HL
			DEC		C
			JR		NZ,CFL1
			LD		HL,(DMAADDR)	; FCB name/extension padded with spaces
			INC		HL
			LD		C,11
			LD		A,' '
CFL2		LD		(HL),A
			INC		HL
			DEC		C
			JR		NZ,CFL2
			RET

; This operation is almost the inverse of FCB2PATH.  It takes a pointer to the
; beginning of the ProDOS dirent and converts it to FCB format (8.3 with
; spaces for any unused characters.)
; Any '8' character in extension is converted back to '$' (see FCB2PATH)
; Handles '*' wildcard character
; HL points to the file entry in the ProDOS directory
; B contains the drive number (1 for A:, 2 for B: etc)
; C controls whether file size is populated in FCB (C=0 disables file size)
; The FCB is written to the buffer pointed to by DMAADDR
; Trashes pretty much all registers (except IX, IY)
NAME2FCB	PUSH	BC				; We will need C later
			PUSH	HL				; Remember source ProDOS dir entry for EOF
			EX		DE,HL			; Stash HL in DE for call to CLRFCB
			CALL	CLRFCB			; Clear FCB at DMAADDR
			EX		DE,HL			; Get file entry pointer back in HL
	
			LD		A,(HL)			; Obtain first char of ProDOS dirent
			AND		0FH				; Mask to obtain length of the name
			LD		C,A				; Stash source character count in C
			LD		DE,(DMAADDR)	; Initialize DE as write pointer
			LD		A,B				; Move drive number to A
			LD		(DE),A			; Write drive number
			LD		B,0				; Use B to count chars written
N2FL1		INC		HL				; Advance source pointer
			INC		DE				; Advance destination pointer
			LD		A,C				; Get count of chars remaining
			CP		0				; If none left ...
			JP		Z,N2FS6			; We are done
			LD		A,B				; Get count of chars written
			CP		8+3				; If 8+3 chars have been written ...
			JP		Z,N2FS6			; We are done
			LD		A,(HL)			; Read character
			CP		'.'				; See if it is a period
			JR		Z,N2FS2			; Prepare to copy the extension
			CP		'*'				; See if it is an asterix
			JR		Z,N2FS3			; Handle asterix wildcard
			LD		(DE),A			; Write character
			
			CP		'8'				; See if character in name is '8'
			JR		NZ,N2FS0		; If not, then no substitution
			LD		A,B				; See how many chars have been written
			CP		8				; >=8? If so we are in the extension
			JR		C,N2FS0			; If not, then no substitution
			LD		A,'$'			; Otherwise substitute '8'->'$'
			LD		(DE),A			; Re-write the substituted character

N2FS0		INC		B				; Increment count of chars written
N2FS1		DEC		C				; Decrement count of chars remaining
			JP		N2FL1			; Loop

			; Initialize DE, B to start processing the extension
N2FS2		LD		DE,(DMAADDR)	; Destination is start of extension
			INC		DE				;
			INC		DE				;
			INC		DE				;
			INC		DE				;
			INC		DE				;
			INC		DE				;
			INC		DE				;
			INC		DE				;
			LD		B,8				; 8 chars have been written
			JR		N2FS1			; Jump back into the read-write loop

			; Handle asterix wildcard character
N2FS3		LD		A,B				; See how many chars have been written
			CP		8				; >=8? If so we are in the extension
			JR		C,N2FS4			; If in main filename (not extension)

			; Asterix in extension
N2FL2		LD		A,'?'			; We will write '?' to rest of extension
			LD		(DE),A			; Write character
			INC		DE				; Increment write pointer
			INC		B				; Increment character count
			LD		A,B				; See if we are done
			CP		8+3				; Filename+extension
			JR		Z,N2FS6			; We are done
			JR		N2FL2			; Loop

N2FS4		; Asterix in main filename
N2FL3		LD		A,'?'			; We will write '?' to rest of filename
			LD		(DE),A			; Write character
			INC		DE				; Increment write pointer
			INC		B				; Increment character count
			LD		A,B				; See if we are done
			CP		8				; Filename+extension
			JR		Z,N2FS5			; We are done - eat chars up until '.'
			JR		N2FL3			; Loop

N2FS5		; Eat rest of chars up until '.'
N2FL4		LD		A,(HL)			; Get character
			CP		'.'				; See if it is a period
			JP		Z,N2FS2			; If so, go process the extension
			INC		HL				; Increment source pointer
			DEC		C				; Decrement count of chars remaining
			LD		A,C				; Get count of chars remaining
			CP		0				; If none left ...
			JR		Z,N2FS6			; We are done
			JR		N2FL4			; Loop

			; Handle file size info
N2FS6		POP		HL				; Source ProDOS file entry
			POP		BC				; Original size-request flag in C
			LD		A,C
			OR		A
			RET		Z				; FCB for parsing only; don't touch allocation bytes

			; ProDOS file entry EOF is a 24-bit little-endian byte count
			; at offsets 21..23. blocks_used includes sapling/tree
			; index blocks and is *not* the logical length.
			LD		DE,21
			ADD		HL,DE
			LD		E,(HL)			; EOF low byte
			INC		HL
			LD		D,(HL)			; EOF middle byte
			INC		HL
			LD		B,(HL)			; EOF high byte

			; EX is one byte in this implementation. Saturate at
			; 256 * 128 records = 4 MiB, represented by EX=255 RC=128.
			LD		A,B
			CP		40H
			JP		NC,N2FMAX

			; Compute ceil(EOF / 128) using EOF >> 7 plus one
			; for any nonzero fractional record. Result in HL.
			LD		A,E
			AND		7FH
			LD		C,0
			JR		Z,N2FALGN
			INC		C
N2FALGN	LD		A,E
			RLCA
			AND		1
			LD		L,A
			LD		A,D
			ADD		A,A
			OR		L
			LD		L,A
			LD		A,D
			RLCA
			AND		1
			LD		H,A
			LD		A,B
			ADD		A,A
			OR		H
			LD		H,A
			LD		A,C
			OR		A
			JR		Z,N2FROUND
			INC		HL

N2FROUND	PUSH	HL				; Save total records for exact boundary
			CALL	RECS2EXRC		; B = quotient /128, A = remainder
			POP		HL
			LD		C,A
			LD		A,H
			OR		L
			JR		Z,N2FSTORE	; Zero-length file
			LD		A,C
			OR		A
			JR		NZ,N2FSTORE
			DEC		B				; Exactly n*128 records: previous extent is full
			LD		C,080H
			JR		N2FSTORE

N2FMAX		LD		B,0FFH			; Clip files >=4 MiB to largest EX/RC
			LD		C,080H

N2FSTORE	LD		HL,(DMAADDR)
			PUSH	HL
			POP		IX
			LD		(IX+0CH),B
			LD		(IX+0FH),C
			LD		A,C
			CALL	N2FMAP
			RET

; Generate a synthetic CP/M 2.2 allocation map in the directory FCB.
; A = records in THIS extent (0..128), DMAADDR = returned FCB.
; DPB has 2 KB allocation blocks, 2-byte block numbers (DSM=511).
; Thus 16 records per block, 8 entries per extent.
; Fake block IDs 1..8 are intentionally reused for each file/extent:
; sufficient for STAT's per-file size column, NOT a filesystem allocator.
; Overwrites ALL 16 map bytes, so no separate clearing pass is needed.
; Trashes AF, BC, DE, HL; preserves IX and IY.
N2FMAP		ADD		A,15			; Round record count up to 16
			RRCA
			RRCA
			RRCA
			RRCA
			AND		0FH			; (records+15)/16 (0..8)
			LD		C,A
			LD		HL,(DMAADDR)
			LD		DE,16
			ADD		HL,DE			; Offset 16: start of allocation map
			LD		B,8				; Eight 16-bit block entries
			LD		D,1				; Fake block number, nonzero
N2FMLP		LD		A,C
			OR		A
			JR		Z,N2FMZERO
			LD		A,D				; Populated allocation entry
			DEC		C
			JR		N2FMSTORE
N2FMZERO	XOR		A				; Unused block entry
N2FMSTORE	LD		(HL),A			; Little endian, low byte
			INC		HL
			XOR		A
			LD		(HL),A			; High byte of block number
			INC		HL
			INC		D
			DJNZ	N2FMLP
			RET

; Read 512 byte block of directory
; Used by F_SFIRST and F_SNEXT
; Trashes HL + registers trashed by F_READ (best to assume all of them!)
; Returns A=0 for success, A=0FFH on error
RDDIRBLK	LD		HL,(DMAADDR)	; Preserve caller's DMA address
			PUSH	HL
			LD		HL,DIRBUF1	; Four consecutive 128-byte record buffers
			LD		B,4
RDBREAD	PUSH	BC			; F_READ may destroy registers
			PUSH	HL
			LD		(DMAADDR),HL
			LD		DE,DFCB
			CALL	F_READ
			POP		HL
			POP		BC
			OR		A			; 0=success, any other status=error
			JR		NZ,RDBS1
			LD		DE,128
			ADD		HL,DE
			DJNZ	RDBREAD

			; Every directory block starts with two link pointers ($00-$03).
			; A zero previous-block pointer identifies the key block, whose
			; first 39-byte entry ($04-$2A) is the directory header.
			; Count that header as entry 1 of 13; scan 12 actual files.
			; Other blocks contain 13 files beginning at offset $04.
			LD		HL,DIRBUF+4
			XOR		A
			LD		(CDBCOUNT),A
			LD		A,(DIRBUF)
			LD		B,A
			LD		A,(DIRBUF+1)
			OR		B
			JR		NZ,RDBPTR
			LD		HL,DIRBUF+DIRHDSZ
			LD		A,1
			LD		(CDBCOUNT),A
RDBPTR		LD		(CDBPTR),HL
			XOR		A				; Return code for success
			JR		RDBS2			; Successful return

RDBS1		LD		A,0FFH			; Error return code

RDBS2		POP		HL				; Reset DMA address as we found it
			LD		(DMAADDR),HL	; ...
			RET

; Match FCBs
; Used by CHKDIRENT
; DE is the address of the FCB describing the file to look for
; Compare with FCB at DMAADDR already created by NAME2FCB
; Returns A=0 if entry matches, A=FFH if no match
; Trashes A,BC,DE,HL
MATCHFCB	INC		DE			; Skip drive byte
			LD		HL,(DMAADDR)
			INC		HL
			LD		B,11			; 8.3 filename bytes
MFL1		LD		A,(DE)
			CP		'?'			; Wildcard matches any byte
			JR		Z,MFS1
			CP		(HL)
			JR		NZ,MFS2
MFS1		INC		DE
			INC		HL
			DJNZ	MFL1
			XOR		A
			RET
MFS2		LD		A,0FFH
			RET

; Compare a ProDOS directory file entry to see if it matches
; Used by F_SFIRST and F_SNEXT
; DE is the address of the FCB describing the file to look for
; HL points to the first file entry in the ProDOS directory
; Returns A=0 if entry matches, A=FFH if no match
CHKDIRENT	LD		B,0				; Hardcode drive A: MATCHFCB ignores it
			LD		A,(HL)			; Get first byte of file entry
			AND		0FH				; Mask to get the filename length
			CP		0				; If zero ...
			JR		Z,CDES1			; File is deleted - no match
			PUSH	HL				; Preserve HL
			PUSH	DE				; Preserve DE
			LD		C,1				; Do check file sizes and put in FCB
			CALL	NAME2FCB		; Create FCB in DMA buffer
			POP		DE				; Recover DE
			POP		HL				; Recover HL
			PUSH	HL				; Preserve HL
			PUSH	DE				; Preserve DE
			CALL	MATCHFCB		; Compare search FCB w/ FCB in DMA buffer
			POP		DE				; Recover DE
			POP		HL				; Recover HL
			RET					; MATCHFCB returns 0 or $FF
CDES1		LD		A,0FFH			; Deleted entry
			RET

; Search a 512 byte block of a ProDOS directory for a matching file entry
; Used by F_SFIRST and F_SNEXT
; DE is the address of the FCB describing the file to look for
; If the extent field of this FCB is '?' then all extents are returned
; CDBPTR points to the next ProDOS file entry to parse
; CDBCOUNT is set to the number of file entries already parsed in this block
; Returns A=0 if entry matches, A=FFH if no match
; Always reload the ProDOS directory pointer at the top of the loop.
; EX='?' processing uses HL for the synthetic FCB in DMAADDR; if a
; candidate does not match, CDBS2 loops here without advancing CDBPTR.
; Never pass that DMA address to CHKDIRENT as a ProDOS dir entry.
CHKDIRBLK
CDBL1		LD		HL,(CDBPTR)		; Reload each iteration, including EX='?' retries
			CALL	CHKDIRENT		; Match the file entry at HL, build FCB
			PUSH	AF				; Stash return code for now
			PUSH	DE				; Copy pointer to search FCB ...
			POP		IX				; ... into IX
			LD		A,(IX+0CH)		; Get extent field of search FCB
			CP		'?'				; Is it '?'
			JP		NZ,CDBS1		; If not, we can advance to next entry

			LD		A,(CDBEXT)		; Load CDBEXT
			CP		0FFH			; If it is 0FFH, means this is first ...
			JR		Z,CDBS0			; ... time we have looked at this dirent
			JR		CDBS01			; Not the first extent for this dirent

			; First extent for directory entry (highest numbered extent)
			; This extent may contain 1-128 records
CDBS0		LD		HL,(DMAADDR)	; Address of FCB created by CHKDIRENT
			PUSH	HL				; Copy address of FCB ...
			POP		IY				; ... into IY
			LD		A,(IY+0CH)		; Get num extents for this entry minus one
			LD		(CDBEXT),A		; Store it for next time
			LD		(IY+0CH),A		; Store it in the FCB returned to caller
			CP		0				; If CDBEXT will be zero next time
			JR		Z,CDBS1			; ... we can advance to next entry
			JP		CDBS2			; Return FCB for this extent (it match)

			; Not the first extent for directory entry
			; Always has 128 records
CDBS01		LD		HL,(DMAADDR)	; CHKDIRENT has rebuilt FCB
			PUSH	HL
			POP		IY				; Use the current output FCB
			LD		B,080H			; Earlier extents have 128 records
			LD		(IY+0FH),B		; Store in RC
			DEC		A				; Decrement extent counter
			LD		(CDBEXT),A		; Store it for next time
			LD		(IY+0CH),A		; Store it in EX
			PUSH	AF				; Keep extent number across N2FMAP
			PUSH	DE				; N2FMAP clobbers DE (search FCB pointer)
			LD		A,080H			; Full extent => eight 2 KB blocks
			CALL	N2FMAP
			POP		DE				; Restore search FCB pointer for CDBL1
			POP		AF
			CP		0				; If CDBEXT will be zero next time
			JR		Z,CDBS1			; ... we can advance to next entry
			JR		CDBS2			; Return FCB for this extent (it match)

CDBS1		LD		HL,(CDBPTR)		; Pointer to file entry
			LD		BC,FILEENTSZ	; Advance to next file entry
			ADD		HL,BC			; ...
			LD		(CDBPTR),HL		; Store the pointer
			LD		A,(CDBCOUNT)	; File entry counter
			INC		A				; Increment count of file entries
			LD		(CDBCOUNT),A	; Store the counter
			LD		A,0FFH			; Initialize CDBEXT to 0FFH ...
			LD		(CDBEXT),A		; ... to start processing next dirent

CDBS2		POP		AF				; Get return code back in A
			CP		0				; Was it a match?
			JR		Z,CDBS3			; If so, we are done
			LD		A,(CDBCOUNT)	; Get the counter back
			CP		ENTPERBLK		; Done all of them in this block?
			JP		NZ,CDBL1		; If not, loop
			LD		A,0FFH			; No match
			RET						;
CDBS3		XOR		A				; Match
			RET

; The following variables are used to preserve state between calls
CDBPTR		DEFW	0000H			; Stores pointer to next file entry
CDBCOUNT	DEFB	0				; Stores file entry counter
CDBEXT		DEFB	0				; Stores extent number

; Find IOBUF address for a file reference number
; Scan only FRN1..FRN2: third 1K region is spare, fourth is stack.
; If found, return FRN slot# 1 or 2 in A, I/O buffer address in HL
; If not found, return A=0FFH
; Trashes BC
GETIOADDR	LD		B,A			; Requested FRN (0 = first free slot)
			LD		HL,FRN1		; FRN1 and FRN2 only
			LD		C,1			; One-based slot number
GIASCAN	LD		A,(HL)
			CP		B
			JR		Z,GIAFOUND
			INC		HL
			INC		C
			LD		A,C
			CP		3
			JR		NZ,GIASCAN
			LD		A,0FFH
			RET
GIAFOUND	LD		A,C			; Return slot 1 or 2 in A
			PUSH	AF
			DEC		A			; Buffer address = $9800 + (slot-1)*$400
			ADD		A,A
			ADD		A,A
			LD		HL,IOBUF1
			ADD		A,H
			LD		H,A
			POP		AF
			RET

; Form 24-bit ProDOS byte mark from CP/M extent B and record A.
; Valid record numbers are 0..127.  Byte offset = (B*128+A)*128.
; Updates SET_MARK parameter directly, avoiding any 16-bit overflow.
EXRC2MARK	LD		C,A
			AND		1
			RRCA				; bit 0 becomes bit 7
			LD		(SMMLIP1),A
			LD		A,C
			SRL		A
			LD		C,A
			LD		A,B
			RRCA
			RRCA
			AND		0C0H		; B bits 0..1 become byte-1 bits 6..7
			OR		C
			LD		(SMMLIP2),A
			LD		A,B
			SRL		A
			SRL		A
			LD		(SMMLIP3),A
			RET

; Form 24-bit ProDOS byte mark from random FCB record R0/R1/R2.
; ProDOS supports byte offsets < $1000000, hence record <= $1FFFF.
; Returns carry set for out-of-range random records.
RAND2MARK	LD		A,(IX+23H)
			CP		2
			JR		NC,RAND_MARK_BAD
			LD		B,A
			LD		A,(IX+21H)
			LD		C,A
			AND		1
			RRCA
			LD		(SMMLIP1),A
			LD		A,C
			SRL		A
			LD		C,A
			LD		A,(IX+22H)
			AND		1
			RRCA
			OR		C
			LD		(SMMLIP2),A
			LD		A,(IX+22H)
			SRL		A
			LD		C,A
			LD		A,B
			AND		1
			RRCA
			OR		C
			LD		(SMMLIP3),A
			OR		A				; Clear carry
			RET
RAND_MARK_BAD	SCF
			RET

; Convert pos in extent/recs format to a linear position in 128 byte records
; Extent number is passed in B
; Records within the extent is passed in A
; Returns the length in records in HL - HL = (B*128)+A
EXRC2RECS	LD		H,B			; 16-bit (extent*128 + record)
			LD		L,A			; Record must be 0..127
			LD		A,H
			RRCA				; Extent bit 0 -> bit 7 of low byte
			AND		80H
			OR		L
			LD		L,A
			SRL		H			; Extent bits 1..7 -> high byte
			RET

; Convert position in terms of random record number to extent/recs
; Length in records in passed in HL
; Returns extent number in B and records within extent in A
RECS2EXRC	SLA		H				; 7 MS-bits of extent number
			BIT		7,L				; See if MS-bit of L is set
			JR		Z,R2ERS1		; If set ...
			INC		H				; ... set LSB of extent number
R2ERS1		LD		B,H				; Return extent in B
			LD		A,L				; Now for the recs in the extent
			AND		7FH				; Just need to mask out MS-bit
			RET

; Compact diagnostic helper: print C as [XX] without a four-digit
; conversion buffer.  Preserve registers as the old PRHEX did.
PRHEX		PUSH	AF
			PUSH	BC
			PUSH	DE
			PUSH	HL
			LD		E,'['
			CALL	C_WRITE
			LD		A,C
			RRCA
			RRCA
			RRCA
			RRCA
			CALL	PHNYB
			LD		A,C
			CALL	PHNYB
			LD		E,']'
			CALL	C_WRITE
			POP		HL
			POP		DE
			POP		BC
			POP		AF
			RET
PHNYB		AND		0FH
			ADD		A,'0'
			CP		3AH			; One past ASCII '9'
			JR		C,PHOUT
			ADD		A,7
PHOUT		LD		E,A
			JP		C_WRITE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Compact CP/M 2.2-style CCP
;
; Commands:
; - d:           - Change default drive (A:, B: etc.)
; - DIR          - Show directory (DIR, DIR A:, DIR FOO.TXT, DIR *.COM)
; - ERA          - Erase file(s) (ERA FOO.TXT, ERA F*.TXT)
; - REN          - Rename file (REN BAR.TXT=FOO.TXT)
; - SAVE         - Save 256-byte pages of TPA (SAVE 7 FOO.COM)
; - TYPE         - Show text file on console (TYPE TEST.TXT)
; - BYE          - Confirm and exit to the ProDOS selector
; - FILENAME.COM - Load and run FILENAME.COM at 0100H
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Built-in argument counts and common filename mistakes are validated.
; Full CP/M filename grammar is not yet enforced.

; Get a line of text from the console & handle it
CCP			
CCPL1		LD		A,(CURDRV)		; Get current drive & user number
			AND		0FH				; Mask out user number
			ADD		A,'A'			; Convert to letter
			LD		E,A				; Print it
			CALL	C_WRITE			; ...
			LD		E,'>'			; Print '>'
			CALL	C_WRITE			; ...
			
			LD		DE,FILEBUF		; Use FILEBUF as line buffer
			LD		A,120			; Max line length
			LD		(DE),A			; Stored in first char of buffer
			CALL	C_READSTR		; Get a line from the user
			LD		HL,FILEBUF+1	; Use actual count byte, not DE (editing clobbers E)
			CALL	UCASE			; Uppercase commands AND transient command tails

			LD		A,(FILEBUF+1)	; Number of chars entered
			CP		0 				; If none ...
			JR		Z,CCPL1			; Loop until user types something!

			; Two char built-in commands A:, B:, C: etc
			CP		2				; Check if two chars ...
			JR		NZ,CCPS1		; If not, skip
			LD		A,(FILEBUF+3)	; See if second char is ':'
			CP		':'				; ...
			JR		NZ,CCPS1		; If not, skip
			LD		A,(FILEBUF+2)	; Get the character before the ':'
			SUB		'A'				; A is 0, B is 1 etc.
			CP		16				; Valid CP/M drives A: through P:
			JP		NC,CCPBADDRV
			LD		E,A				; Set the default drive
			CALL	DRV_SET			; ...
			JP		CCPL1			; Go again

CCPBADDRV LD      DE,BFMSG
           CALL    C_WRITESTR
           JP      CCPL1
CCPS1      LD      HL,FCB1			; Clear FCB1
			LD		(DMAADDR),HL	;
			CALL	CLRFCB			;

			LD		HL,FCB2			; Clear FCB2
			LD		(DMAADDR),HL	;
			CALL	CLRFCB			;

			CALL	PARSE			; Parse the command line
			CALL	BUILTIN			; Check for built-in commands
			CP		0				; If zero, was a built-in command
			JP		Z,CCP			; Go again
			CALL	RUNCOM			; Try to run .COM file

			JP		CCP				; Go again

; Uppercase the command input (Pascal string) in place.
UCASE      LD      B,(HL)
UCL1       LD      A,B
           OR      A
           RET     Z
           INC     HL
           LD      A,(HL)
           CP      'a'
           JR      C,UCS1
           CP      'z'+1
           JR      NC,UCS1
           SUB     'a'-'A'
           LD      (HL),A
UCS1       DJNZ    UCL1
           RET

; Parse the command line
; Replaces the contents of FILEBUF with command tail as Pascal-style string
; Creates FCB for loading .COM program
; B is used to keep track of the parser state machine:
;   0 in whitespace before command
;   1 in command
;   2 in whitespace segment following command
;   3 in first argument
;   4 in whitespace segment following first argument
;   5 in second argument
;   6 in whitespace segment following second arg (or later)
PARSE		CALL	RSTPATHBUF		; Set IY and E for writing PATHBUF
			LD		HL,FILEBUF+1	; Skip first byte - buffer capacity
			PUSH	HL				; HL->IX. Use IX as dest pointer into FILEBUF
			POP		IX				; ...
			LD		D,0				; D is the count of chars for FILEBUF
			LD		B,0				; B is the state of the parser
			LD		C,(HL)			; Get the length of source string
CTL1		LD		A,C				; See if any chars are left in input
			CP		0				; ...
			JR		Z,CTS2			; If 0, go update the length byte
			INC		HL				; Advance to next char of source string
			DEC		C				; Decrement count remaining
			LD		A,(HL)			; Get char from buffer
			CP		' '				; See if it a space
			JR		Z,CTS1			; If space ...
			CALL	CMDNSPC			; Handle non-space
			JR		CTL1			; Loop
CTS1		CALL	CMDSPC			; Handle space
			JR		CTL1			; Loop
CTS2		LD		A,' '			; Fake an additional space on the end ...
			CALL	CMDSPC			; ... so parser can get itself in correct state
			LD		A,D				; Get string length of command tail
			CP		1				; If length is 1, is just a space
			JR		NZ,CTS3			; If not length 1, store length, otherwise ...
			LD		D,0				; ... Set length to zero
CTS3		LD		(IX+0),0		; CP/M command tail needs a zero terminator
								; IX points just past the generated tail.
			LD		HL,FILEBUF		; First byte is length of string
			LD		(HL),D			; Write string length (excluding zero)
			RET						;

; Helper function to reset the PATHBUF buffer pointer & character count
; PATHBUF is used to store the filename for creating an FCB
; Sets IY to point to first character to be written to PATHBUF
; Resets count of chars written E
RSTPATHBUF	PUSH	HL				; Preserve HL
			LD		HL,PATHBUF+1	; Use HL to initialize IY
			PUSH	HL				; HL->IY. Use IY as dest ptr into PATHBUF
			POP		IY				; ...
			POP		HL				; Restore original HL
			LD		E,0				; Reset count of chars in PATHBUF
			RET

; Examines Pascal string pointed to by HL to see if it begins with a drive
; letter and a colon.  If so, reduces string length by 2 and advances HL two
; positions, sets B to the drive number.  If no drive is specified, sets B
; to the default drive.
DRVLETTER	INC		HL				; Advance to second char
			INC		HL				; ...
			LD 		A,(HL)			; See if second char typed is a colon
			CP 		':'				;
			JR 		NZ,DLS1			; If not then skip to default drive
			DEC		HL				; Back to first char
			LD 		A,(HL)			; Get the drive letter
			SUB 	'A'-1			; Convert to 1-based drive number
			LD 		B,A 			; In B for NAME2FCB
			DEC		HL				; Back one to the size byte
			LD		A,(HL)			; Get the string length
			SUB		2				; Eat drive letter and colon
			INC		HL				; ...
			INC		HL				; ...
			LD		(HL),A			; Write the reduced length
			RET
DLS1		DEC		HL				; Put HL back to the beginning
			DEC		HL				; ...
			LD		A,(CURDRV)		; Get drive and user number
			AND		0FH				; Mask out user number
			INC		A				; FCB drive numbers are 1-based
			LD		B,A				; Always use default drive
			RET

; Handle the end of command/argument tokens. State B is 0..6:
; odd states 1/3/5 finish command / first / second argument.
CMDSPC     LD      A,B
           OR      A
           RET     Z               ; Leading whitespace
           CP      6
           JR      Z,SPTAIL         ; Further arguments stay in command tail
           AND     1
           RET     Z               ; Inter-argument whitespace
           LD      A,' '
           CALL    EMTFILBUF
           LD      A,E
           LD      (PATHBUF),A
           CALL    RSTPATHBUF
           PUSH    HL
           PUSH    BC
           PUSH    DE
           LD      A,B
           CP      1
           JR      Z,SPCOM
           CP      3
           JR      Z,SPFIRST
           LD      HL,FCB2
           JR      SPMKFCB
SPCOM      LD      HL,PATHBUF2
           JR      SPMKFCB
SPFIRST    LD      HL,FCB1
SPMKFCB    LD      (DMAADDR),HL
           LD      HL,PATHBUF
           CALL    DRVLETTER
           LD      C,0
           CALL    NAME2FCB
           POP     DE
           POP     BC
           POP     HL
           LD      A,B
           CP      1
           JR      NZ,SPNEXT
           LD      A,'C'
           LD      (PATHBUF2+9),A
           LD      A,'O'
           LD      (PATHBUF2+10),A
           LD      A,'M'
           LD      (PATHBUF2+11),A
SPNEXT     INC     B
           RET
SPTAIL     LD      A,' '
           JP      EMTFILBUF

; Emit non-space input byte to command and/or argument buffers.
; State transitions 0->1, 2->3, 4->5 happen on the first byte.
CMDNSPC    LD      A,B
           CP      6
           JR      Z,CNSFILE
           LD      A,(HL)
           CALL    EMTPATHBUF
           LD      A,B
           OR      A
           JR      NZ,CNSNEXT
           INC     B
           RET
CNSNEXT    CP      1
           RET     Z
           LD      A,(HL)
           CALL    EMTFILBUF
           LD      A,B
           CP      2
           JR      Z,CNSINC
           CP      4
           RET     NZ
CNSINC     INC     B
           RET
CNSFILE    LD      A,(HL)
           JP      EMTFILBUF

; Write character at A to IX (which points into FILEBUF)
; Helper for CMDSPC/CMDNSPC
EMTFILBUF	LD		(IX+0H),A		; Emit char to FILEBUF
			INC		IX				; ...
			INC		D				; Character count for FILEBUF
			RET

; Write character at A to IX (which points into PATHBUF)
; Helper for CMDNSPC
EMTPATHBUF PUSH    AF
           LD      A,E
           CP      63
           JR      NC,EPPFULL
           POP     AF
           LD      (IY+0H),A
           INC     IY
           INC     E
           RET
EPPFULL    POP     AF
           RET

; Built-ins are matched against the first five bytes of the parsed
; command FCB. Each fixed-size entry is name[5], nargs[1], handler[2].
; Bit 7 of nargs permits zero arguments as well as one (DIR).
BITABLE    DEFM    'DIR  '
           DEFB    081H
           DEFW    DIRECT
           DEFM    'ERA  '
           DEFB    1
           DEFW    ERASE
           DEFM    'REN  '
           DEFB    1
           DEFW    RENAME
           DEFM    'TYPE '
           DEFB    1
           DEFW    BITYPE
           DEFM    'SAVE '
           DEFB    2
           DEFW    BISAVE
           DEFM    'BYE  '
           DEFB    0
           DEFW    CCPBYE

; The CCP parser normalizes arguments as " arg1 arg2 ", always
; separating words by ONE space and retaining the leading/trailing space.
; Number of words = number of spaces - 1 (or 0 if tail is empty).
CCPARGC    LD      HL,FILEBUF
           LD      B,(HL)
           LD      C,0
           INC     HL
CALOOP     LD      A,B
           OR      A
           JR      Z,CADONE
           LD      A,(HL)
           CP      ' '
           JR      NZ,CANEXT
           INC     C
CANEXT     INC     HL
           DJNZ    CALOOP
CADONE     LD      A,C
           OR      A
           RET     Z
           DEC     A
           RET

CCPBAD     LD      DE,BFMSG
           CALL    C_WRITESTR
           LD      A,1
           OR      A
           RET

; Disallow ambiguous file specifications in TYPE, REN and SAVE.
; Returns A=0 for unambiguous name, nonzero for '?' anywhere.
ISWILD     LD      B,11
IWLOOP     LD      A,(HL)
           CP      '?'
           RET     Z
           INC     HL
           DJNZ    IWLOOP
           XOR     A
           RET
CCPNOWILD  CALL    ISWILD
           OR      A
           RET     Z
           JP      CCPBAD

BITYPE     LD      HL,FCB1NAM
           CALL    CCPNOWILD
           RET     NZ
           JP      TYPEFILE
BISAVE     LD      HL,FCB2NAM
           CALL    CCPNOWILD
           RET     NZ
           JP      SAVEFILE

; Single table-driven dispatcher instead of six repeated string
; comparisons. A handler is entered with a synthetic return address.
BUILTIN    LD      HL,BITABLE
           LD      C,6
BISCAN     LD      DE,PATHBUF2+1
           LD      B,5
BICMP      LD      A,(DE)
           CP      (HL)
           JR      NZ,BISKIP
           INC     DE
           INC     HL
           DJNZ    BICMP
           LD      A,(HL)
           LD      (BIREQ),A
           INC     HL
           LD      E,(HL)
           INC     HL
           LD      D,(HL)
           PUSH    DE
           CALL    CCPARGC
           LD      B,A
           LD      A,(BIREQ)
           AND     0FH
           CP      B
           JR      Z,BIRUN
           LD      A,(BIREQ)
           BIT     7,A
           JR      Z,BIFAIL
           LD      A,B
           OR      A
           JR      NZ,BIFAIL
BIRUN      POP     HL
           LD      DE,BIRETURN
           PUSH    DE
           JP      (HL)
BIRETURN   XOR     A
           RET
BIFAIL     POP     HL
           CALL    CCPBAD
           XOR     A
           RET
BISKIP     LD      E,B            ; Skip unmatched portion of 5-char key
           LD      D,0
           ADD     HL,DE
           LD      DE,3           ; nargs and jump target
           ADD     HL,DE
           DEC     C
           JR      NZ,BISCAN
           LD      A,0FFH
           RET
BIREQ      DEFB    0

; Shared confirmation reader. A=0 for Y; A=1 for N.
; Invalid input is ignored; C_READ echoes typed characters.
CCPYESNO   CALL    C_WRITESTR
CYKEY      CALL    C_READ
           AND     0DFH
           CP      'Y'
           JR      Z,CYYES
           CP      'N'
           JR      NZ,CYKEY
           LD      E,13
           CALL    C_WRITE
           LD      A,1
           RET
CYYES      LD      E,13
           CALL    C_WRITE
           XOR     A
           RET
CCPBYE     LD      DE,BYEASK
           CALL    CCPYESNO
           OR      A
           RET     NZ
           XOR     A
           LD      (CMD),A
           JP      BYERESUME      ; Stable SoftCard handoff; next start is cold
BYEASK     DEFM    'Y/N? $'

; Load and run a .COM file to 0100H
; The FCB describing the file to run is in PATHBUF2
RUNCOM		LD		DE,PATHBUF2		; Point to the FCB in PATHBUF2
			LD		HL,PATHBUF2		; Set DMAADDR to PATHBUF2 (not FILEBUF!)
			LD		(DMAADDR),HL	; ...
			CALL	_F_OPEN			;
			CP		0				;
			JP		NZ,RCOERR		; Open error
			LD		HL,0100H		; Set DMAADDR to 0100H
			LD		(DMAADDR),HL	; ...
RCL1		CALL	F_READ			; Read records until done
			LD		HL,(DMAADDR)	; Advance DMAADDR for each record
			LD		BC,80H			; ...
			ADD		HL,BC			; ...
			LD		(DMAADDR),HL	; ...
			CP		0				; Check return code from F_READ
			JR		Z,RCL1			; If zero, keep looping
			CP		1				; Check return code from F_READ
			JR		NZ,RCLERR		; If not EOF (1), then error
			CALL	F_CLOSE			; Close the file
			LD		HL,FILEBUF		; Reset DMAADDR to 0080H
			LD		(DMAADDR),HL	; ...
			LD		A,(CURDRV)		; Save CCP drive/user before transient
			PUSH	AF			; STAT may temporarily select another drive
			CALL	PROGSTRT		; Run user program at 0100H
			POP		AF			; Restore drive/user on normal return
			LD		(CURDRV),A		; Restore CCP default drive
			LD		E,13			; Print carriage return
			CALL	C_WRITE			; ...
			LD		HL,FILEBUF		; Reset DMAADDR to 0080H
			LD		(DMAADDR),HL	; ...
			RET						;
RCOERR		LD		DE,NFMSG		; 'Not found' message
			CALL	C_WRITESTR		; ...
			RET						;
RCLERR		CALL	F_CLOSE			; Close the file
			LD		HL,FILEBUF		; Reset DMAADDR to 0080H
			LD		(DMAADDR),HL	; ...
			LD		DE,REMSG		; 'Read error' message
			CALL	C_WRITESTR		; ...
			RET

NFMSG		DEFM	'Not found'
			DEFB	13,'$'

REMSG		DEFM	'I/O error'
			DEFB	13,'$'

BFMSG		DEFM	'Bad format'
			DEFB	13,'$'

RNEMSG		DEFM	'Rename error'
			DEFB	13,'$'

; Four names per line, with their drive letters. No sorting is done.
DIRECT     LD      A,(FCB1NAM)
           CP      ' '
           CALL    Z,DIRFCB
           XOR     A
           LD      (DIRCOL),A
           LD      HL,FILEBUF
           LD      (DMAADDR),HL
           LD      E,13
           CALL    C_WRITE
           LD      DE,FCB1
           CALL    F_SFIRST
           OR      A
           JR      NZ,DIRDONE
DIRLOOP    CALL    PRDIRENT
           LD      DE,FCB1
           CALL    F_SNEXT
           OR      A
           JR      Z,DIRLOOP
DIRDONE    LD      A,(DIRCOL)
           OR      A
           RET     Z
           LD      E,13
           JP      C_WRITE
DIRCOL     DEFB    0

; Set up FCB1 to search all files
; If length of command tail is zero, or length of command tail is 3
; and 3rd char is ':' then set up FCB for searching
DIRFCB     LD      A,(FILEBUF)
           CP      4
           JR      NZ,DFS1
           LD      A,(FILEBUF+3)
           CP      ':'
           JR      NZ,DFS1
           LD      A,(FILEBUF+2)
           SUB     'A'-1
           JR      DFS2
DFS1       LD      A,(CURDRV)
           AND     0FH
           INC     A

DFS2       LD      (FCB1DRV),A
           LD      HL,FCB1NAM
           LD      B,11
           LD      A,'?'
DFILL      LD      (HL),A
           INC     HL
           DJNZ    DFILL
           RET

; Print drive: plus 8.3 filename from the first 11 bytes of DMA.
; Four entries per row, 3-space separation. Existing dot retained.
PRDIRENT   LD      A,(FCB1DRV)
           DEC     A
           ADD     A,'A'
           LD      E,A
           CALL    C_WRITE
           LD      E,':'
           CALL    C_WRITE
           LD      E,' '
           CALL    C_WRITE
           LD      HL,FILEBUF+1
           LD      B,11
PRDLOOP    LD      A,B
           CP      3
           JR      NZ,PRDNODOT
           LD      E,' '
           PUSH    HL
           CALL    C_WRITE
           POP     HL
PRDNODOT   LD      E,(HL)
           PUSH    HL
           CALL    C_WRITE
           POP     HL
           INC     HL
           DJNZ    PRDLOOP
           LD      A,(DIRCOL)
           INC     A
           AND     3
           LD      (DIRCOL),A
           JR      Z,PRDNEWLINE
           LD      DE,DIRSEP
           JP      C_WRITESTR
PRDNEWLINE LD      E,13
           JP      C_WRITE
DIRSEP     DEFM    '   $'

; Wildcard ERA always asks before deleting, including ERA *.COM.
; This is deliberately safer than stock CP/M 2.2, which prompts only
; for ERA *.*. FCB1 contains the wildcard-expanded '?' characters.
ERASE      LD      HL,FCB1NAM
           CALL    ISWILD
           OR      A
           JR      Z,ERADO
           LD      DE,BYEASK
           CALL    CCPYESNO
           OR      A
           RET     NZ
ERADO      LD      HL,FILEBUF
           LD      (DMAADDR),HL
           LD      DE,FCB1
           CALL    F_DELETE
           OR      A
           RET     Z
           LD      DE,NFMSG
           JP      C_WRITESTR

; Rename a file
; Here we need to build our own 'special' FCB using the x:dest=src command line
; Maniplate the command tail to replace the leading space with char count of
; first string and the = with char count of second string.  Then use NAME2FCB
; twice to build the 'special' FCB used by F_RENAME.
RENAME		LD		HL,FILEBUF		; Command tail is in filebuf
			LD		C,(HL)			; Read length of string
			INC		C				; Makes length compare easier
			LD		B,0				; Use B to count chars
RENL1		INC		HL				; Advance to next char
			INC		B				; Increase char count
			LD		A,B				; Copy to A for compare
			CP		C				; Compare with string length
			JP		Z,RENS4			; If at end then bad format
			LD		A,(HL)			; Fetch char
			CP		'='				; See if it is equals sign
			JR		Z,RENS1			; Handle '=' sign
			JR		RENL1			; Loop
RENS1      LD      A,B               ; Get char count
           SUB     2
           JP      Z,RENS4         ; Empty destination is invalid
				; For initial space and '='
			LD		DE,FILEBUF		; Will write through ptr DE
			INC		DE				; Advance to initial space
			LD		(DE),A			; Store length of first string
			LD		(TEMPWORD),HL	; Store address of '=' sign
RENL2		INC		HL				; Advance to next char
			INC		B				; Increase char count
			LD		A,B				; Copy to A for compare
			CP		C				; Compare with string length
			JR		Z,RENS3			; If at end then jump out
			JR		RENL2			; Loop
RENS3		LD		A,B				; Get overall char count into A
			SUB		4				; Compensate for extra chars
			LD		HL,FILEBUF		; Get char count of first string
			INC		HL				; ...
			SUB		(HL)			; Subtract from char count
			LD		HL,(TEMPWORD)	; Address of '=' sign
           LD      (HL),A           ; Store length of second string
           OR      A
           JP      Z,RENS4         ; Empty source is invalid

           LD      HL,FCB2			; Set DMAADDR for destination
			LD		(DMAADDR),HL	; ...
			LD		HL,FILEBUF		; Set HL to dest file string
			INC		HL				; ...
			CALL	DRVLETTER		; Handle any x: drive letter prefix
			LD		C,0				; NAME2FCB should not do size lookup
			CALL	NAME2FCB		; Make FCB for source file

			LD		HL,FCB1			; Set DMAADDR for source
			LD		(DMAADDR),HL	; ...
			LD		HL,(TEMPWORD)	; Set HL to source file string
			LD		C,0				; NAME2FCB should not do size lookup
			CALL	NAME2FCB		; Make FCB for source file
           LD      A,(FCB2)       ; Get drive number of destination
           LD      (FCB1),A
           LD      HL,FCB1NAM     ; Neither REN filename may be ambiguous
           CALL    ISWILD
           OR      A
           JP      NZ,RENS4
           LD      HL,FCB2NAM
           CALL    ISWILD
           OR      A
           JP      NZ,RENS4

           LD      DE,FCB1			; Pass address of FCB to F_RENAME
			LD		HL,FILEBUF		; Set DMAADDR to point to FILEBUF
			LD		(DMAADDR),HL	; ...
			CALL	F_RENAME		; Perform the rename

			CP		0				; See if it was successful
			JR		NZ,RENS5		; If not, display message
			RET						;

RENS4      JP      CCPBAD
RENS5		LD		DE,RNEMSG		; 'Rename error' message
			CALL	C_WRITESTR		; ...
			RET

; Show a test file on the console
; File to open is in FCB1
TYPEFILE	LD		DE,FCB1			; Point to FCB1
			LD		HL,FILEBUF		; Set DMAADDR to FILEBUF
			LD		(DMAADDR),HL	; ...
			CALL	F_OPEN			; Open the file with wildcard search
			CP		0				;
			JR		NZ,TFOERR		; Open error
TFL1		LD		HL,FILEBUF		; Write ^Z to buffer in case 0 bytes read
			LD		A,26			; ...
			LD		(HL),A			; ...
			LD		DE,FCB1			; Point to FCB1
			CALL	F_READ			; Read records until done
			CP		0				; Check return code from F_READ
			JR		NZ,TFS1			; If non-zero jump out of loop
			CALL	TYPEBLK			; Display block on screen
			JR		TFL1			; Loop
TFS1		CP		1				; Check return code from F_READ
			JR		NZ,TFLERR		; If not EOF (1), then error
			CALL	TYPEBLK			; Display last block on screen
			CALL	F_CLOSE			; Close the file
			LD		E,13			; Carriage return
			CALL	C_WRITE			;
			RET						;
TFOERR		LD		DE,NFMSG		; 'Not found' message
			CALL	C_WRITESTR		; ...
			RET						;
TFLERR		CALL	F_CLOSE			; Close the file
			LD		DE,REMSG		; 'Read error' message
			CALL	C_WRITESTR		; ...
			RET

; Display one 128-byte CP/M record, stopping at ^Z.
; C_WRITE preserves BC and DE, so only the pointer needs protection.
TYPEBLK    LD      HL,FILEBUF
           LD      B,128
TBL1       LD      A,(HL)
           CP      26
           RET     Z
           LD      E,A
           PUSH    HL
           CALL    C_WRITE
           POP     HL
           INC     HL
           DJNZ    TBL1
           RET

; CP/M SAVE n file: n decimal 256-byte pages starting at TPA $0100.
; Each page is written as TWO 128-byte BDOS sequential records.
; Max n=128, saving up to $80FF without touching resident code at $8100.
; The second parser argument is already an FCB at FCB2.
SAVEFILE   LD      HL,FILEBUF+2   ; Decimal number begins after first space
           LD      B,0             ; Accumulated pages
SVDEC      LD      A,(HL)
           CP      ' '
           JR      Z,SVNUMBER
           SUB     '0'
           JR      C,SVBAD
           CP      10
           JR      NC,SVBAD
           LD      C,A
           LD      A,B
           CP      13            ; 13*10 exceeds 128 even with digit 0
           JR      NC,SVBAD
           ADD     A,A
           LD      D,A             ; 2*previous
           ADD     A,A
           ADD     A,A             ; 8*previous
           ADD     A,D             ; 10*previous
           ADD     A,C
           CP      129
           JR      NC,SVBAD
           LD      B,A
           INC     HL
           JR      SVDEC
SVNUMBER   LD      A,B
           LD      (SVPAGES),A
           LD      DE,FCB2
           CALL    F_MAKE
           OR      A
           JR      NZ,SVIOERR
           LD      HL,0100H
           LD      (DMAADDR),HL
SVPAGE     LD      A,(SVPAGES)
           OR      A
           JR      Z,SVCLOSE
           LD      B,2
SVRECORD   PUSH    BC
           LD      DE,FCB2
           CALL    F_WRITE
           POP     BC
           OR      A
           JR      NZ,SVWRITEERR
           LD      HL,(DMAADDR)
           LD      DE,128
           ADD     HL,DE
           LD      (DMAADDR),HL
           DJNZ    SVRECORD
           LD      A,(SVPAGES)
           DEC     A
           LD      (SVPAGES),A
           JR      SVPAGE
SVCLOSE    LD      DE,FCB2
           CALL    F_CLOSE
           OR      A
           JR      NZ,SVIOERR
SVRESET    LD      HL,FILEBUF
           LD      (DMAADDR),HL
           RET
SVWRITEERR LD      DE,FCB2
           CALL    F_CLOSE        ; Close even on an unsuccessful write
SVIOERR    LD      DE,REMSG
           CALL    C_WRITESTR
           JR      SVRESET
SVBAD      LD      DE,BFMSG
           CALL    C_WRITESTR
           JR      SVRESET
SVPAGES    DEFB    0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Additional private scratch space for BDOS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; ProDOS Parameter Lists
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Parameter list for ProDOS CREATE call
FMMLI		DEFB	20H,00H,0BFH	; JSR $BF00 in 6502 code		
			DEFB	0C0H			; ProDOS CREATE call
			DEFW	FMMLIPL+OFFSET	; Pointer to parm list in 6502 addr space
			DEFB	60H				; RTS in 6502 code
FMMLIPL		DEFB	7				; ProDOS PL: Seven parameters
FMMLIP		DEFW	PATHBUF+OFFSET	; ProDOS PL: Pointer to path in 6502 addr
FMMLIA		DEFB	0C3H			; ProDOS PL: Access (0C3H full access)
FMMLIT		DEFB	0				; ProDOS PL: File type (0 means typeless)
FMMLIAT		DEFW	0000H			; ProDOS PL: Aux file type (always 0000H)
FMMLIS		DEFB	1				; ProDOS PL: Storage type (1 for file)
FMMLICD		DEFW	0000H			; ProDOS PL: Create date (always 0000H)
FMMLICT		DEFW	0000H			; ProDOS PL: Create time (always 0000H)

; Parameter list for ProDOS DESTROY call
FDMLI		DEFB	20H,00H,0BFH	; JSR $BF00 in 6502 code		
			DEFB	0C1H			; ProDOS DESTROY call
			DEFW	FDMLIPL+OFFSET	; Pointer to parm list in 6502 addr space
			DEFB	60H				; RTS in 6502 code
FDMLIPL		DEFB	1				; ProDOS PL: Seven parameters
FDMLIP		DEFW	PATHBUF+OFFSET	; ProDOS PL: Pointer to path in 6502 addr

; Parameter list for ProDOS RENAME call
FRNMLI		DEFB	20H,00H,0BFH	; JSR $BF00 in 6502 code		
			DEFB	0C2H			; ProDOS RENAME call
			DEFW	FRNMLIPL+OFFSET	; Pointer to parm list in 6502 addr space
			DEFB	60H				; RTS in 6502 code
FRNMLIPL	DEFB	2				; ProDOS PL: Two parameters
FRNMLIP1	DEFW	PATHBUF+OFFSET	; ProDOS PL: Pointer to path in 6502 addr
FRNMLIP2	DEFW	PATHBUF2+OFFSET	; ProDOS PL: Pointer to path in 6502 addr

; Parameter list for ProDOS GET_FILE_INFO call
GFIMLI		DEFB	20H,00H,0BFH	; JSR $BF00 in 6502 code		
			DEFB	0C4H			; ProDOS GET_FILE_INFO call
			DEFW	GFIMLIPL+OFFSET	; Pointer to parm list in 6502 addr space
			DEFB	60H				; RTS in 6502 code
GFIMLIPL	DEFB	0AH				; ProDOS PL: Ten parameters
GFIMLIP		DEFW	PATHBUF+OFFSET	; ProDOS PL: Pointer to path in 6502 addr
GFIMLIAC	DEFB	0				; ProDOS PL: Access
GFIMLIT		DEFB	0				; ProDOS PL: File type
GFIMLIAT	DEFW	0000H			; ProDOS PL: Aux type
GFIMLIS		DEFB	1				; ProDOS PL: Storage type
GFIMLIBU	DEFW	0000H			; ProDOS PL: Blocks used
GFIMLIMD	DEFW	0000H			; ProDOS PL: Modification date
GFIMLIMT	DEFW	0000H			; ProDOS PL: Modification time
GFIMLICD	DEFW	0000H			; ProDOS PL: Create date
GFIMLICT	DEFW	0000H			; ProDOS PL: Create time

; Parameter list for ProDOS OPEN call
FOMLI		DEFB	20H,00H,0BFH	; JSR $BF00 in 6502 code		
			DEFB	0C8H			; ProDOS OPEN call
			DEFW	FOMLIPL+OFFSET	; Pointer to parm list in 6502 addr space
			DEFB	60H				; RTS in 6502 code
FOMLIPL		DEFB	3				; ProDOS PL: Three parameters
FOMLIP		DEFW	PATHBUF+OFFSET	; ProDOS PL: pointer to path in 6502 addr
FOMLII		DEFW	0000H			; ProDOS PL: pointer to IO buffer
FOMLIN		DEFB	0				; ProDOS PL: File reference number

; Parameter list for ProDOS READ call
FRMLI		DEFB	20H,00H,0BFH	; JSR $BF00 in 6502 code		
			DEFB	0CAH			; ProDOS READ call
			DEFW	FRMLIPL+OFFSET	; Pointer to parm list in 6502 addr space
			DEFB	60H				; RTS in 6502 code
FRMLIPL		DEFB	4				; ProDOS PL: Four parameters
FRMLIN		DEFB	0				; ProDOS PL: File reference number
FRMLIDB		DEFW	0000H			; ProDOS PL: Data buffer
FRMLIRC		DEFW	128				; ProDOS PL: Request count (bytes to read)
FRMLITC		DEFW	0000H			; ProDOS PL: Number of bytes transferred

; Parameter list for ProDOS WRITE call
FWMLI		DEFB	20H,00H,0BFH	; JSR $BF00 in 6502 code		
			DEFB	0CBH			; ProDOS WRITE call
			DEFW	FWMLIPL+OFFSET	; Pointer to parm list in 6502 addr space
			DEFB	60H				; RTS in 6502 code
FWMLIPL		DEFB	4				; ProDOS PL: Four parameters
FWMLIN		DEFB	0				; ProDOS PL: File reference number
FWMLIDB		DEFW	0000H			; ProDOS PL: Data buffer
FWMLIRC		DEFW	128				; ProDOS PL: Request count (bytes to read)
FWMLITC		DEFW	0000H			; ProDOS PL: Number of bytes transferred

; Parameter list for ProDOS CLOSE call
FCMLI		DEFB	20H,00H,0BFH	; JSR $BF00 in 6502 code		
			DEFB	0CCH			; ProDOS CLOSE call
			DEFW	FCMLIPL+OFFSET	; Pointer to parm list in 6502 addr space
			DEFB	60H				; RTS in 6502 code
FCMLIPL		DEFB	1				; ProDOS PB: One parameter
FCMLIN		DEFB	0				; ProDOS PB: File reference number

; Parameter list for ProDOS FLUSH call
FLMLI		DEFB	20H,00H,0BFH	; JSR $BF00 in 6502 code		
			DEFB	0CDH			; ProDOS FLUSH call
			DEFW	FLMLIPL+OFFSET	; Pointer to parm list in 6502 addr space
			DEFB	60H				; RTS in 6502 code
FLMLIPL		DEFB	1				; ProDOS PL: One parameter
FLMLIN		DEFB	0				; ProDOS PL: File ref num (0 = all files)

; Parameter list for ProDOS SET_MARK call
SMMLI		DEFB	20H,00H,0BFH	; JSR $BF00 in 6502 code		
			DEFB	0CEH			; ProDOS SET_MARK call
			DEFW	SMMLIPL+OFFSET	; Pointer to parm list in 6502 addr space
			DEFB	60H				; RTS in 6502 code
SMMLIPL		DEFB	2				; ProDOS PL: Two parameters
SMMLIN		DEFB	0				; ProDOS PL: File reference number
SMMLIP1		DEFB	0				; ProDOS PL: Position (LSB)
SMMLIP2		DEFB	0				; ProDOS PL: Position
SMMLIP3		DEFB	0				; ProDOS PL: Position (MSB)

; Parameter list for ProDOS SET_EOF call
SEMLI		DEFB	20H,00H,0BFH	; JSR $BF00 in 6502 code
			DEFB	0D0H			; ProDOS SET_EOF call
			DEFW	SEMLIPL+OFFSET	; Pointer to parm list in 6502 addr space
			DEFB	60H				; RTS in 6502 code
SEMLIPL		DEFB	2				; ProDOS PL: Two parameters
SEMLIN		DEFB	0				; ProDOS PL: File reference number
SEMLIE1		DEFB	0				; ProDOS PL: EOF position (LS-byte)
SEMLIE2		DEFB	0				; ProDOS PL: EOF position
SEMLIE3		DEFB	0				; ProDOS PL: EOF position (MS-byte)

; Parameter list for ProDOS GET_EOF call
GEMLI		DEFB	20H,00H,0BFH	; JSR $BF00 in 6502 code
			DEFB	0D1H			; ProDOS GET_EOF call
			DEFW	GEMLIPL+OFFSET	; Pointer to parm list in 6502 addr space
			DEFB	60H				; RTS in 6502 code
GEMLIPL		DEFB	2				; ProDOS PL: Two parameters
GEMLIN		DEFB	0				; ProDOS PL: File reference number
GEMLIE1		DEFB	0				; ProDOS PL: EOF position (LS-byte)
GEMLIE2		DEFB	0				; ProDOS PL: EOF position
GEMLIE3		DEFB	0				; ProDOS PL: EOF position (MS-byte)

; FCB used for opening ProDOS directory corresponding to drive
DFCB								; File control block for directory
DFCBDRV		DEFB	00H				; FCB Drive (0 current, 1 A:, 2 B: etc)
DFCBNAM		DEFM	'           '	; FCB filename and extension (all spaces)
DFCBEX		DEFB	00H				; FCB extent field
DFCBS1		DEFB	00H				; FCB S1 field
DFCBS2		DEFB	00H				; FCB S2 field
DFCBRC		DEFB	00H				; FCB RC field
DFCBMAP		DEFS	16				; Map of blocks in file
DFCBSR		DEFB	0				; FCB seq record number
DFCBRR		DEFB	0,0,0			; FCB rand record number

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; End of ProDOS Parameter Lists
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Drive parameter block (CP/M 2.2 format)
; See Johnson-Laird Pg 33-34
DPB			DEFW	32				; # 128 byte records per track (for Disk II)
			DEFB	4				; Block shift (2048 byte allocation blocks)
			DEFB	15			; Block mask (2048 byte allocation blocks)
			DEFB	0				; Extent mask (16K extents)
DPBDSM		DEFW	511			; 2K DSM set by V_GETFREE (up to 16382)
			DEFW	255				; # directory entries 
			DEFB	0				; Directory allocation bitmap byte 1
			DEFB	0				; Directory allocation bitmap byte 2
			DEFW	0				; Checksum vector size
			DEFW	0				; # of reserved tracks

; 2048-byte CP/M allocation vector supports up to 16384 x 2 KiB
; allocation blocks, i.e. ProDOS's 32 MiB maximum. This is synthetic
; accounting; no claim is made that these are unique physical blocks.
;
; Reuse 6502 MAIN $0800-$0FFF (Apple II text page 2 and spare RAM),
; mapped to Z80 $F800-$FFFF. The 6502 direct console uses text page 1.
; This avoids sacrificing another 2 KiB of precious Z80 TPA or colliding
; with the live ProDOS I/O buffers at Z80 $9800-$A7FF.
;
; $0800-$09FF is the temporary ProDOS block buffer and GET_PREFIX buffer;
; ON_LINE uses $0880. Consequently V_GETFREE builds the allocation map
; ONLY after the final READ_BLOCK completes. A later V_GETFREE refreshes it.
ALLOCVEC	EQU		0F800H
VOLBUF		EQU		0F800H
VLEFT		DEFW	0				; Volume blocks remaining in scan
VFREE		DEFW	0				; Number of actual free 512-byte blocks
VTOTAL		DEFW	0				; ProDOS header total blocks (800K => $0640)
VNBLOCKS	DEFW	0				; 2K blocks (800K => 400, 32MB => 16383)
VFEND		DEFW	0				; Bitmap byte for highest CP/M block
VFMASK		DEFB	0				; Bit mask at VFEND
VBUDGET	DEFW	0				; Maximum bits available (excl 0..8)
VERR		DEFB	0				; Last ProDOS error, $FE if header invalid

; GET_PREFIX (ProDOS $C7). Returns Pascal absolute path in $0800.
VPMLI		DEFB	20H,00H,0BFH
			DEFB	0C7H
			DEFW	VPPL+OFFSET
			DEFB	60H
VPPL		DEFB	1
			DEFW	0800H

; ON_LINE (ProDOS $C5), unit=0 enumerates mounted devices.
; 256-byte list at $0880, well away from the 64-byte prefix at $0800.
VOMLI		DEFB	20H,00H,0BFH
			DEFB	0C5H
			DEFW	VOPL+OFFSET
			DEFB	60H
VOPL		DEFB	2
			DEFB	0			; 0 = enumerate all units
			DEFW	0880H

; GET_FILE_INFO (ProDOS $C4), only for the no-prefix fallback.
; The temporary absolute pathname lives at $0800.
VFMLI		DEFB	20H,00H,0BFH
			DEFB	0C4H
			DEFW	VFPL+OFFSET
			DEFB	60H
VFPL		DEFB	0AH
			DEFW	0800H
			DEFB	0			; Access returned
VFTYPE		DEFB	0			; File type returned ($0F = DIR)
			DEFS	13			; Remaining GET_FILE_INFO fields

V_HASPFX	DEFB	0
V_NAMELEN	DEFB	0

; ProDOS READ_BLOCK call, read-only, used to inspect volume bitmap.
VRMLI		DEFB	20H,00H,0BFH	; JSR $BF00
			DEFB	080H			; ProDOS READ_BLOCK
			DEFW	VRPL+OFFSET
			DEFB	60H				; RTS
VRPL		DEFB	3
VRUNIT		DEFB	0			; Populated by V_FINDUNIT at each free-space query
			DEFW	0800H			; physical 6502 address (NOT VOLBUF+OFFSET)
VRBLK		DEFW	0				; Requested ProDOS 512-byte block

; 64 byte buffer for storing a file path as a Pascal style string
PATHBUF
PATHLEN		DEFB	0
PATH		DEFS	64

; 64 byte buffer for storing a second file path as a Pascal style string
PATHBUF2
PATHLEN2	DEFB	0
PATH2		DEFS	64

; Record file reference numbers for each I/O buffer
; Or 0 if no file is using the buffer
FRN1		DEFB	0
FRN2		DEFB	0
FRN3		DEFB	0
FRN4		DEFB	0

; 512 byte buffer for reading directories (used by F_SFIRST and F_SNEXT)
DIRBUF
DIRBUF1		DEFS	128
DIRBUF2		DEFS	128
DIRBUF3		DEFS	128
DIRBUF4		DEFS	128

; Two 1024 byte ProDOS I/O buffers, 1K spare, then the 1K Z80 stack
; The two I/O buffers start on page boundaries
; ProDOS occupies the space from $BF00 up (in 6502 addresses)
; 6502 code is loaded at $B800 for now
; RAM $A400-$A7FF is reserved for Z80 stack, not file I/O.


			;ORG		9000H	; Try this - WORKS
			ORG		9800H	; Try this - WORKS
IOBUF1		DEFS	1024
IOBUF2		DEFS	1024
; Put the read completion shim in the otherwise spare $A000-$A3FF area.
; It cannot overlap ProDOS buffers or the dedicated $A400-$A7FF stack.
; Keeping it here actually saves 6 bytes in the crowded resident area.
IOFREE
; Both F_READ and F_READRAND use this helper after SET_MARK succeeds.
; ProDOS READ sets FRMLITC even if EOF is reached before 128 bytes.
; $4C is EOF only when the transfer count is zero; a short read returns
; success and must be padded in the CP/M DMA buffer, not on disk.
; Return ProDOS status unchanged for errors other than $4C;
; otherwise return 0 if 1..128 bytes were read and $4C if none.
READ128		XOR		A
			LD		(FRMLITC),A	; No stale transfer count on error
			LD		(FRMLITC+1),A
			LD		HL,FRMLI
			CALL	PRODOS
			OR		A
			JR		Z,R128_COUNT
			CP		04CH
			RET		NZ		; Preserve bad FRN / other error
R128_COUNT	LD		A,(FRMLITC+1)
			OR		A			; 128 requested: high byte must be 0
			JR		NZ,R128_BAD
			LD		A,(FRMLITC)
			OR		A
			JR		Z,R128_EOF
			CP		128
			JR		Z,R128_OK
			JR		NC,R128_BAD	; ProDOS cannot return >128 bytes
			LD		C,A			; Bytes read (1..127)
			LD		B,0
			LD		HL,(DMAADDR)
			ADD		HL,BC		; First unfilled byte
			LD		A,128
			SUB		C
			LD		B,A			; Number of bytes to pad (1..127)
			LD		A,01AH		; CP/M text EOF marker (^Z)
R128_FILL	LD		(HL),A
			INC		HL
			DJNZ	R128_FILL
R128_OK	XOR		A
			RET
R128_EOF	LD		A,04CH
			RET
R128_BAD	LD		A,0FFH
			RET

; ProDOS's F_SFIRST/F_SNEXT leave the directory open between matches.
; Once exhausted, release its physical ProDOS handle and associated 1K
; OPEN buffer. The caller's DMA address and wildcard FCB are unchanged.
; On an already-closed/failed OPEN, F_CLOSE is harmless (DFCB S2=0).
; Keep this helper in the spare region rather than crowding $9800.
SEARCH_EOF	LD		DE,DFCB
			CALL	F_CLOSE
			LD		A,0FFH		; CP/M search: no more entries
			LD		L,A			; Also return error in L
			RET

			ORG		0A400H
; Dedicated stack: the live directory buffer ends at ~$97F2.
; Z80 SP=$A800, grows down into $A400-$A7FF, not DIRBUF.
; This intentionally limits simultaneously open ProDOS files to two.
Z80STACK	DEFS	1024

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

