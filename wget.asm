; WGET.COM v0.2e FCB initialization fix for Zapple-II Phase 4C (Apple //e, Z80 SoftCard)
; Progress: one initial dot, then one per 1024 payload bytes flushed.
; HTTP/1.0 downloader using resident BDOS F9/FA/FB/FC networking.
; Usage: WGET http://a.b.c.d[:port]/path FILE.EXT
; IPv4 only, plain HTTP, status 200 only. No DNS, TLS, redirects or chunking.
; Downloads are written as 128-byte CP/M sequential records. Last record
; is padded with Ctrl-Z (1Ah). Do not overwrite existing files.
; Udo Munk Z80ASM dialect. All labels <= 8 chars, no ';' inside strings.

BDOS    EQU 0005H
        ORG 0100H
START   LD SP,STKTOP
; Explicitly clear counters: DEFS storage may be filled with FFh
; by Udo Munk's assembler (or by the COM loader).
        LD HL,NBYTES
        LD B,4
        XOR A
NBZERO  LD (HL),A
        INC HL
        DJNZ NBZERO
        LD DE,BANNER
        CALL PRINT
        CALL ARGS
        JP C,BADARGS
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
BADARGS LD DE,USAGE
        JP ERROR
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

; Copy CP/M command tail to private NUL terminated buffer.
ARGS    LD A,(0080H)
        CP 124
        JR NC,ARGERR
        LD B,A
        LD HL,0081H
        LD DE,CMDTXT
ARGCOPY LD A,B
        OR A
        JR Z,ARGEND
        LD A,(HL)
        LD (DE),A
        INC HL
        INC DE
        DJNZ ARGCOPY
ARGEND  XOR A
        LD (DE),A
        LD HL,CMDTXT
        CALL SKIPSP
        LD A,(HL)
        OR A
        JR Z,ARGERR
        LD (URLPTR),HL
        CALL NEXTTK
        CALL SKIPSP
        LD A,(HL)
        OR A
        JR Z,ARGERR
        LD (OUTPTR),HL
        CALL NEXTTK
        CALL SKIPSP
        LD A,(HL)
        OR A
        JR NZ,ARGERR
        OR A
        RET
ARGERR  SCF
        RET
SKIPSP  LD A,(HL)
        CP ' '
        JR Z,SKIP1
        CP 9
        RET NZ
SKIP1   INC HL
        JR SKIPSP
NEXTTK  LD A,(HL)
        OR A
        RET Z
        CP ' '
        JR Z,TKEND
        CP 9
        JR Z,TKEND
        INC HL
        JR NEXTTK
TKEND   LD (HL),0
        INC HL
        RET

; Parse http://numeric-IP[:port]/path. Record Host: and URL path.
URLPAR  LD HL,(URLPTR)
        LD DE,PREFIX
URLPRE  LD A,(DE)
        OR A
        JR Z,PREOK
        LD B,A
        LD A,(HL)
        CALL UPPER
        CP B
        JR NZ,URLBAD
        INC HL
        INC DE
        JR URLPRE
PREOK   LD (HOSTPT),HL
        LD DE,HOSTIP
        LD B,4
IPLOOP  PUSH BC
        PUSH DE
        CALL OCTET
        POP DE
        POP BC
        JR C,URLBAD
        LD (DE),A
        INC DE
        DEC B
        JR Z,IPEND
        LD A,(HL)
        CP '.'
        JR NZ,URLBAD
        INC HL
        JR IPLOOP
IPEND   LD A,(HL)
        CP ':'
        JR NZ,PORTEND
        INC HL
        CALL GETPORT
        JR C,URLBAD
PORTEND LD A,(HL)
        CP '/'
        JR NZ,URLBAD
        LD (PATHPT),HL
        LD HL,(HOSTPT)
        LD DE,HOSTTX
        LD B,27
HOSTCP  LD A,(HL)
        CP '/'
        JR Z,HOSTEND
        OR A
        JR Z,URLBAD
        LD (DE),A
        INC HL
        INC DE
        DJNZ HOSTCP
        JR URLBAD
HOSTEND XOR A
        LD (DE),A
        OR A
        RET
URLBAD  SCF
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

; CP/M FCB name creation; no drive prefix, 8.3 uppercase.
FPAR    LD HL,FCB
        LD B,36
        XOR A
FZERO   LD (HL),A
        INC HL
        DJNZ FZERO
; Now populate blank-padded filename and extension.
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

BANNER  DEFM 'Zapple-II WGET v0.2e'
        DEFB 13,10,'$'
USAGE   DEFM 'Usage: WGET http://IP[:port]/path FILE.EXT'
        DEFB 13,10,'$'
ERRURL  DEFM 'Invalid URL. Only numeric IPv4 and http:// supported'
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
URLPTR  DEFW 0
OUTPTR  DEFW 0
HOSTPT  DEFW 0
PATHPT  DEFW 0
HOSTIP  DEFS 4
HOSTTX  DEFS 28
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
STACK   DEFS 256
STKTOP
        END
