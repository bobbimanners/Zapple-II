; Zapple-II AUX CCP 1.6 (Stage 28; compact history and WordStar editor)
; Standard CP/M 2.2 BDOS for built-ins; private BDOS F7 for program chaining.
; Requires Stage 13 kernel: F7 copies launch FCB + FCB1 + FCB2 + command tail.
; Transient program memory is AUX; tab switches retain command and stack.
; F7 parameter block: 36-byte COM FCB, 16-byte default FCB1,
; 16-byte default FCB2, 128-byte command tail (CP/M 0080h format).
            ORG     0100H
START       CALL    EDRESTORE                  ; safe no-op on a fresh tab
            LD      DE,BANNER
            CALL    PRINT
MAINLOOP    CALL    PROMPT
            CALL    READLINE
            LD      HL,LINE
            CALL    SKSP
            LD      (CMDPTR),HL
            LD      A,(HL)
            OR      A
            JP      Z,MAINLOOP
            LD      A,(HL)
            CP      'A'
            JR      C,CMDSCAN
            CP      'P'+1
            JR      NC,CMDSCAN
            INC     HL
            LD      A,(HL)
            CP      ':'
            JR      NZ,CMDSCAN
            INC     HL
            LD      A,(HL)
            OR      A
            JR      NZ,CMDSCAN
            LD      HL,(CMDPTR)
            LD      A,(HL)
            SUB     'A'
            LD      E,A
            LD      C,14
            CALL    0005H
            JP      MAINLOOP
CMDSCAN     LD      HL,(CMDPTR)
CSNEXT      LD      A,(HL)
            OR      A
            JR      Z,CSEOL
            CP      ' '
            JR      Z,CSSP
            INC     HL
            JR      CSNEXT
CSSP        LD      (HL),0
            INC     HL
            CALL    SKSP
CSEOL       LD      (ARGPTR),HL
            LD      HL,(CMDPTR)
            LD      DE,KDIR
            CALL    MATCH
            JP      Z,DODIR
            LD      HL,(CMDPTR)
            LD      DE,KTYPE
            CALL    MATCH
            JP      Z,DOTYPE
            LD      HL,(CMDPTR)
            LD      DE,KERA
            CALL    MATCH
            JP      Z,DOERA
            LD      HL,(CMDPTR)
            LD      DE,KREN
            CALL    MATCH
            JP      Z,DOREN
            LD      HL,(CMDPTR)
            LD      DE,KUSER
            CALL    MATCH
            JP      Z,DOUSER
            LD      HL,(CMDPTR)
            LD      DE,KHELP
            CALL    MATCH
            JP      Z,DOHELP
            LD      HL,(CMDPTR)
            LD      DE,KHIST
            CALL    MATCH
            JP      Z,DOHIST
            LD      HL,(CMDPTR)
            LD      DE,KCLS
            CALL    MATCH
            JP      Z,DOCLS
            LD      HL,(CMDPTR)
            LD      DE,KBANKS
            CALL    MATCH
            JP      Z,DOBANKS
            LD      HL,(CMDPTR)
            LD      DE,KCACHE
            CALL    MATCH
            JP      Z,DOCACHE
            LD      HL,(CMDPTR)
            LD      DE,KTERM
            CALL    MATCH
            JP      Z,DOTERM
            LD      HL,(CMDPTR)
            LD      DE,KTAB
            CALL    MATCH
            JP      Z,DOTAB
            LD      HL,(CMDPTR)
            LD      DE,KXSUB
            CALL    MATCH
            JP      Z,DOXSUB
            LD      HL,(CMDPTR)
            LD      DE,KBYE
            CALL    MATCH
            JP      Z,DOBYE
            LD      HL,(CMDPTR)
            LD      DE,KSAVE
            CALL    MATCH
            JP      Z,DOSAVE
            JP      DOEXEC

; Match the legacy CCP prompt exactly: [0]A:>, [1]A3:>, [F]B12:>.
; Private BDOS F8/id 8 returns the logical TABMODE session in A and L.
; MAIN owns TABMODE and it cannot be read directly from AUX TPA.
; BDOS 25 queries drive; BDOS 32/E=FFh queries the active USER.
PROMPT      LD      A,8
            LD      (BXID),A
            LD      DE,BXID
            LD      C,0F8H
            CALL    0005H
            AND     0FH
            CP      10
            JR      C,PRMDIG
            ADD     A,37H                       ; hex A..F
            JR      PRMCHAR
PRMDIG      ADD     A,30H                       ; hex 0..9
PRMCHAR     PUSH    AF
            LD      A,'['
            CALL    OUT
            POP     AF
            CALL    OUT
            LD      A,']'
            CALL    OUT
            LD      C,25
            CALL    0005H
            ADD     A,'A'
            CALL    OUT
            LD      E,0FFH
            LD      C,32
            CALL    0005H
            OR      A
            JR      Z,PRMEND
            CALL    PRINTNUM
PRMEND      LD      A,':'
            CALL    OUT
            LD      A,'>'
            JP      OUT

; Reuse the kernel's BDOS 10 editor (raw input, BS/DEL, no double echo).
; Convert the returned CP/M [max][count][characters][CR] buffer to
; the original NUL-terminated, uppercase LINE used by the parser.
; The Stage 25 bridge used HL without initializing it, allowing the F8/10
; record copier to write anywhere in AUX memory.  The out-of-line setup
; after the data region preserves all original code/data addresses.
; F8/10 returns A=1 only when a SUBMIT record has been echoed and copied.
READLINE    JP      RLSUBPTR
RLSUBCALL   LD      (BXTAIL),HL                 ; address of BDOS 10 count byte
            LD      A,10
            LD      (BXID),A
            LD      DE,BXID
            LD      C,0F8H
            CALL    0005H                      ; ask MAIN for next $$$.SUB record
            DEC     A                          ; only A=1 means a valid record
            JR      Z,RLHAVE                    ; already echoed by CCPSUB
RLKEYBD     JP      EDSTART
; Original BDOS 10 path retained for reference and XSUB-independent editing.
RLKEYOLD    LD      DE,INBUF                  ; physical BDOS 10 (proven Stage 25.2 editor)
            LD      A,78
            LD      (DE),A
            LD      C,10
            CALL    0005H                      ; otherwise use kernel line editor
RLHAVE      LD      A,(INBUF+1)
            LD      B,A
            LD      HL,INBUF+2
            LD      DE,LINE
RLCOPY      LD      A,B
            OR      A
            JR      Z,RLDONE
            LD      A,(HL)
            CP      'a'
            JR      C,RLKEEP
            CP      'z'+1
            JR      NC,RLKEEP
            SUB     32
RLKEEP      LD      (DE),A
            INC     DE
            INC     HL
            DJNZ    RLCOPY
RLDONE      XOR     A
            LD      (DE),A
            RET
SKSP        LD      A,(HL)
            CP      ' '
            RET     NZ
            INC     HL
            JR      SKSP
MATCH       LD      A,(DE)
            OR      A
            JR      Z,MBOUND
            CP      (HL)
            JR      NZ,MBAD
            INC     DE
            INC     HL
            JR      MATCH
MBOUND      LD      A,(HL)
            OR      A
            RET     Z
MBAD        LD      A,1
            OR      A
            RET

; Poll ^C non-destructively to stop a listing.
POLLKEY     PUSH    BC
            PUSH    DE
            PUSH    HL
            LD      E,0FFH
            LD      C,6
            CALL    0005H
            CP      3
            POP     HL
            POP     DE
            POP     BC
            RET

; Stage 24.2: classic CP/M 2.2 DIR layout, four padded 8.3 names per row.
; Preserve wildcard parsing, explicit drive, and ^C while listing.
DODIR       CALL    SETDMA
            LD      HL,(ARGPTR)
            LD      A,(HL)
            OR      A
            JR      Z,DIRALL
            ; Accept DIR B: as shorthand for DIR B:*.*.
            LD      B,A
            INC     HL
            LD      A,(HL)
            CP      ':'
            JR      NZ,DIRPAT
            INC     HL
            LD      A,(HL)
            OR      A
            JR      NZ,DIRPAT
            LD      A,B
            CP      'A'
            JP      C,SHOWBAD
            CP      'P'+1
            JP      NC,SHOWBAD
            SUB     'A'-1
            LD      (DIRDRIVE),A
            CALL    FCBWILD
            LD      A,(DIRDRIVE)
            LD      (FCB),A
            JR      DIRFIRST
DIRPAT      LD      HL,(ARGPTR)
            LD      A,1
            LD      (ALLOWW),A
            CALL    PARSENAME
            JP      NZ,SHOWBAD
            JR      DIRFIRST
DIRALL      CALL    FCBWILD
; Capture the selected drive once. FCB drive 0 means current drive.
DIRFIRST    LD      A,(FCB)
            OR      A
            JR      NZ,DFEXPL
            LD      C,25
            CALL    0005H
            INC     A
DFEXPL      ADD     A,'A'-1
            LD      (DIRDRIVE),A                ; ASCII drive for line prefixes
            XOR     A
            LD      (DIRCOL),A
            LD      DE,FCB
            LD      C,17                       ; SEARCH FIRST
            CALL    0005H
            OR      A
            JP      NZ,DIRNONE
DIRLOOP     LD      A,(DIRCOL)
            OR      A
            JR      NZ,DIRSEP
            CALL    DIRPREFIX                 ; A: only at beginning of row
            JR      DIRPRINT
DIRSEP      LD      A,' '
            CALL    OUT
            LD      A,':'
            CALL    OUT
            LD      A,' '
            CALL    OUT
DIRPRINT    CALL    DIRFIELD
            LD      A,(DIRCOL)
            INC     A
            CP      4
            JR      NZ,DIRPART
            XOR     A
            LD      (DIRCOL),A
            LD      A,13                      ; 4 names completed: newline
            CALL    OUT
            JR      DIRNEXT
DIRPART     LD      (DIRCOL),A
DIRNEXT     CALL    POLLKEY
            JP      Z,DIRABORT
            LD      DE,FCB
            LD      C,18                      ; SEARCH NEXT
            CALL    0005H
            OR      A
            JP      Z,DIRLOOP
            LD      A,(DIRCOL)
            OR      A
            JP      Z,MAINLOOP                ; full row already ended in CR
            LD      A,13                      ; finish partial row
            CALL    OUT
            JP      MAINLOOP
DIRPREFIX   LD      A,(DIRDRIVE)
            CALL    OUT
            LD      A,':'
            CALL    OUT
            LD      A,' '
            JP      OUT
DIRABORT    LD      A,13
            CALL    OUT
            LD      DE,DIRSTOP
            CALL    PRINT
            JP      MAINLOOP
DIRNONE     LD      DE,EMPTYMSG
            CALL    PRINT
            JP      MAINLOOP

; One classic CP/M entry: exactly 8 name chars, a space, 3 extension
; chars. Mask attribute bits in directory results, preserving padding.
DIRFIELD    LD      HL,DMA+1
            LD      B,8
DFBASE      LD      A,(HL)
            AND     07FH
            CALL    OUT
            INC     HL
            DJNZ    DFBASE
            LD      A,' '
            CALL    OUT
            LD      B,3
DFEXT       LD      A,(HL)
            AND     07FH
            CALL    OUT
            INC     HL
            DJNZ    DFEXT
            RET
FCBWILD     CALL    FCBZERO
            LD      HL,FCB+1
            LD      B,11
            LD      A,'?'
FWLOOP      LD      (HL),A
            INC     HL
            DJNZ    FWLOOP
            RET
FCBZERO     LD      HL,FCB
            LD      B,36
            XOR     A
FZLOOP      LD      (HL),A
            INC     HL
            DJNZ    FZLOOP
            RET
SETDMA      LD      DE,DMA
            LD      C,26
            JP      0005H

DOTYPE      LD      HL,(ARGPTR)
            LD      A,(HL)
            OR      A
            JP      Z,SHOWBAD
            XOR     A
            LD      (ALLOWW),A
            CALL    PARSENAME
            JP      NZ,SHOWBAD
            CALL    SETDMA
            LD      DE,FCB
            LD      C,15
            CALL    0005H
            OR      A
            JP      NZ,SHOWNOTF
TYBLOCK     LD      DE,FCB
            LD      C,20
            CALL    0005H
            OR      A
            JR      NZ,TYCLOSE
            LD      HL,DMA
            LD      B,128
TYBYTE      LD      A,(HL)
            CP      1AH
            JR      Z,TYCLOSE
            OR      A
            JR      Z,TYSKIP
            CALL    OUT
TYSKIP      INC     HL
            PUSH    BC
            CALL    POLLKEY
            POP     BC
            JR      Z,TYCLOSE
            DJNZ    TYBYTE
            JR      TYBLOCK
TYCLOSE     LD      DE,FCB
            LD      C,16
            CALL    0005H
            LD      A,13
            CALL    OUT
            JP      MAINLOOP
SHOWNOTF    LD      DE,NOTFOUND
            CALL    PRINT
            JP      MAINLOOP
SHOWBAD     LD      DE,BADNAME
            CALL    PRINT
            JP      MAINLOOP
SHOWERR     LD      DE,FAILMSG
            CALL    PRINT
            JP      MAINLOOP

DOERA       LD      HL,(ARGPTR)
            LD      A,1
            LD      (ALLOWW),A
            CALL    PARSENAME
            JP      NZ,SHOWBAD
            CALL    HASWILD
            JR      Z,ERDELETE
            LD      DE,ERASK
            CALL    PRINT
            LD      C,1
            CALL    0005H
            CP      'Y'
            JP      NZ,MAINLOOP
ERDELETE    LD      DE,FCB
            LD      C,19
            CALL    0005H
            OR      A
            JP      NZ,SHOWERR
            JP      MAINLOOP
HASWILD     LD      HL,FCB+1
            LD      B,11
HWLOOP      LD      A,(HL)
            CP      '?'
            JR      Z,HWFND
            INC     HL
            DJNZ    HWLOOP
            XOR     A
            RET
HWFND       LD      A,1
            OR      A
            RET

; REN new.ext=old.ext. Source is first FCB, destination goes at +16.
DOREN       LD      HL,(ARGPTR)
            LD      (RENDST),HL
RNEQ        LD      A,(HL)
            OR      A
            JP      Z,SHOWBAD
            CP      '='
            JR      Z,RNGOT
            INC     HL
            JR      RNEQ
RNGOT       LD      (HL),0
            INC     HL
            LD      A,(HL)
            OR      A
            JP      Z,SHOWBAD
            XOR     A
            LD      (ALLOWW),A
            CALL    PARSENAME                  ; old name
            JP      NZ,SHOWBAD
            LD      HL,FCB
            LD      DE,RENFCB
            LD      BC,36
            LDIR
            LD      HL,(RENDST)
            CALL    PARSENAME                  ; new name
            JP      NZ,SHOWBAD
            LD      A,(FCB)
            LD      B,A
            LD      A,(RENFCB)
            OR      A
            JR      Z,RNCOPY
            LD      A,B
            OR      A
            JR      Z,RNCOPY
            LD      A,(RENFCB)
            CP      B
            JP      NZ,SHOWBAD
RNCOPY      LD      HL,FCB+1
            LD      DE,RENFCB+17
            LD      BC,11
            LDIR
            LD      DE,RENFCB
            LD      C,23
            CALL    0005H
            OR      A
            JP      NZ,SHOWERR
            JP      MAINLOOP

DOUSER      LD      HL,(ARGPTR)
            LD      A,(HL)
            OR      A
            JR      NZ,USERSET
            LD      E,0FFH
            LD      C,32
            CALL    0005H
            CALL    PRINTNUM
            LD      A,13
            CALL    OUT
            JP      MAINLOOP
USERSET     CALL    NUMPARSE
            JP      NZ,SHOWBAD
            LD      E,A
            LD      C,32
            CALL    0005H
            JP      MAINLOOP
; decimal 0..15, no other characters; return A=value and Z success.
NUMPARSE    LD      A,(HL)
            SUB     '0'
            JR      C,NUMBAD
            CP      10
            JR      NC,NUMBAD
            LD      B,A
            INC     HL
            LD      A,(HL)
            OR      A
            JR      Z,NUMONE
            SUB     '0'
            JR      C,NUMBAD
            CP      10
            JR      NC,NUMBAD
            LD      D,A
            INC     HL
            LD      A,(HL)
            OR      A
            JR      NZ,NUMBAD
            LD      A,B
            ADD     A,A
            LD      E,A
            ADD     A,A
            ADD     A,A
            ADD     A,E                     ; B*10
            ADD     A,D
            CP      16
            JR      NC,NUMBAD
            CP      A                      ; return Z on valid nonzero number
            RET
NUMONE      LD      A,B
            CP      A
            RET
NUMBAD      LD      A,0FFH
            OR      A
            RET
PRINTNUM    CP      10
            JR      C,NUMSINGLE
            SUB     10
            LD      B,A
            LD      A,'1'
            CALL    OUT
            LD      A,B
NUMSINGLE   ADD     A,'0'
            JP      OUT

; Display the current tab's history, oldest entry first.
; The editor has already appended HIST before command dispatch.
; History is a 10-slot circular buffer: EDHEAD is the NEXT write slot.
; No F8 transfer or bank switching is necessary here.
DOHIST      LD      A,(EDCOUNT)
            OR      A
            JP      Z,MAINLOOP
            LD      (HLEFT),A
            LD      B,A
            LD      A,(EDHEAD)
            SUB     B                       ; oldest = (head - count) % 10
            JR      NC,HISTINIT
            ADD     A,10
HISTINIT    LD      (HINDEX),A
            LD      A,1
            LD      (HNUMBER),A
HISTLINE    LD      A,(HNUMBER)
            CALL    PRINTNUM                ; chronological number, 1..10
            LD      A,':'
            CALL    OUT
            LD      A,' '
            CALL    OUT
            LD      A,(HINDEX)
            CALL    EDGETPTR                ; HL = address of slot
            LD      B,75                    ; bound reads even if damaged
HISTCHAR    LD      A,(HL)
            OR      A
            JR      Z,HISTNEXT
            CALL    OUT                     ; prints '$' correctly too
            INC     HL
            DJNZ    HISTCHAR
HISTNEXT    LD      A,13
            CALL    OUT
            LD      A,(HINDEX)
            INC     A
            CP      10
            JR      C,HISTINDEX
            XOR     A
HISTINDEX   LD      (HINDEX),A
            LD      A,(HNUMBER)
            INC     A
            LD      (HNUMBER),A
            LD      A,(HLEFT)
            DEC     A
            LD      (HLEFT),A
            JP      NZ,HISTLINE
            JP      MAINLOOP
DOHELP      LD      DE,HELPMSG
            CALL    PRINT
            JP      MAINLOOP

; Stage 19: private BDOS $F8 bridge to the MAIN-only CCP handlers.
; Record is 1-byte command ID followed by 80 bytes of normalized
; FILEBUF tail (length, leading space, argument(s), trailing space, NUL).
; MAIN dispatch checks that this request originates in an AUX shell.
DOCLS       LD      A,1
            JP      BXCMD
DOBANKS     LD      A,2
            JP      BXCMD
DOCACHE     LD      A,3
            JP      BXCMD
DOTERM      LD      A,4
            JP      BXCMD
; Stage 21: accept both TAB n ACTION and TAB ACTION n.
; Stage 19's private BDOS F8 already forwards the standard normalized
; tail to the native TBCMD parser; only action-first input needs reordering.
DOTAB       LD      HL,(ARGPTR)
            LD      DE,TBSWITCH
            CALL    TBHEAD
            JP      Z,TBVSWITCH
            LD      HL,(ARGPTR)
            LD      DE,TBSUSPEND
            CALL    TBHEAD
            JP      Z,TBVSUSPEND
            LD      HL,(ARGPTR)
            LD      DE,TBRESUME
            CALL    TBHEAD
            JP      Z,TBVRESUME
            LD      HL,(ARGPTR)
            LD      DE,TBEXCLUSIVE
            CALL    TBHEAD
            JP      Z,TBVEXCLUSIVE
            LD      HL,(ARGPTR)
            LD      DE,TBKILL
            CALL    TBHEAD
            JP      Z,TBVKILL
            LD      A,5
            JP      BXCMD
; On match HL points at the separating space before the argument.
TBHEAD      LD      A,(DE)
            OR      A
            JR      Z,TBHEND
            CP      (HL)
            RET     NZ
            INC     HL
            INC     DE
            JR      TBHEAD
TBHEND      LD      A,(HL)
            CP      ' '
            RET
TBVSWITCH   LD      DE,TBEMPTY
            JP      TBREORDER
TBVSUSPEND  LD      DE,TBSUSPEND
            JP      TBREORDER
TBVRESUME   LD      DE,TBRESUME
            JP      TBREORDER
TBVEXCLUSIVE LD     DE,TBEXCLUSIVE
            JP      TBREORDER
TBVKILL     LD      DE,TBKILL
; HL=space following action; DE=action string, or NUL for SWITCH.
; Numeric selector is a single 0..9/A..F character, range checked
; by the native TABDECODE routine in the kernel.
TBREORDER   INC     HL
            CALL    SKSP
            LD      A,(HL)
            OR      A
            JP      Z,SHOWBAD
            LD      (TABCAN),A
            INC     HL
            CALL    SKSP
            LD      A,(HL)
            OR      A
            JP      NZ,SHOWBAD
            LD      A,(DE)
            OR      A
            JR      NZ,TBRVERB
            LD      (TABCAN+1),A
            JR      TBRDONE
TBRVERB     LD      A,' '
            LD      (TABCAN+1),A
            LD      HL,TABCAN+2
TBRCOPY     LD      A,(DE)
            LD      (HL),A
            OR      A
            JR      Z,TBRDONE
            INC     HL
            INC     DE
            JR      TBRCOPY
TBRDONE     LD      HL,TABCAN
            LD      (ARGPTR),HL
            LD      A,5
            JP      BXCMD
DOXSUB      LD      A,6
            JP      BXCMD
DOBYE       LD      A,7
            JP      BXCMD
; SAVE pages filename -- preserves the previous transient image in a
; dedicated RamWorks screen bank before CCP.COM replaces low TPA.
; F8/9 receives the ordinary normalized command tail followed by FCB2.
; Check syntax before calling the native kernel SAVEFILE implementation.
DOSAVE      LD      HL,(ARGPTR)
            LD      B,0
SVNUMLOOP   LD      A,(HL)
            CP      ' '                         ; space ends the page count
            JR      Z,SVNUMEND                  ; don't reject it as < '0'
            CP      '0'
            JP      C,SHOWBAD
            CP      '9'+1
            JR      NC,SVNUMEND
            INC     B
            LD      A,B
            CP      4
            JP      NC,SHOWBAD                   ; maximum three digits
            INC     HL
            JR      SVNUMLOOP
SVNUMEND    LD      A,B
            OR      A
            JP      Z,SHOWBAD
            LD      A,(HL)
            CP      ' '
            JP      NZ,SHOWBAD
            CALL    SKSP
            LD      A,(HL)
            OR      A
            JP      Z,SHOWBAD
            LD      (SVFPTR),HL
            XOR     A
            LD      (ALLOWW),A
            CALL    PARSENAME
            JP      NZ,SHOWBAD
            LD      HL,(SVFPTR)
SVFEND      LD      A,(HL)
            OR      A
            JR      Z,SVFOK
            CP      ' '
            JR      Z,SVFTRAIL
            INC     HL
            JR      SVFEND
SVFTRAIL    CALL    SKSP
            LD      A,(HL)
            OR      A
            JP      NZ,SHOWBAD
SVFOK       LD      HL,FCB
            LD      DE,BXFCB
            LD      BC,36
            LDIR
            LD      A,9
            JP      BXCMD
BXCMD       LD      (BXID),A
            CALL    BXBUILD
            LD      DE,BXID
            LD      C,0F8H
            CALL    0005H
            JP      MAINLOOP
BXBUILD     LD      HL,BXTAIL
            LD      B,80
            XOR     A
BXZERO      LD      (HL),A
            INC     HL
            DJNZ    BXZERO
            LD      HL,(ARGPTR)
            LD      A,(HL)
            OR      A
            RET     Z
            LD      DE,BXTAIL+1
            LD      A,' '
            LD      (DE),A
            INC     DE
            LD      B,1
BXCOPY      LD      A,(HL)
            OR      A
            JR      Z,BXFIN
            LD      C,A
            LD      A,B
            CP      76
            JR      NC,BXFIN
            LD      A,C
            LD      (DE),A
            INC     HL
            INC     DE
            INC     B
            JR      BXCOPY
BXFIN       LD      A,' '
            LD      (DE),A
            INC     DE
            INC     B
            XOR     A
            LD      (DE),A
            LD      A,B
            LD      (BXTAIL),A
            RET

; Plain 8.3 filename parser with drive prefix and '?'/'*' wildcard support.
; Input HL: token (NUL, space or '=' terminates). Output FCB (36 bytes).
; ALLOWW=1 permits '?'/'*', 0 requires exact name. Z=success.
PARSENAME   PUSH    HL
            CALL    FCBZERO
            LD      HL,FCB+1
            LD      B,11
            LD      A,' '
PFFILL      LD      (HL),A
            INC     HL
            DJNZ    PFFILL
            POP     HL
            LD      A,(HL)
            OR      A
            JP      Z,PINVALID
            INC     HL
            LD      A,(HL)
            CP      ':'
            JR      NZ,PNODRV
            DEC     HL
            LD      A,(HL)
            SUB     'A'-1
            JP      C,PINVALID
            OR      A
            JP      Z,PINVALID
            CP      17
            JP      NC,PINVALID
            LD      (FCB),A
            INC     HL
            INC     HL
            JR      PSTART
PNODRV     DEC     HL
PSTART      LD      DE,FCB+1
            LD      B,8
PNAME       LD      A,(HL)
            OR      A
            JR      Z,PNAMEDONE
            CP      ' '
            JR      Z,PNAMEDONE
            CP      '='
            JR      Z,PNAMEDONE
            CP      '.'
            JR      Z,PEXTBEGIN
            CP      '*'
            JR      Z,PNSTAR
            CP      '?'
            JR      NZ,PNCHAR
            LD      A,(ALLOWW)
            OR      A
            JP      Z,PINVALID
            LD      A,'?'
            JR      PNSTORE
PNCHAR      CALL    VALIDCHAR
            JP      NZ,PINVALID
            LD      A,(HL)
PNSTORE     LD      C,A
            LD      A,B
            OR      A
            JP      Z,PINVALID
            LD      A,C
            LD      (DE),A
            INC     DE
            INC     HL
            DEC     B
            JR      PNAME
PNSTAR      LD      A,(ALLOWW)
            OR      A
            JP      Z,PINVALID
            INC     HL
            LD      A,(HL)
            OR      A
            JR      Z,PNSTA0
            CP      ' '
            JR      Z,PNSTA0
            CP      '='
            JR      Z,PNSTA0
            CP      '.'
            JP      NZ,PINVALID
PNSTA0      LD      A,B
            OR      A
            JP      Z,PINVALID
            LD      A,'?'
PNSTA1      LD      (DE),A
            INC     DE
            DJNZ    PNSTA1
            LD      A,(HL)
            CP      '.'
            JR      Z,PEXTBEGIN
            LD      DE,FCB+9
            LD      B,3
            LD      A,'?'
PNSTA2      LD      (DE),A
            INC     DE
            DJNZ    PNSTA2
            JR      PVALID
PNAMEDONE  LD      A,B
            CP      8
            JR      Z,PINVALID
            JR      PENDCHECK
PEXTBEGIN   LD      A,B
            CP      8
            JR      Z,PINVALID
            INC     HL
            LD      DE,FCB+9
            LD      B,3
PEXTL       LD      A,(HL)
            OR      A
            JR      Z,PENDCHECK
            CP      ' '
            JR      Z,PENDCHECK
            CP      '='
            JR      Z,PENDCHECK
            CP      '*'
            JR      Z,PXSTAR
            CP      '.'
            JR      Z,PINVALID
            CP      '?'
            JR      NZ,PXCHAR
            LD      A,(ALLOWW)
            OR      A
            JR      Z,PINVALID
            LD      A,'?'
            JR      PXSTORE
PXCHAR      CALL    VALIDCHAR
            JR      NZ,PINVALID
            LD      A,(HL)
PXSTORE     LD      C,A
            LD      A,B
            OR      A
            JR      Z,PINVALID
            LD      A,C
            LD      (DE),A
            INC     DE
            INC     HL
            DEC     B
            JR      PEXTL
PXSTAR      LD      A,(ALLOWW)
            OR      A
            JR      Z,PINVALID
            INC     HL
            LD      A,(HL)
            OR      A
            JR      Z,PXSFILL
            CP      ' '
            JR      Z,PXSFILL
            CP      '='
            JR      NZ,PINVALID
PXSFILL     LD      A,B
            OR      A
            JP      Z,PINVALID
            LD      A,'?'
PXS1        LD      (DE),A
            INC     DE
            DJNZ    PXS1
PENDCHECK   LD      A,(HL)
            OR      A
            JR      Z,PVALID
            CP      ' '
            JR      Z,PVALID
            CP      '='
            JR      Z,PVALID
PINVALID    LD      A,1
            OR      A
            RET
PVALID      XOR     A
            RET
; accept letters/digits and CP/M filename punctuation except separators
VALIDCHAR   CP      '!'
            JR      C,VINVALID
            CP      07FH
            JR      NC,VINVALID
            CP      '/'
            JR      Z,VINVALID
            CP      ':'
            JR      Z,VINVALID
            CP      03BH                    ; semicolon literal (Udo Munk Z80ASM-safe)
            JR      Z,VINVALID
            CP      '<'
            JR      Z,VINVALID
            CP      '>'
            JR      Z,VINVALID
            CP      '['
            JR      Z,VINVALID
            CP      ']'
            JR      Z,VINVALID
            CP      ','
            JR      Z,VINVALID
            CP      '='
            JR      Z,VINVALID
            CP      '.'
            JR      Z,VINVALID
            XOR     A
            RET
VINVALID    LD      A,1
            OR      A
            RET

; Execute .COM. Build CP/M tail + two default FCBs and hand them to F7.
DOEXEC      XOR     A
            LD      (ALLOWW),A
            LD      HL,(CMDPTR)
            CALL    PARSENAME
            JP      NZ,SHOWBAD
            LD      A,(FCB+9)
            CP      ' '
            JR      NZ,EXEXT
            LD      A,'C'
            LD      (FCB+9),A
            LD      A,'O'
            LD      (FCB+10),A
            LD      A,'M'
            LD      (FCB+11),A
EXEXT       LD      A,(FCB+9)
            CP      'C'
            JP      NZ,SHOWBAD
            LD      A,(FCB+10)
            CP      'O'
            JP      NZ,SHOWBAD
            LD      A,(FCB+11)
            CP      'M'
            JP      NZ,SHOWBAD
            LD      HL,FCB
            LD      DE,EXPAR
            LD      BC,36
            LDIR
            LD      HL,EXF1
            LD      B,32
            XOR     A
EXFCLEAR    LD      (HL),A
            INC     HL
            DJNZ    EXFCLEAR
            LD      HL,EXF1+1
            LD      B,11
            LD      A,' '
EXFBL1      LD      (HL),A
            INC     HL
            DJNZ    EXFBL1
            LD      HL,EXF2+1
            LD      B,11
EXFBL2      LD      (HL),A
            INC     HL
            DJNZ    EXFBL2
            LD      HL,EXTAIL
            LD      B,128
            XOR     A
EXTCLEAR    LD      (HL),A
            INC     HL
            DJNZ    EXTCLEAR
            LD      HL,(ARGPTR)
            LD      A,(HL)
            OR      A
            JR      Z,EXNOTAIL
            LD      DE,EXTAIL+1
            LD      A,' '
            LD      (DE),A
            INC     DE
            LD      B,1
EXTCOPY     LD      A,(HL)
            OR      A
            JR      Z,EXTDONE
            LD      C,A
            LD      A,B
            CP      126
            JR      NC,EXTDONE
            LD      A,C
            LD      (DE),A
            INC     HL
            INC     DE
            INC     B
            JR      EXTCOPY
EXTDONE     LD      A,' '                    ; match MAIN CCP's trailing delimiter
            LD      (DE),A
            INC     DE
            INC     B
            XOR     A                             ; matching MAIN CCP's NUL terminator
            LD      (DE),A
            LD      A,B
            LD      (EXTAIL),A
            ; Prepare default FCBs; preserve EXPAR so child name survives.
            LD      HL,(ARGPTR)
            LD      A,1
            LD      (ALLOWW),A
            CALL    PARSENAME
            JR      NZ,EXNOF1
            LD      HL,FCB
            LD      DE,EXF1
            LD      BC,16
            LDIR
EXNOF1      LD      HL,(ARGPTR)
EXFINDSP    LD      A,(HL)
            OR      A
            JR      Z,EXNOTAIL
            CP      ' '
            JR      Z,EXF2START
            INC     HL
            JR      EXFINDSP
EXF2START   CALL    SKSP
            LD      A,(HL)
            OR      A
            JR      Z,EXNOTAIL
            CALL    PARSENAME
            JR      NZ,EXNOTAIL
            LD      HL,FCB
            LD      DE,EXF2
            LD      BC,16
            LDIR
EXNOTAIL    LD      A,0
            LD      (EXTAIL+1),A               ; NUL when no args
            LD      A,(EXTAIL)
            OR      A
            JR      Z,EXGO
            ; restore first tail character (no modification to the buffer)
            LD      A,' '
            LD      (EXTAIL+1),A
EXGO        LD      DE,EXPAR
            LD      C,0F7H
            CALL    0005H                    ; success never returns to AUX CCP
            LD      DE,EXFAIL
            CALL    PRINT
            JP      MAINLOOP

PRINT       LD      C,9
            JP      0005H
OUT         PUSH    AF
            PUSH    BC
            PUSH    DE
            PUSH    HL
            LD      E,A
            LD      C,2
            CALL    0005H
            POP     HL
            POP     DE
            POP     BC
            POP     AF
            RET

BANNER      DEFM    'Zapple-II AUX CCP 1.6.11 (Stage 28.11)'
            DEFB    13,'$'
KDIR        DEFM    'DIR'
            DEFB    0
KTYPE       DEFM    'TYPE'
            DEFB    0
KERA        DEFM    'ERA'
            DEFB    0
KREN        DEFM    'REN'
            DEFB    0
KUSER       DEFM    'USER'
            DEFB    0
KHELP       DEFM    'HELP'
            DEFB    0
KHIST       DEFM    'HIST'
            DEFB    0
KCLS        DEFM    'CLS'
            DEFB    0
KBANKS      DEFM    'BANKS'
            DEFB    0
KCACHE      DEFM    'CACHE'
            DEFB    0
KTERM       DEFM    'TERM'
            DEFB    0
KTAB        DEFM    'TAB'
            DEFB    0
TBSWITCH    DEFM    'SWITCH'
            DEFB    0
TBSUSPEND   DEFM    'SUSPEND'
            DEFB    0
TBRESUME    DEFM    'RESUME'
            DEFB    0
TBEXCLUSIVE DEFM    'EXCLUSIVE'
            DEFB    0
TBKILL      DEFM    'KILL'
            DEFB    0
TBEMPTY     DEFB    0
KXSUB       DEFM    'XSUB'
            DEFB    0
KBYE        DEFM    'BYE'
            DEFB    0
KSAVE       DEFM    'SAVE'
            DEFB    0
DIRSTOP     DEFM    '^C  Directory interrupted'
            DEFB    13,'$'
EMPTYMSG    DEFM    'No matching files'
            DEFB    13,'$'
NOTFOUND    DEFM    'File not found'
            DEFB    13,'$'
BADNAME     DEFM    'Bad command or filename'
            DEFB    13,'$'
FAILMSG     DEFM    'File operation failed'
            DEFB    13,'$'
ERASK       DEFM    'Erase wildcard matches (Y/N)? $'
EXFAIL      DEFM    'Program launch failed (requires Stage 13 kernel)'
            DEFB    13,'$'
HELPMSG     DEFM    'DIR ERA REN TYPE USER    CLS BANKS CACHE [RESET]'
            DEFB    13
            DEFM    'TERM VT100/SOROC/H19/H89/VT52   TAB LIST/HELP'
            DEFB    13
            DEFM    'TAB SWITCH n, SUSPEND n, RESUME n, EXCLUSIVE n, KILL n'
            DEFB    13
            DEFM    'Also: TAB n [SUSPEND/RESUME/EXCLUSIVE/KILL]'
            DEFB    13
            DEFM    'XSUB BYE  A:..P:  program [args]'
            DEFB    13
            DEFM    'SAVE n file.ext (after a transient)'
            DEFB    13
            DEFM    'Edit: ^S/^D left/right, ^G DEL, ^Q^S/^Q^D BOL/EOL'
            DEFB    13
            DEFM    'History: HIST lists, ^E/^X or Up/Down recalls, ^Y clears'
            DEFB    13,'$'
SAVEWARN    DEFM    'SAVE unavailable: AUX CCP overwrote transient RAM'
            DEFB    13,'$'
CMDPTR      DEFW    LINE
ARGPTR      DEFW    LINE
RENDST      DEFW    LINE
SVFPTR      DEFW    LINE
LNPTR       DEFW    LINE
LNCOUNT     DEFB    0
ALLOWW      DEFB    0
DIRCOL      DEFB    0
DIRDRIVE    DEFB    0
LINE        DEFS    124
FCB         DEFS    36
RENFCB      DEFS    36
DMA         DEFS    128
; Structure consumed by private F7: 36+16+16+128 = 196 bytes
EXPAR       DEFS    36
EXF1        DEFS    16
EXF2        DEFS    16
EXTAIL      DEFS    128

INBUF       DEFS    124                          ; dedicated BDOS 10 input buffer
BXID        DEFB    0
BXTAIL      DEFS    80                          ; private F8 MAIN command tail
BXFCB       DEFS    36                          ; F8/9 SAVE target, must follow BXTAIL
TABCAN      DEFS    20                          ; TAB action-first canonical arguments

; Stage 26: out-of-line F8/10 setup, safely beyond all CCP buffers.
; INBUF+1 is the count-byte destination; INBUF holds capacity on
; the physical-keyboard (BDOS 10) path.  SUBMIT may supply 120 chars;
; both INBUF and LINE have 124 bytes reserved in Stage 25.2.
RLSUBPTR    LD      HL,INBUF+1
            JP      RLSUBCALL

; Stage 28 command editor. No MAIN kernel changes are required.
; BDOS 6 / E=FF reads raw keys, so the supervisor still sees OA+hotkeys.
; Everything below belongs to the executing AUX session (independent history).
; Apple II: LEFT=08h, RIGHT=15h, UP=0Bh, DOWN=0Ah.
; WordStar: ^S/^D left/right, ^E/^X history, ^G delete,
;           ^Q^S start of line, ^Q^D end of line; DEL backspaces.
; Apple II's left arrow and ^H both produce 08h, so both move left.
; ^Y clears the line; ^C cancels without killing the CCP.
; History holds 10 entries of 75 chars (+ NUL in each 76-byte slot).
; Interactive editing still accepts up to 118 characters; history truncates
; commands longer than 75 chars so four tab histories fit in $0400-$0FFF.
;
EDSTART     XOR     A
            LD      (EDLEN),A
            LD      (EDPOS),A
            LD      (EDNAV),A
            LD      (EDPREFIX),A
            LD      (LINE),A
EDWAIT      LD      E,0FFH
            LD      C,6
            CALL    0005H
            OR      A
            JR      Z,EDWAIT
            CP      3
            JP      Z,EDCANCEL
            LD      B,A
            LD      A,(EDPREFIX)
            OR      A
            JR      Z,EDNORMKEY
            XOR     A
            LD      (EDPREFIX),A
            LD      A,B
            CP      13H                    ; ^Q ^S = beginning of line
            JP      Z,EDBOL
            CP      04H                    ; ^Q ^D = end of line
            JP      Z,EDEOL
            JP      EDWAIT
EDNORMKEY   LD      A,B
            CP      13
            JP      Z,EDENTER
            CP      11H                    ; ^Q prefix
            JR      NZ,EDOTHER
            LD      A,1
            LD      (EDPREFIX),A
            JR      EDWAIT
EDOTHER     CP      08H                    ; Apple II left arrow / ^H (same scan code)
            JP      Z,EDLEFT                ; DEL still backspaces
            CP      7FH                    ; Delete key
            JP      Z,EDBACK
            CP      13H                    ; ^S: left
            JP      Z,EDLEFT
            CP      04H                    ; ^D: right
            JP      Z,EDRIGHT
            CP      15H                    ; right arrow
            JP      Z,EDRIGHT
            CP      07H                    ; ^G: delete under cursor
            JP      Z,EDDELETE
            CP      05H                    ; ^E: previous history
            JP      Z,EDUP
            CP      0BH                    ; up arrow
            JP      Z,EDUP
            CP      18H                    ; ^X: next history
            JP      Z,EDDOWN
            CP      0AH                    ; down arrow
            JP      Z,EDDOWN
            CP      19H                    ; ^Y: clear line
            JP      Z,EDCLEAR
            CP      01H                    ; ^A: beginning (additional shortcut)
            JP      Z,EDBOL
            CP      06H                    ; ^F: end (additional shortcut)
            JP      Z,EDEOL
            CP      ' '
            JP      C,EDWAIT
            CP      07FH
            JP      NC,EDWAIT
            JP      EDINSERT
;
; Position changes only. Output existing character on right movement so
; Soroc needs no terminal-specific ESC sequences or cursor-addressing.
EDLEFT      LD      A,(EDPOS)
            OR      A
            JP      Z,EDWAIT
            DEC     A
            LD      (EDPOS),A
            LD      A,08H
            CALL    OUT
            JP      EDWAIT
EDRIGHT     LD      A,(EDPOS)
            LD      B,A
            LD      A,(EDLEN)
            CP      B
            JP      Z,EDWAIT
            LD      A,B
            LD      E,A
            LD      D,0
            LD      HL,LINE
            ADD     HL,DE
            LD      A,(HL)
            CALL    OUT
            LD      A,(EDPOS)
            INC     A
            LD      (EDPOS),A
            JP      EDWAIT
EDBOL       LD      A,(EDPOS)
            LD      B,A
            CALL    EDBS
            XOR     A
            LD      (EDPOS),A
            JP      EDWAIT
EDEOL       LD      A,(EDPOS)
            LD      B,A
            LD      A,(EDLEN)
            SUB     B
            LD      B,A
            LD      HL,LINE
            LD      A,(EDPOS)
            LD      E,A
            LD      D,0
            ADD     HL,DE
            CALL    EDSFX
            LD      A,(EDLEN)
            LD      (EDPOS),A
            JP      EDWAIT
;
; Insert at cursor, always in insert mode. Shift includes the terminating NUL.
EDINSERT    LD      (EDCHAR),A
            LD      A,(EDLEN)
            CP      118
            JP      NC,EDWAIT
            LD      E,A
            LD      D,0
            LD      HL,LINE
            ADD     HL,DE                 ; HL -> old NUL
            PUSH    HL
            POP     DE
            INC     DE                    ; DE -> shifted NUL
            LD      B,A
            LD      A,(EDPOS)
            LD      C,A
            LD      A,B
            SUB     C
            INC     A
            LD      C,A
            LD      B,0
            LDDR                          ; backwards copy, safe overlap
            LD      A,(EDPOS)
            LD      E,A
            LD      D,0
            LD      HL,LINE
            ADD     HL,DE
            LD      A,(EDCHAR)
            LD      (HL),A
            LD      A,(EDLEN)
            INC     A
            LD      (EDLEN),A
            LD      A,(EDPOS)
            INC     A
            LD      (EDPOS),A
            DEC     A                     ; original edit offset
            LD      E,A
            LD      D,0
            LD      HL,LINE
            ADD     HL,DE
            LD      C,A
            LD      A,(EDLEN)
            SUB     C
            LD      B,A
            CALL    EDSFX                ; rewrite inserted char and rest
            LD      A,(EDLEN)
            LD      B,A
            LD      A,(EDPOS)
            LD      C,A
            LD      A,B
            SUB     C
            LD      B,A
            CALL    EDBS                 ; put cursor after inserted char
            JP      EDWAIT
;
; DEL (^G) removes the character under the cursor, then redraws tail.
EDDELETE    LD      A,(EDPOS)
            LD      B,A
            LD      A,(EDLEN)
            CP      B
            JP      Z,EDWAIT
            LD      A,B
            LD      E,A
            LD      D,0
            LD      HL,LINE
            ADD     HL,DE
            PUSH    HL
            POP     DE                    ; DE -> LINE+pos
            INC     HL                    ; HL -> LINE+pos+1
            LD      A,(EDLEN)
            SUB     B                     ; include old NUL in copy
            LD      C,A
            LD      B,0
            LDIR
            LD      A,(EDLEN)
            DEC     A
            LD      (EDLEN),A
            LD      B,A
            LD      A,(EDPOS)
            LD      C,A
            LD      A,B
            SUB     C
            LD      B,A
            LD      E,C
            LD      D,0
            LD      HL,LINE
            ADD     HL,DE
            CALL    EDSFX
            LD      A,' '
            CALL    OUT                  ; clear old final column
            LD      A,(EDLEN)
            LD      B,A
            LD      A,(EDPOS)
            LD      C,A
            LD      A,B
            SUB     C
            INC     A
            LD      B,A
            CALL    EDBS
            JP      EDWAIT
EDBACK      LD      A,(EDPOS)
            OR      A
            JP      Z,EDWAIT
            DEC     A
            LD      (EDPOS),A
            LD      A,08H
            CALL    OUT
            JP      EDDELETE
;
; B=character count; HL -> starting bytes. OUT preserves BC, DE, HL.
EDSFX       LD      A,B
            OR      A
            RET     Z
EDSFL       LD      A,(HL)
            CALL    OUT
            INC     HL
            DJNZ    EDSFL
            RET
; Move the cursor left B positions without erasing any text.
EDBS        LD      A,B
            OR      A
            RET     Z
EDBSL       LD      A,08H
            CALL    OUT
            DJNZ    EDBSL
            RET
;
; EDCLEAR uses the same whole-line redraw as history navigation.
EDCLEAR     LD      HL,EDEMPTY
            CALL    EDREDRAW
            JP      EDWAIT
;
; Every history navigation redraws in-place; temporary draft is restored
; when moving down past newest history entry. No screen-wide repaint.
EDUP        LD      A,(EDCOUNT)
            OR      A
            JP      Z,EDWAIT
            LD      B,A
            LD      A,(EDNAV)
            CP      B
            JP      Z,EDWAIT
            OR      A
            JR      NZ,EDUPH
            LD      HL,LINE
            LD      DE,EDDRAFT
            LD      BC,120
            LDIR
EDUPH       LD      A,(EDNAV)
            INC     A
            LD      (EDNAV),A
            CALL    EDSELECT
            CALL    EDREDRAW
            JP      EDWAIT
EDDOWN      LD      A,(EDNAV)
            OR      A
            JP      Z,EDWAIT
            DEC     A
            LD      (EDNAV),A
            JR      NZ,EDDOWNH
            LD      HL,EDDRAFT
            JR      EDDOWNR
EDDOWNH     CALL    EDSELECT
EDDOWNR     CALL    EDREDRAW
            JP      EDWAIT
;
; Returns HL -> history[ (head - navigation + 10) % 10 ].
EDSELECT    LD      A,(EDHEAD)
            LD      B,A
            LD      A,(EDNAV)
            LD      C,A
            LD      A,B
            SUB     C
            JR      NC,EDSELP
            ADD     A,10
EDSELP      JP      EDGETPTR
;
; A=slot (0..9), HL=slot address.
EDGETPTR    LD      L,A
            LD      H,0
            ADD     HL,HL
            LD      DE,EDPTRS
            ADD     HL,DE
            LD      E,(HL)
            INC     HL
            LD      D,(HL)
            EX      DE,HL
            RET
;
; HL points to NUL-terminated replacement. EDPOS and EDLEN track
; current display. History includes fully normalized uppercase commands.
EDREDRAW    PUSH    HL
            LD      A,(EDPOS)
            LD      B,A
            CALL    EDBS
            LD      A,(EDLEN)
            LD      B,A
            LD      C,B
            LD      A,B
            OR      A
            JR      Z,EDRBSP
EDRSP       LD      A,' '
            CALL    OUT
            DJNZ    EDRSP
EDRBSP      LD      B,C
            CALL    EDBS
            POP     HL
            LD      DE,LINE
            LD      B,0
EDRCP       LD      A,(HL)
            LD      (DE),A
            OR      A
            JR      Z,EDRDONE
            CALL    OUT
            INC     HL
            INC     DE
            INC     B
            JR      EDRCP
EDRDONE     LD      A,B
            LD      (EDLEN),A
            LD      (EDPOS),A
            RET
;
; Uppercase only on Enter, keeping case as typed during editing.
EDENTER     LD      A,13
            CALL    OUT
            LD      HL,LINE
            LD      A,(EDLEN)
            LD      B,A
            LD      A,B
            OR      A
            RET     Z                     ; no history entry for blank commands
EDUPCASE    LD      A,(HL)
            CP      'a'
            JR      C,EDUCNEXT
            CP      'z'+1
            JR      NC,EDUCNEXT
            SUB     32
            LD      (HL),A
EDUCNEXT    INC     HL
            DJNZ    EDUPCASE
            CALL    EDADD
            CALL    EDSAVE
            RET
EDCANCEL    LD      A,13
            CALL    OUT
            XOR     A
            LD      (LINE),A
            RET
;
; Add every nonblank typed command to the ring. Kernel F8/11 persists this
; ring across transient reloads; editor remains tab-local between saves.
EDADD       LD      A,(EDHEAD)
            CALL    EDGETPTR
            EX      DE,HL                ; DE=history write slot
            LD      HL,LINE
            LD      BC,76
            LDIR
            DEC     DE                  ; last byte of destination history record
            XOR     A
            LD      (DE),A              ; ensure NUL for long (102+ byte) commands
            LD      A,(EDHEAD)
            INC     A
            CP      10
            JR      C,EDADDSLOT
            XOR     A
EDADDSLOT      LD      (EDHEAD),A
            LD      A,(EDCOUNT)
            CP      10
            RET     Z
            INC     A
            LD      (EDCOUNT),A
            RET
;
; No history slot crosses a bank. Dedicated AUX per-tab memory survives
; cooperative tab switches, not CCP re-execution after a .COM program.
HINDEX      DEFB    0           ; HIST output state (not persisted)
HNUMBER     DEFB    0
HLEFT       DEFB    0
EDLEN       DEFB    0
EDPOS       DEFB    0
EDNAV       DEFB    0
EDPREFIX    DEFB    0
EDCHAR      DEFB    0
EDEMPTY     DEFB    0
EDPTRS      DEFW    EDH0,EDH1,EDH2,EDH3,EDH4
            DEFW    EDH5,EDH6,EDH7,EDH8,EDH9
EDDRAFT     DEFS    120
EDHEAD      DEFB    0           ; F8/11-12 persists 762 bytes from EDHEAD
EDCOUNT     DEFB    0
EDH0        DEFS    76
EDH1        DEFS    76
EDH2        DEFS    76
EDH3        DEFS    76
EDH4        DEFS    76
EDH5        DEFS    76
EDH6        DEFS    76
EDH7        DEFS    76
EDH8        DEFS    76
EDH9        DEFS    76

; Private F8 11/12 transfer the 762-byte history block to/from reserved
; screen-bank AUX storage, one 768-byte slot per logical session.
; Not part of the SAVE snapshot, the TPA, or the display buffer.
; Restore into a scratch area first. The kernel must not replace the
; live editor ring while its F8 call is still on the AUX call stack.
; F8/12 returns A=1 only when a valid per-tab snapshot was transferred.
EDRESTORE   LD      A,12
            LD      HL,EDTEMP
            CALL    EDTRANSFER
            CP      1
            RET     NZ                    ; new tab: leave initial empty ring
            LD      A,(EDTEMP)            ; EDHEAD: next slot, 0..9
            CP      10
            RET     NC
            LD      A,(EDTEMP+1)          ; EDCOUNT: populated slots, 0..10
            CP      11
            RET     NC
            LD      HL,EDTEMP
            LD      DE,EDHEAD
            LD      BC,762
            LDIR                          ; now fully in AUX, no bank switching
            ; Unused history slots may contain assembler DEFS fill bytes.
            ; All slots get a terminal NUL to bound editor redraw/recall.
            LD      HL,EDH0+75
            LD      DE,76
            LD      B,10
            XOR     A
EDRNUL      LD      (HL),A
            ADD     HL,DE
            DJNZ    EDRNUL
            RET
EDSAVE      LD      A,11
            LD      HL,EDHEAD
EDTRANSFER  LD      (BXID),A
            LD      (BXTAIL),HL
            LD      DE,BXID
            LD      C,0F8H
            CALL    0005H
            RET

; Temporary restore destination: never read during normal editing.
; 2 bytes of metadata + ten 76-byte command slots = 762 bytes.
EDTEMP      DEFS    762
