; WGET.COM v0.3 for Zapple-II (Apple //e, Z80 SoftCard)
; Progress: one initial dot, then one per 1024 payload bytes flushed.
; HTTP/1.0 downloader using resident BDOS F9/FA/FB/FC networking.
; Usage: WGET (prompts for case-sensitive URL and output filename)
; IPv4 A-record DNS for hostname; no TLS, redirects or HTTP chunking.
; Downloads are written as 128-byte CP/M sequential records. Last record
; is padded with Ctrl-Z (1Ah). Do not overwrite existing files.
; Udo Munk Z80ASM dialect. All labels <= 8 chars, no ';' inside strings.

BDOS    EQU 0005H
        ORG 0100H
START   LD SP,STKTOP
        LD DE,BANNER
        CALL PRINT
        CALL ASKARGS
        JP C,EXIT
        CALL URLPAR
        JP C,BADURL
        CALL FPAR
        JP C,BADNAME
        CALL CHECKEX
        JP C,EXISTS
        CALL NETALOC
        JP C,NOSOCK
        CALL SETTCP
        JP C,FAIL
        CALL OPENCON
        JP C,FAIL
        CALL REQHTTP
        JP C,FAIL
        CALL RECEIVE
        JP C,FAIL
        CALL FINISH
        JP C,FAIL
        LD DE,CRLF
        CALL PRINT
        LD DE,DONE
        CALL PRINT
        JP EXIT
BADURL  LD DE,ERRURL
        JP ERROR
BADNAME LD DE,ERRNAME
        JP ERROR
EXISTS  LD DE,ERRXST
        JP ERROR
NOSOCK  LD DE,ERRSOCK
        JP ERROR
FAIL    LD DE,ERRFAIL
ERROR   CALL PRINT
EXIT    CALL FCLOSE
        CALL NETFREE
        LD C,0
        JP BDOS

PRINT   LD C,9
        JP BDOS
; A=byte, display as 2 hex digits (for HTTP diagnostic count)
HEXBYTE PUSH AF
        RRCA
        RRCA
        RRCA
        RRCA
        CALL NIBBLE
        POP AF
NIBBLE  AND 0FH
        ADD A,'0'
        CP '9'+1
        JR C,HEXCHR
        ADD A,7
HEXCHR  LD E,A
        LD C,2
        JP BDOS

; CP/M 2.2 uppercases the command tail. Reading from BDOS console input
; instead preserves the case of URL paths (and the Host header).
; Prompt for both parameters; FPAR still converts the 8.3 filename to uppercase.
ASKARGS LD DE,URLASK
        CALL PRINT
        LD HL,CMDTXT
        LD B,127                   ; 128-byte buffer incl. NUL
        CALL READLN
        JR C,URLTOOL
        LD HL,CMDTXT
        CALL SKIPSP
        LD A,(HL)
        OR A
        JR Z,ASKARGS
        CALL UPPER
        CP 'Q'
        JR NZ,URLSET
        INC HL
        LD A,(HL)
        OR A
        JR Z,ASKQUIT
        DEC HL
URLSET  LD (URLPTR),HL
NAMEASK LD DE,OUTASK
        CALL PRINT
        LD HL,OUTTXT
        LD B,15                    ; 16-byte buffer incl. NUL
        CALL READLN
        JR C,NAMETOOL
        LD HL,OUTTXT
        CALL SKIPSP
        LD A,(HL)
        OR A
        JR Z,NAMEASK
        LD (OUTPTR),HL
        OR A                       ; success, carry clear
        RET
URLTOOL LD DE,URLLONG
        CALL PRINT
        JR ASKARGS
NAMETOOL LD DE,NAMLONG
        CALL PRINT
        JR NAMEASK
ASKQUIT SCF
        RET

; BDOS 1 returns raw console characters with echo, not CCP tail folding.
; HL = buffer, B = maximum accepted characters. Consume the entire line,
; including on overflow, so leftover characters never become the next URL.
; Returns carry set if truncated, otherwise NUL-terminated input.
READLN  LD A,B
        LD (RDLIM),A
        XOR A
        LD (RDLONG),A
RDLOOP  PUSH BC
        PUSH HL
        LD C,1
        CALL BDOS
        POP HL
        POP BC
        CP 13
        JR Z,RDDONE
        CP 8
        JR Z,RDBACK
        CP 127
        JR Z,RDBACK
        CP 32
        JR C,RDLOOP
        LD D,A
        LD A,B
        OR A
        JR Z,RDOVFL
        LD A,D
        LD (HL),A
        INC HL
        DEC B
        JR RDLOOP
RDOVFL  LD A,1
        LD (RDLONG),A
        JR RDLOOP
RDBACK  LD A,(RDLIM)
        CP B
        JR Z,RDLOOP             ; backspace at start
        DEC HL
        INC B
        JR RDLOOP
RDDONE  LD (HL),0
        LD DE,CRLF
        CALL PRINT
        LD A,(RDLONG)
        OR A                    ; clears carry when no overflow
        RET Z
        SCF
        RET
SKIPSP  LD A,(HL)
        CP ' '
        JR Z,SKIP1
        CP 9
        RET NZ
SKIP1   INC HL
        JR SKIPSP

; Parse http://host-or-IP[:port]/path, retaining original Host: header.
; Resolve hostnames using the resident DNS setting before opening TCP.
URLPAR  LD HL,(URLPTR)
        LD DE,PREFIX
URLPRE  LD A,(DE)
        OR A
        JR Z,PREOK
        LD B,A
        LD A,(HL)
        CALL UPPER
        CP B
        JP NZ,URLBAD
        INC HL
        INC DE
        JR URLPRE
PREOK   LD (HOSTPT),HL
        LD DE,HOSTNAM
        LD B,63
UHLOOP  LD A,(HL)
        OR A
        JP Z,URLBAD
        CP ':'
        JR Z,UHDONE
        CP '/'
        JR Z,UHDONE
        CP 33                  ; no spaces or controls
        JP C,URLBAD
        LD (DE),A
        INC HL
        INC DE
        DJNZ UHLOOP
        JP URLBAD              ; hostname too long
UHDONE  LD A,B
        CP 63
        JP Z,URLBAD            ; empty host
        XOR A
        LD (DE),A
        LD A,(HL)
        CP ':'
        JR NZ,PORTEND
        INC HL
        CALL GETPORT
        JP C,URLBAD
PORTEND LD A,(HL)
        CP '/'
        JP NZ,URLBAD
        LD (PATHPT),HL
        ; HTTP Host: must include :port if supplied; use original URL.
        LD HL,(HOSTPT)
        LD DE,HOSTTX
        LD B,69
HOSTCP  LD A,(HL)
        CP '/'
        JR Z,HOSTEND
        OR A
        JP Z,URLBAD
        LD (DE),A
        INC HL
        INC DE
        DJNZ HOSTCP
        JP URLBAD
HOSTEND XOR A
        LD (DE),A
        CALL NUMIP
        RET NC                ; numeric IPv4: no DNS query needed
        CALL DNSINIT
        LD HL,HOSTNAM
        CALL DNRSLV
        JP C,URLBAD
        EX DE,HL
        LD DE,HOSTIP
        LD BC,4
        LDIR
        OR A
        RET
URLBAD  SCF
        RET

; Try parsing the entire host as dotted decimal IPv4.
; Non-numeric hosts are resolved by DNSLIB instead.
NUMIP   LD HL,HOSTNAM
        LD DE,HOSTIP
        LD B,4
NIPLP   PUSH BC
        PUSH DE
        CALL OCTET
        POP DE
        POP BC
        JR C,NIPBAD
        LD (DE),A
        INC DE
        DEC B
        JR Z,NIPEND
        LD A,(HL)
        CP '.'
        JR NZ,NIPBAD
        INC HL
        JR NIPLP
NIPEND  LD A,(HL)
        OR A
        JR NZ,NIPBAD
        OR A
        RET
NIPBAD  SCF
        RET

; Input HL->digits, return A=octet, HL->delimiter.
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
; Input HL->digits ending '/', store big-endian DPORT.
GETPORT EX DE,HL
        LD HL,0
        LD A,0
        LD (PNDIG),A
PORTLP  LD A,(DE)
        CP '0'
        JR C,PORTDN
        CP '9'+1
        JR NC,PORTDN
        SUB '0'
        LD (PDIG),A
        PUSH DE
        LD D,H
        LD E,L
        ADD HL,HL
        JR C,PORTOF
        ADD HL,HL
        JR C,PORTOF
        ADD HL,HL
        JR C,PORTOF
        ADD HL,DE
        JR C,PORTOF
        ADD HL,DE
        JR C,PORTOF
        LD A,(PDIG)
        LD E,A
        LD D,0
        ADD HL,DE
        JR C,PORTOF
        POP DE
        INC DE
        LD A,(PNDIG)
        INC A
        LD (PNDIG),A
        CP 6
        JR NC,PORTERR
        JR PORTLP
PORTOF  POP DE
PORTERR SCF
        RET
PORTDN  LD A,(PNDIG)
        OR A
        JR Z,PORTERR
        LD A,H
        OR L
        JR Z,PORTERR
        LD A,H
        LD (DPORT),A
        LD A,L
        LD (DPORT+1),A
        EX DE,HL
        OR A
        RET
UPPER   CP 'a'
        RET C
        CP 'z'+1
        RET NC
        SUB 32
        RET

; CP/M FCB: initialize ALL 36 bytes before filling the name.
; DEFS is not guaranteed to contain zero at runtime. In particular,
; byte 0 must be zero (default drive) before BDOS MAKE/WRITE checks R/O.
; EX/S1/S2/RC/CR/R0-R2 must not inherit stale AUX TPA contents.
FPAR    LD HL,FCB
        LD B,36
        XOR A
FZLOOP  LD (HL),A
        INC HL
        DJNZ FZLOOP
        LD HL,FCB+1
        LD B,11
FILLSP  LD (HL),' '
        INC HL
        DJNZ FILLSP
        LD HL,(OUTPTR)
        LD DE,FCB+1
        LD B,8
        LD C,0
FPNAME  LD A,(HL)
        OR A
        JR Z,FPNDONE
        CP '.'
        JR Z,FPEXT
        CALL FILCHR
        JR C,FPERR
        LD A,B
        OR A
        JR Z,FPERR
        LD A,(HL)
        CALL UPPER
        LD (DE),A
        INC DE
        INC HL
        DEC B
        INC C
        JR FPNAME
FPEXT   LD A,C
        OR A
        JR Z,FPERR
        INC HL
        LD DE,FCB+9
        LD B,3
FPXLP   LD A,(HL)
        OR A
        JR Z,FPOK
        CP '.'
        JR Z,FPERR
        CALL FILCHR
        JR C,FPERR
        LD A,B
        OR A
        JR Z,FPERR
        LD A,(HL)
        CALL UPPER
        LD (DE),A
        INC DE
        INC HL
        DEC B
        JR FPXLP
FPNDONE LD A,C
        OR A
        JR Z,FPERR
FPOK    OR A
        RET
FPERR   SCF
        RET
; Accept simple safe filename chars A-Z 0-9 _ - $.
FILCHR  CALL UPPER
        CP 'A'
        JR C,FCNUM
        CP 'Z'+1
        JR C,FCOK
FCNUM   CP '0'
        JR C,FCSP
        CP '9'+1
        JR C,FCOK
FCSP    CP '_'
        JR Z,FCOK
        CP '-'
        JR Z,FCOK
        CP '$'
        JR Z,FCOK
        SCF
        RET
FCOK    OR A
        RET
; Avoid overwriting existing files.
CHECKEX LD DE,FCB
        LD C,15
        CALL BDOS
        CP 0FFH
        JR Z,NEXIST
        LD DE,FCB
        LD C,16
        CALL BDOS
        SCF
        RET
NEXIST  OR A
        RET

; Network ownership from Phase 3/4: FA allocate/free.
NETALOC LD E,0
        LD C,0FAH
        CALL BDOS
        CP 4
        JR NC,ALFAIL
        LD (SOCKNO),A
        LD D,A
        ADD A,4
        LD (SOCKHI),A
        LD A,1
        LD (HELD),A
        LD DE,SOCKMSG
        CALL PRINT
        LD A,(SOCKNO)
        CALL HEXBYTE
        LD DE,CRLF
        CALL PRINT
        OR A
        RET
ALFAIL  SCF
        RET
NETFREE LD A,(HELD)
        OR A
        RET Z
        XOR A
        LD (HELD),A
        LD A,(SOCKNO)
        LD D,A
        LD E,1
        LD C,0FAH
        CALL BDOS
        RET

; F9: three-byte MAIN-to-6502 bridge writes W5100 address/value.
; B=selected socket register offset, A=value.
WSET    LD (WVAL),A
        LD A,(SOCKHI)
        LD (WPAR),A
        LD A,B
        LD (WPAR+1),A
        LD DE,WPAR
        LD C,0F9H
        CALL BDOS
        RET
; Set TCP mode, source port, destination IP/port. Reassert mode.
SETTCP  LD B,0
        LD A,1
        CALL WSET
        LD B,4
        LD A,0C0H
        CALL WSET
        LD B,5
        LD A,(SOCKNO)
        ADD A,0DEH
        CALL WSET
        LD B,0CH
        LD A,(HOSTIP)
        CALL WSET
        LD B,0DH
        LD A,(HOSTIP+1)
        CALL WSET
        LD B,0EH
        LD A,(HOSTIP+2)
        CALL WSET
        LD B,0FH
        LD A,(HOSTIP+3)
        CALL WSET
        LD B,10H
        LD A,(DPORT)
        CALL WSET
        LD B,11H
        LD A,(DPORT+1)
        CALL WSET
        LD B,0
        LD A,1
        CALL WSET
        OR A
        RET
; FB: D=socket E=operation, A=00 success (E=0 returns SR).
FBGET   LD A,(SOCKNO)
        LD D,A
        LD E,0
        LD C,0FBH
        CALL BDOS
        RET
FBCMD   LD D,A
        LD A,(SOCKNO)
        LD D,A
        LD C,0FBH
        CALL BDOS
        RET
OPENCON LD E,1
        CALL FBCMD
        CP 0FFH
        JR Z,NFATAL
        CALL FBGET
        CP 013H
        JR NZ,NFATAL
        LD E,4
        CALL FBCMD
        CP 0FFH
        JR Z,NFATAL
        LD HL,30000
CNWAIT  PUSH HL
        CALL FBGET
        POP HL
        CP 017H
        JR Z,CONOK
        CP 000H
        JR Z,NFATAL
        CP 01CH
        JR Z,NFATAL
        DEC HL
        LD A,H
        OR L
        JR Z,NFATAL
        LD A,L
        OR A
        JR NZ,CNWAIT
        PUSH HL
        LD C,11
        CALL BDOS
        POP HL
        JR CNWAIT
CONOK   OR A
        RET
NFATAL  SCF
        RET

; TCP transmit data via FC, up to 16 bytes, retry would-block.
; SENDSTR HL=NUL-terminated string. Uses a retry bound and yields.
SENDSTR LD (SPTR),HL
SSTRLP LD HL,(SPTR)
        LD A,(HL)
        OR A
        RET Z
        LD DE,TXBUF
        LD B,16
SCPY    LD A,(HL)
        OR A
        JR Z,SCEND
        LD (DE),A
        INC HL
        INC DE
        DJNZ SCPY
SCEND   LD A,16
        SUB B
        LD (SLEN),A
        LD HL,10000
        LD (SWAIT),HL
SRETRY  LD A,(SOCKNO)
        LD (NXP),A
        XOR A
        LD (NXP+1),A
        LD A,(SLEN)
        LD (NXP+2),A
        LD HL,TXBUF
        LD (NXP+3),HL
        LD DE,NXP
        LD C,0FCH
        CALL BDOS
        CP 0FFH
        JR Z,SDERR
        OR A
        JR Z,SWAIT0
        LD B,A
        LD A,(SLEN)
        CP B
        JR NZ,SDERR
        LD HL,(SPTR)
        LD E,A
        LD D,0
        ADD HL,DE
        LD (SPTR),HL
        JR SSTRLP
SWAIT0  LD HL,(SWAIT)
        DEC HL
        LD (SWAIT),HL
        LD A,H
        OR L
        JR Z,SDERR
        LD C,11
        CALL BDOS
        JR SRETRY
SDERR   SCF
        RET
REQHTTP LD HL,REQGET
        CALL SENDSTR
        RET C
        LD HL,(PATHPT)
        CALL SENDSTR
        RET C
        LD HL,REQVER
        CALL SENDSTR
        RET C
        LD HL,HOSTTX
        CALL SENDSTR
        RET C
        LD HL,REQTAIL
        JP SENDSTR

; Receive in batches of 16. HTTP/1.0 headers are discarded; 200 only.
RECEIVE LD HL,30000
        LD (IDLE),HL
RXLOOP  LD A,(SOCKNO)
        LD (NXP),A
        LD A,1
        LD (NXP+1),A
        LD A,16
        LD (NXP+2),A
        LD HL,RXBUF
        LD (NXP+3),HL
        LD DE,NXP
        LD C,0FCH
        CALL BDOS
        CP 0FFH
        JR Z,RXERR
        OR A
        JR Z,RXIDLE
        LD B,A
        LD HL,30000
        LD (IDLE),HL
        LD HL,RXBUF
RXEACH  LD A,(HL)
        PUSH HL
        PUSH BC
        CALL PROCESS
        POP BC
        POP HL
        JR C,RXERR
        INC HL
        DJNZ RXEACH
        JR RXLOOP
RXIDLE CALL FBGET
        CP 01CH
        JR Z,RXEOF
        CP 0
        JR Z,RXEOF
        CP 017H
        JR NZ,RXERR
        LD HL,(IDLE)
        DEC HL
        LD (IDLE),HL
        LD A,H
        OR L
        JR Z,RXERR
        LD C,11
        CALL BDOS
        JR RXLOOP
RXEOF   LD A,(HEADER)
        OR A
        JR NZ,RXERR
        OR A
        RET
RXERR   SCF
        RET
; Streaming header parser stores first 15 bytes of each line only.
PROCESS LD E,A
        LD A,(HEADER)
        OR A
        JR Z,BODBYTE
        LD A,E
        CP 13
        JR Z,PROCOK
        CP 10
        JR Z,LINEDN
        LD A,(LPOS)
        CP 15
        JR NC,PROCOK
        LD L,A
        LD H,0
        LD BC,LINEBUF
        ADD HL,BC
        LD (HL),E
        LD A,(LPOS)
        INC A
        LD (LPOS),A
PROCOK  OR A
        RET
LINEDN  LD A,(FIRST)
        OR A
        JR Z,NOTFST
        XOR A
        LD (FIRST),A
        LD A,(LPOS)
        CP 12
        JR C,BADHTTP
        LD HL,LINEBUF
        LD A,(HL)
        CP 'H'
        JR NZ,BADHTTP
        LD A,(LINEBUF+1)
        CP 'T'
        JR NZ,BADHTTP
        LD A,(LINEBUF+5)
        CP '1'
        JR NZ,BADHTTP
        LD A,(LINEBUF+9)
        CP '2'
        JR NZ,BADHTTP
        LD A,(LINEBUF+10)
        CP '0'
        JR NZ,BADHTTP
        LD A,(LINEBUF+11)
        CP '0'
        JR NZ,BADHTTP
LINRESET XOR A
        LD (LPOS),A
        RET
NOTFST  LD A,(LPOS)
        OR A
        JR NZ,LINRESET
        CALL FCREATE
        RET C
        XOR A
        LD (HEADER),A
        LD (LPOS),A
        RET
BADHTTP LD DE,ERRHTTP
        CALL PRINT
        SCF
        RET
BODBYTE LD A,E
        JP SAVECHR
; Create destination only after HTTP status 200 and blank header line.
FCREATE LD DE,FCB
        LD C,22
        CALL BDOS
        CP 0FFH
        JP Z,DOSERR
        LD A,1
        LD (FOPEN),A
        LD DE,FILEBUF
        LD C,26
        CALL BDOS
        LD DE,PROGMSG
        CALL PRINT
        LD A,1
        LD (PRGCOL),A
        LD E,'.'               ; show progress even for tiny files
        LD C,2
        CALL BDOS
        OR A
        RET
; Save byte to CP/M 128-byte DMA record, flush on full.
SAVECHR LD (SAVEB),A
        LD A,(FIDX)
        LD E,A
        LD D,0
        LD HL,FILEBUF
        ADD HL,DE
        LD A,(SAVEB)
        LD (HL),A
        LD HL,NBYTES
        INC (HL)
        JR NZ,BYTEDN
        INC HL
        INC (HL)
        JR NZ,BYTEDN
        INC HL
        INC (HL)
        JR NZ,BYTEDN
        INC HL
        INC (HL)
BYTEDN  LD A,(FIDX)
        INC A
        LD (FIDX),A
        CP 128
        JR NZ,SVOK
        CALL WRRECORD
        RET C
        XOR A
        LD (FIDX),A
        LD A,(NBYTES)        ; 1 KiB requires low 10 bits to be zero
        OR A
        JR NZ,SVOK
        LD A,(NBYTES+1)
        AND 03H
        JR NZ,SVOK
        CALL PRGDOT
SVOK    OR A
        RET
; Only call this after every 1 KiB successfully written to disk.
; Keep output sparse on the Apple //e console (max 64 dots/line).
PRGDOT  LD E,'.'
        LD C,2
        CALL BDOS
        LD A,(PRGCOL)
        INC A
        LD (PRGCOL),A
        CP 64
        RET NZ
        XOR A
        LD (PRGCOL),A
        LD DE,CRLF
        CALL PRINT
        RET
WRRECORD LD DE,FILEBUF
        LD C,26
        CALL BDOS
        LD DE,FCB
        LD C,21
        CALL BDOS
        OR A
        RET Z
DOSERR  SCF
        RET
; Last partial record: pad with CP/M EOF, flush, then CLOSE.
FINISH  LD A,(FIDX)
        OR A
        JR Z,FINALCL
        LD B,A
        LD HL,FILEBUF
        LD E,A
        LD D,0
        ADD HL,DE
PADLP   LD (HL),01AH
        INC HL
        INC B
        LD A,B
        CP 128
        JR NZ,PADLP
        CALL WRRECORD
        RET C
FINALCL LD DE,FCB
        LD C,16
        CALL BDOS
        CP 0FFH
        JP Z,DOSERR
        XOR A
        LD (FOPEN),A
        RET
FCLOSE  LD A,(FOPEN)
        OR A
        RET Z
        LD DE,FCB
        LD C,16
        CALL BDOS
        XOR A
        LD (FOPEN),A
        RET

BANNER  DEFM 'Zapple-II WGET v0.3'
        DEFB 13,10,'$'
URLASK  DEFM 'URL (Q quits)> $'
OUTASK  DEFM 'Save as (8.3 filename)> $'
URLLONG DEFM 'URL too long (max 127 chars)'
        DEFB 13,10,'$'
NAMLONG DEFM 'Filename too long (max 15 chars)'
        DEFB 13,10,'$'
ERRURL  DEFM 'Invalid URL or DNS lookup failed (http:// only)'
        DEFB 13,10,'$'
ERRNAME DEFM 'Invalid CP/M 8.3 output filename'
        DEFB 13,10,'$'
ERRXST  DEFM 'File exists, not overwritten'
        DEFB 13,10,'$'
ERRSOCK DEFM 'No free TCP socket'
        DEFB 13,10,'$'
ERRHTTP DEFM 'HTTP status not 200, no file created'
        DEFB 13,10,'$'
ERRFAIL DEFM 'Transfer error or timeout (partial file may remain)'
        DEFB 13,10,'$'
PROGMSG DEFM 'Receiving: $'
SOCKMSG DEFM 'Socket $'
CRLF    DEFB 13,10,'$'
DONE    DEFM 'Transfer complete'
        DEFB 13,10,'$'
PREFIX  DEFM 'HTTP://'
        DEFB 0
REQGET  DEFM 'GET '
        DEFB 0
REQVER  DEFM ' HTTP/1.0'
        DEFB 13,10
        DEFM 'Host: '
        DEFB 0
REQTAIL DEFB 13,10
        DEFM 'Connection: close'
        DEFB 13,10
        DEFM 'Accept: */*'
        DEFB 13,10,13,10,0
CMDTXT  DEFS 128
OUTTXT  DEFS 16
RDLIM   DEFB 0
RDLONG  DEFB 0
URLPTR  DEFW 0
OUTPTR  DEFW 0
HOSTPT  DEFW 0
PATHPT  DEFW 0
HOSTIP  DEFS 4
HOSTNAM DEFS 64
HOSTTX  DEFS 70
DPORT   DEFB 0,80
PNDIG   DEFB 0
PDIG    DEFB 0
FCB     DEFS 36
FILEBUF DEFS 128
FIDX    DEFB 0
FOPEN   DEFB 0
SAVEB   DEFB 0
NBYTES  DEFS 4
PRGCOL  DEFB 0
SOCKNO  DEFB 0
SOCKHI  DEFB 0
HELD    DEFB 0
WPAR    DEFB 0,0
WVAL    DEFB 0
NXP     DEFS 5
TXBUF   DEFS 16
RXBUF   DEFS 16
SPTR    DEFW 0
SLEN    DEFB 0
SWAIT   DEFW 0
IDLE    DEFW 0
HEADER  DEFB 1
FIRST   DEFB 1
LPOS    DEFB 0
LINEBUF DEFS 16
; Obtain the shared runtime DNS address configured by IPCONFIG.
; FD: E=6, D=octet index 0..3, A=octet value on return.
DNSINIT LD D,0
        LD HL,DNSIP
DNILP   PUSH HL
        PUSH DE
        LD E,6
        LD C,0FDH
        CALL BDOS
        POP DE
        POP HL
        LD (HL),A
        INC HL
        INC D
        LD A,D
        CP 4
        JR NZ,DNILP
        RET

; ==== Hardware-proven DNSLIB embedded for single-source assembly ====
; DNSLIB.ASM - Zapple-II Phase 5A reusable DNS A-record resolver.
; Source derived from working NSLOOKUP.COM 0.1 UDP query/ring/parser.
; Public: DNRSLV: HL->NUL-terminated hostname; returns carry clear and
;         DE->DNSADDR (4-byte IPv4) on success, carry set on failure.
;         DNSIP = four-byte DNS server address (default 1.1.1.1).
; Uses BDOS FA (extra UDP socket), FB (W5100 commands), F9 (write bridge).
; All module labels <=8 chars. Slot 5, like existing kernel F9 bridge.
; Designed for direct insertion before application data / stack.
;
DNRSLV  LD (DNHOSTPT),HL
        XOR A
        LD (DNHELD),A
        LD (DNFOUND),A
        CALL DNMAKEQ
        JP C,DNRFAIL
        CALL DNSETPOR
        CALL DNPICK
        JP C,DNRFAIL
        CALL DNUDPOPE
        JP C,DNRFAIL
        CALL DNTXDNS
        JP C,DNRFAIL
        CALL DNRXDNS
        JP C,DNRFAIL
        CALL DNPARSE
        JP C,DNRFAIL
        LD A,(DNFOUND)
        OR A
        JP Z,DNRFAIL
        CALL DNRELEAS
        LD DE,DNSADDR
        OR A
        RET
DNRFAIL CALL DNRELEAS
        SCF
        RET

; DNS header 5AA5 flags 0100 (recursion desired), one A/IN question.
; DEFS is not necessarily zero! Every transmitted byte is written.
DNMAKEQ   LD HL,DNQHEAD
        LD DE,DNQBUF
        LD BC,12
        LDIR
        LD A,12
        LD (DNQCNT),A
        LD HL,(DNHOSTPT)
        LD (DNQSPTR),HL
        LD DE,DNQBUF+12
        CALL DNNEWLAB
DNQLOOP   LD HL,(DNQSPTR)
        LD A,(HL)
        OR A
        JR Z,DNQEND
        CP '.'
        JR Z,DNQDOT
        CP 'A'
        JR C,DNQLOW
        CP 'Z'+1
        JR NC,DNQLOW
        ADD A,32
DNQLOW    CP 'a'
        JR C,DNQDIG
        CP 'z'+1
        JR C,DNQCHAR
DNQDIG    CP '0'
        JR C,DNQDASH
        CP '9'+1
        JR C,DNQCHAR
DNQDASH   CP '-'
        JR NZ,DNQBAD
DNQCHAR   LD B,A
        LD A,(DNQLABL)
        INC A
        CP 64
        JR NC,DNQBAD
        LD (DNQLABL),A
        LD A,B
        CALL DNQPUT
        LD HL,(DNQSPTR)
        INC HL
        LD (DNQSPTR),HL
        JR DNQLOOP
DNQDOT    CALL DNENDLAB
        JR C,DNQBAD
        LD HL,(DNQSPTR)
        INC HL
        LD (DNQSPTR),HL
        LD A,(HL)
        OR A
        JR Z,DNQFIN
        CALL DNNEWLAB
        JR DNQLOOP
DNQEND    CALL DNENDLAB
        JR C,DNQBAD
DNQFIN    XOR A
        CALL DNQPUT
        XOR A
        CALL DNQPUT
        LD A,1
        CALL DNQPUT
        XOR A
        CALL DNQPUT
        LD A,1
        CALL DNQPUT
        OR A
        RET
DNQBAD    SCF
        RET
DNNEWLAB  LD (DNQLBPTR),DE
        XOR A
        LD (DNQLABL),A
        CALL DNQPUT
        RET
DNENDLAB  LD A,(DNQLABL)
        OR A
        JR Z,DNQBAD
        LD HL,(DNQLBPTR)
        LD (HL),A
        OR A
        RET
DNQPUT    LD (DE),A
        INC DE
        PUSH AF
        LD A,(DNQCNT)
        INC A
        LD (DNQCNT),A
        POP AF
        RET

; Slot 5 W5100 IO: verified Z80 native reads and kernel F9 writes.
DNSETPOR LD A,5
        ADD A,A
        ADD A,A
        ADD A,A
        ADD A,A
        ADD A,084H
        LD (DNMOD001+1),A
        INC A
        LD (DNADD003+1),A
        INC A
        LD (DNADD004+1),A
        INC A
        LD (DNDAT001+1),A
        RET
DNMOD001  LD A,(0E0B4H)
        RET
DNDAT001  LD A,(0E0B7H)
        RET
DNADD003  LD (0E0B5H),A
        RET
DNADD004  LD (0E0B6H),A
        RET
DNWSEL    PUSH AF
        LD A,H
        CALL DNADD003
        LD A,L
        CALL DNADD004
        POP AF
        RET
DNWREAD   CALL DNWSEL
        JP DNDAT001
DNWWRITE  PUSH AF
        PUSH BC
        PUSH DE
        PUSH HL
        LD (DNWVAL),A
        LD A,H
        LD (DNWADDR),A
        LD A,L
        LD (DNWADDR+1),A
        LD DE,DNWADDR
        LD C,0F9H
        CALL BDOS
        POP HL
        POP DE
        POP BC
        POP AF
        RET
; Write a selected socket register. B=offset, A=value.
DNWSET    PUSH HL
        PUSH AF
        LD A,(DNSOCKHI)
        LD H,A
        LD L,B
        POP AF
        CALL DNWWRITE
        POP HL
        RET
; Read a selected socket register. A=offset, return A=register.
DNWGET    PUSH HL
        LD L,A
        LD A,(DNSOCKHI)
        LD H,A
        CALL DNWREAD
        POP HL
        RET

DNPICK    LD E,0
        LD C,0FAH
        CALL BDOS
        CP 4
        JR NC,DNPICKER
        LD (DNSOCKNO),A
        ADD A,4
        LD (DNSOCKHI),A
        LD A,1
        LD (DNHELD),A
        OR A
        RET
DNPICKER SCF
        RET
DNRELEAS LD A,(DNHELD)
        OR A
        RET Z
        XOR A
        LD (DNHELD),A
        LD A,(DNSOCKNO)
        LD D,A
        LD E,1
        LD C,0FAH
        CALL BDOS
        RET
; FB: E=W5100 command, or 0 to read status. Ownership checked.
DNFBCMD   LD A,(DNSOCKNO)
        LD D,A
        LD C,0FBH
        CALL BDOS
        RET
DNFBGET   LD E,0
        CALL DNFBCMD
        RET

DNUDPOPE LD A,0
        CALL DNFBGET
        CP 0
        JR NZ,DNUDPBAD
        LD B,0
        LD A,2
        CALL DNWSET
        LD B,4
        LD A,0D3H
        CALL DNWSET
        LD B,5
        LD A,(DNSOCKNO)
        ADD A,051H
        CALL DNWSET
        LD B,0CH
        LD A,(DNSIP)
        CALL DNWSET
        LD B,0DH
        LD A,(DNSIP+1)
        CALL DNWSET
        LD B,0EH
        LD A,(DNSIP+2)
        CALL DNWSET
        LD B,0FH
        LD A,(DNSIP+3)
        CALL DNWSET
        LD B,10H
        XOR A
        CALL DNWSET
        LD B,11H
        LD A,35H
        CALL DNWSET
        LD B,0
        LD A,2
        CALL DNWSET
        LD E,1
        CALL DNFBCMD
        CP 0FFH
        JR Z,DNUDPBAD
        CALL DNFBGET
        CP 22H
        JR NZ,DNUDPBAD
        OR A
        RET
DNUDPBAD  SCF
        RET

; Compute TX or RX ring base and mask from live TMSR/RMSR.
; Input A=memory allocation register offset (1Bh TX, 1Ah RX).
; C=base page 40h (TX) or 60h (RX).
DNRINGSE LD (DNMEMREG),A
        LD A,C
        LD (DNRBASE),A
        LD A,(DNMEMREG)
        LD L,A
        LD H,0
        CALL DNWREAD
        LD B,A
        LD A,(DNSOCKNO)
        LD C,A
DNRINGLP  LD A,C
        OR A
        JR Z,DNRINGCU
        LD A,B
        AND 3
        CALL DNSIZPAG
        LD D,A
        LD A,(DNRBASE)
        ADD A,D
        LD (DNRBASE),A
        LD A,B
        RRCA
        RRCA
        LD B,A
        DEC C
        JR DNRINGLP
DNRINGCU LD A,B
        AND 3
        CALL DNSIZPAG
        DEC A
        LD (DNRMASK),A
        LD D,A
        LD A,(DNRBASE)
        AND 01FH
        ADD A,D
        CP 32
        JR NC,DNRINGBA
        OR A
        RET
DNRINGBA SCF
        RET
DNSIZPAG LD E,A
        LD D,0
        LD HL,DNSZTAB
        ADD HL,DE
        LD A,(HL)
        RET
; DNPTRHI/DNPTRLO are full 16-bit W5100 hardware ring pointers.
; Input A=socket register offset of pointer's high byte.
DNGETPTR  CALL DNWGET
        LD (DNPTRHI),A
        LD A,(DNREGPTR)
        INC A
        CALL DNWGET
        LD (DNPTRLO),A
        RET
DNSETPTR  LD A,(DNREGPTR)
        LD B,A
        LD A,(DNPTRHI)
        CALL DNWSET
        LD A,(DNREGPTR)
        INC A
        LD B,A
        LD A,(DNPTRLO)
        CALL DNWSET
        RET
DNRADDR   PUSH BC
        LD A,(DNPTRHI)
        LD B,A
        LD A,(DNRMASK)
        AND B
        LD B,A
        LD A,(DNRBASE)
        ADD A,B
        LD H,A
        LD A,(DNPTRLO)
        LD L,A
        POP BC
        RET
DNINCPTR  LD A,(DNPTRLO)
        INC A
        LD (DNPTRLO),A
        RET NZ
        LD A,(DNPTRHI)
        INC A
        LD (DNPTRHI),A
        RET
DNRINGWR  PUSH AF
        CALL DNRADDR
        POP AF
        CALL DNWWRITE
        CALL DNINCPTR
        RET
DNRINGRD  CALL DNRADDR
        CALL DNWREAD
        PUSH AF
        CALL DNINCPTR
        POP AF
        RET

; Transmit DNS query as ONE UDP datagram, never through chunked FC.
DNTXDNS   LD A,1BH
        LD C,40H
        CALL DNRINGSE
        JP C,DNTXFAIL
        LD A,20H
        CALL DNWGET
        OR A
        JR NZ,DNTXSPAC
        LD A,21H
        CALL DNWGET
        LD B,A
        LD A,(DNQCNT)
        CP B
        JR C,DNTXSPAC
        JR Z,DNTXSPAC
        SCF
        RET
DNTXSPAC LD A,24H
        LD (DNREGPTR),A
        CALL DNGETPTR
        LD HL,DNQBUF
        LD A,(DNQCNT)
        LD B,A
DNTXLOOP  LD A,(HL)
        PUSH HL
        CALL DNRINGWR
        POP HL
        INC HL
        DJNZ DNTXLOOP
        CALL DNSETPTR
        LD B,2
        LD A,18H
        CALL DNWSET
        LD E,20H
        CALL DNFBCMD
        CP 0FFH
        JR Z,DNTXFAIL
        LD HL,30000
DNTXWAIT  PUSH HL
        LD A,2
        CALL DNWGET
        POP HL
        AND 18H
        CP 10H
        JR Z,DNTXOK
        CP 08H
        JR Z,DNTXFAIL
        DEC HL
        LD A,H
        OR L
        JR Z,DNTXFAIL
        JR DNTXWAIT
DNTXOK    OR A
        RET
DNTXFAIL  SCF
        RET

; Receive one UDP datagram. W5100 adds 8-byte metadata header.
; DNRXBUF starts with source IP (4), source port (2), packet length (2).
DNRXDNS   LD HL,50000
DNRXWAIT  PUSH HL
        LD A,26H
        CALL DNWGET
        LD (DNAVHIGH),A
        LD A,27H
        CALL DNWGET
        LD (DNAVLOW),A
        POP HL
        LD A,(DNAVHIGH)
        OR A
        JR NZ,DNRXREAD
        LD A,(DNAVLOW)
        CP 8
        JR NC,DNRXREAD
        DEC HL
        LD A,H
        OR L
        JP Z,DNRXFAIL
        JR DNRXWAIT
DNRXREAD LD A,1AH
        LD C,60H
        CALL DNRINGSE
        JP C,DNRXFAIL
        LD A,28H
        LD (DNREGPTR),A
        CALL DNGETPTR
        LD HL,DNRXBUF
        LD BC,8
        CALL DNREADN
        LD A,(DNRXBUF+6)
        CP 2
        JR C,DNRXSIZE
        JP NZ,DNRXFAIL
        LD A,(DNRXBUF+7)
        OR A
        JP NZ,DNRXFAIL
DNRXSIZE  LD A,(DNRXBUF+6)
        LD B,A
        LD A,(DNRXBUF+7)
        LD C,A
        LD (DNDLEN),BC
        ; Confirm W5100 reports the complete 8-byte header plus payload.
        LD A,C
        ADD A,8
        LD C,A
        LD A,B
        ADC A,0
        LD B,A
        LD A,(DNAVHIGH)
        CP B
        JP C,DNRXFAIL
        JR NZ,DNRXAVOK
        LD A,(DNAVLOW)
        CP C
        JP C,DNRXFAIL
DNRXAVOK  LD BC,(DNDLEN)
        ; Discard packets not sent by the requested resolver on UDP/53.
        LD HL,DNRXBUF
        LD DE,DNSIP
        LD B,4
DNRXSRC   LD A,(DE)
        CP (HL)
        JP NZ,DNRXFAIL
        INC DE
        INC HL
        DJNZ DNRXSRC
        LD A,(DNRXBUF+4)
        OR A
        JP NZ,DNRXFAIL
        LD A,(DNRXBUF+5)
        CP 35H
        JP NZ,DNRXFAIL
        LD BC,(DNDLEN)
        LD A,B
        OR A
        JR NZ,DNRXBODY
        LD A,C
        CP 12
        JR C,DNRXFAIL
DNRXBODY  LD HL,DNRXBUF+8
        LD BC,(DNDLEN)
        CALL DNREADN
        CALL DNSETPTR
        LD E,40H
        CALL DNFBCMD
        CP 0FFH
        JP Z,DNRXFAIL
        OR A
        RET
DNRXFAIL  SCF
        RET
; Read BC bytes into HL, reading the selected W5100 RX ring.
DNREADN   LD A,B
        OR C
        RET Z
        PUSH BC
        PUSH HL
        CALL DNRINGRD
        POP HL
        LD (HL),A
        INC HL
        POP BC
        DEC BC
        JR DNREADN

; Packet parse: check ID, QR, RCODE, QDCOUNT; skip compressed names.
DNPARSE   LD A,(DNSBUF)
        CP 05AH
        JP NZ,DNDNFAIL
        LD A,(DNSBUF+1)
        CP 0A5H
        JP NZ,DNDNFAIL
        LD A,(DNSBUF+2)
        AND 80H
        JP Z,DNDNFAIL
        LD A,(DNSBUF+2)
        AND 02H                 ; TC: truncated UDP response
        JP NZ,DNDNFAIL
        LD A,(DNSBUF+3)
        AND 0FH
        JR Z,DNRCOK
        SCF
        RET
DNRCOK    LD A,(DNSBUF+4)
        OR A
        JP NZ,DNDNFAIL
        LD A,(DNSBUF+5)
        CP 1
        JP NZ,DNDNFAIL
        LD HL,DNSBUF
        LD BC,(DNDLEN)
        ADD HL,BC
        LD (DNENDPTR),HL
        LD HL,DNSBUF+12
        CALL DNSKNAME
        JP C,DNDNFAIL
        LD DE,4
        ADD HL,DE
        CALL DNCHEC01
        JP C,DNDNFAIL
        LD A,(DNSBUF+6)
        OR A
        JP NZ,DNDNFAIL
        LD A,(DNSBUF+7)
        LD (DNANLEFT),A
DNANLOOP  LD A,(DNANLEFT)
        OR A
        JP Z,DNANEND
        CALL DNSKNAME
        JP C,DNDNFAIL
        PUSH HL
        LD DE,10
        ADD HL,DE
        CALL DNCHEC01
        POP HL
        JP C,DNDNFAIL
        LD A,(HL)
        LD (DNRTYPE),A
        INC HL
        LD A,(HL)
        LD (DNRTYPE+1),A
        INC HL
        LD A,(HL)
        LD (DNRCLASS),A
        INC HL
        LD A,(HL)
        LD (DNRCLASS+1),A
        INC HL
        LD DE,4
        ADD HL,DE
        LD A,(HL)
        LD (DNRLENH),A
        INC HL
        LD A,(HL)
        LD (DNRLENL),A
        INC HL
        LD (DNRDPTR),HL
        LD A,(DNRLENH)
        LD B,A
        LD A,(DNRLENL)
        LD C,A
        ADD HL,BC
        CALL DNCHEC01
        JP C,DNDNFAIL
        LD (DNNEXTAD),HL
        LD A,(DNRTYPE)
        OR A
        JR NZ,DNANMORE
        LD A,(DNRTYPE+1)
        CP 1
        JR NZ,DNANMORE
        LD A,(DNRCLASS)
        OR A
        JR NZ,DNANMORE
        LD A,(DNRCLASS+1)
        CP 1
        JR NZ,DNANMORE
        LD A,(DNRLENH)
        OR A
        JR NZ,DNANMORE
        LD A,(DNRLENL)
        CP 4
        JR NZ,DNANMORE
        LD A,(DNFOUND)
        OR A
        JR NZ,DNPRTANS
        LD HL,(DNRDPTR)
        LD DE,DNSADDR
        LD BC,4
        LDIR                     ; preserve first A record for future callers
DNPRTANS  LD A,(DNFOUND)
        INC A
        LD (DNFOUND),A
DNANMORE  LD HL,(DNNEXTAD)
        LD A,(DNANLEFT)
        DEC A
        LD (DNANLEFT),A
        JP DNANLOOP
DNANEND   LD A,(DNFOUND)
        OR A
        RET NZ
        SCF
        RET
DNDNFAIL  SCF
        RET
; Consume QNAME/RR name at HL without following compression pointers.
DNSKNAME  LD B,40
DNSKLOOP  CALL DNCHECKL
        RET C
        LD A,(HL)
        OR A
        JR Z,DNSKZERO
        LD C,A
        AND 0C0H
        CP 0C0H
        JR Z,DNSKCOMP
        OR A
        JR NZ,DNSKBAD
        LD A,C
        CP 64
        JR NC,DNSKBAD
        LD E,A
        LD D,0
        INC HL
        ADD HL,DE
        CALL DNCHEC01
        RET C
        DJNZ DNSKLOOP
DNSKBAD   SCF
        RET
DNSKZERO  INC HL
        OR A
        RET
DNSKCOMP  INC HL
        CALL DNCHECKL
        RET C
        INC HL
        OR A
        RET
; Check HL < or <= DNENDPTR. No external pointer dereference.
DNCHECKL PUSH DE
        LD DE,(DNENDPTR)
        LD A,H
        CP D
        JR C,DNCLGOOD
        JR NZ,DNCLBAD
        LD A,L
        CP E
        JR C,DNCLGOOD
DNCLBAD   POP DE
        SCF
        RET
DNCLGOOD  POP DE
        OR A
        RET
DNCHEC01 PUSH DE
        LD DE,(DNENDPTR)
        LD A,H
        CP D
        JR C,DNCEGOOD
        JR NZ,DNCEBAD
        LD A,L
        CP E
        JR C,DNCEGOOD
        JR Z,DNCEGOOD
DNCEBAD   POP DE
        SCF
        RET
DNCEGOOD  POP DE
        OR A
        RET

DNQHEAD   DEFB 05AH,0A5H,1,0,0,1,0,0,0,0,0,0
DNSZTAB   DEFB 4,8,16,32
DNSIP   DEFB 1,1,1,1
DNHELD    DEFB 0
DNSOCKNO  DEFB 0
DNSOCKHI  DEFB 0
DNFOUND   DEFB 0
DNSADDR DEFB 0,0,0,0
DNQCNT    DEFB 0
DNQLABL   DEFB 0
DNHOSTPT DEFW 0
DNQSPTR   DEFW 0
DNQLBPTR  DEFW 0
DNWADDR   DEFB 0,0
DNWVAL    DEFB 0
DNMEMREG  DEFB 0
DNRBASE   DEFB 0
DNRMASK   DEFB 0
DNREGPTR  DEFB 0
DNPTRHI   DEFB 0
DNPTRLO   DEFB 0
DNAVHIGH  DEFB 0
DNAVLOW   DEFB 0
DNDLEN    DEFW 0
DNENDPTR  DEFW 0
DNANLEFT  DEFB 0
DNRTYPE   DEFB 0,0
DNRCLASS  DEFB 0,0
DNRLENH   DEFB 0
DNRLENL   DEFB 0
DNRDPTR   DEFW 0
DNNEXTAD DEFW 0
DNCMDTXT  DEFS 128
DNQBUF    DEFS 256
DNRXBUF   DEFS 520
DNSBUF  EQU DNRXBUF+8


STACK   DEFS 256
STKTOP
        END
