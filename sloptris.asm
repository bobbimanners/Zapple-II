; SLOPTRIS.COM - minimalist CP/M Tetris for Zapple-II.
; Supports SOROC and VT100 output, selected on startup.
; Udo Munk z80asm 1.1: z80asm -osloptris.bin SLOPTRIS.ASM
; Strip the three-byte FF 00 01 origin header to make SLOPTRIS.COM
; 10 x 20 board displayed as 20 x 20 character cells (2 chars per block).
; Controls: Apple II LEFT/RIGHT = move, UP = rotate, DOWN = soft drop;
;           SPACE = hard drop, P = pause/resume, Q = quit.
; Solid inverse-video spaces.  The original Soroc drawing engine is
; translated at the output boundary for VT100 (no duplicate draw code).
; BIOS CONST/CONIN polling, no interrupts.
; VT100 cursor keys ESC [ A/B/C/D and ESC O A/B/C/D are recognised.
;
        org     0100h

start:  ld      (oldsp),sp
        ld      sp,stktop
        call    initkeys
        call    trmopts         ; terminal-selection menu before clear
        call    vthide          ; hide VT100 cursor while playing
        ld      hl,board
        ld      de,board+1
        ld      bc,199
        ld      (hl),0
        ldir
        xor     a
        ld      (lines),a
        ld      (dead),a
        ld      a,01h
        ld      (seed),a
        ld      a,10
        ld      (tick),a
        xor     a
        ld      (prevdraw),a
        call    randkind
        ld      (nextkind),a
        call    frame
        call    score
        call    spawn
        ld      a,(dead)
        or      a
        jp      nz,gameover
        ld      a,'#'
        call    sprite

main:   call    delay
        call    gamekey         ; raw BIOS input plus VT100 cursor decoder
        or      a
        jr      z,mtick
        cp      ' '
        jp      z,harddrop
        cp      08h             ; Apple II left arrow
        jr      z,keyleft
        cp      15h             ; Apple II right arrow
        jr      z,keyright
        cp      0bh             ; Apple II up arrow
        jr      z,keyturn
        cp      0ah             ; Apple II down arrow
        jr      z,keydown
        and     0dfh            ; ASCII lowercase -> uppercase
        cp      'Q'
        jp      z,quit
        cp      'P'
        jp      z,pause
        cp      'A'
        jr      z,keyleft
        cp      'D'
        jr      z,keyright
        cp      'W'
        jr      z,keyturn
        cp      'S'
        jr      z,keydown
mtick:  ld      a,(tick)
        dec     a
        ld      (tick),a
        jr      nz,main
        ld      a,10
        ld      (tick),a
        call    gravity
        ld      a,(dead)
        or      a
        jp      nz,gameover
        jp      main

keyleft:
        call    prep
        ld      a,(tx)
        dec     a
        ld      (tx),a
        call    attempt
        jr      mtick
keyright:
        call    prep
        ld      a,(tx)
        inc     a
        ld      (tx),a
        call    attempt
        jr      mtick
keyturn:
        call    prep
        ld      a,(tr)
        inc     a
        and     3
        ld      (tr),a
        call    attempt
        jr      mtick
keydown:
        call    gravity
        ld      a,(dead)
        or      a
        jp      nz,gameover
        jp      main

; Try candidate tx,ty,tr.  Screen stays intact if invalid.
attempt:
        call    hit
        ret     nz
        ld      a,' '
        call    sprite
        call    install
        ld      a,'#'
        call    sprite
        ret

; Each gravity step either moves down or settles a piece.
gravity:
        call    prep
        ld      a,(ty)
        inc     a
        ld      (ty),a
        call    hit
        jr      nz,settle
        ld      a,' '
        call    sprite
        call    install
        ld      a,'#'
        call    sprite
        ret

; Hard drop draws only at start and final position.
harddrop:
        ld      a,' '
        call    sprite
hdloop: call    prep
        ld      a,(ty)
        inc     a
        ld      (ty),a
        call    hit
        jr      nz,hdend
        call    install
        jr      hdloop
hdend:  ld      a,'#'
        call    sprite
        call    settle
        ld      a,(dead)
        or      a
        jp      nz,gameover
        jp      main

; Move current piece into locked board, clear complete rows.
settle: call    lock
        call    sweep
        call    spawn
        ld      a,(dead)
        or      a
        ret     nz
        ld      a,'#'
        call    sprite
        ret

 ; Spawn the previously previewed piece, replace the preview once.
; Keep preview unchanged throughout movement/gravity of current piece.
spawn:  ld      a,(nextkind)
        ld      (kind),a
        ld      a,(prevdraw)
        or      a
        jr      z,spnew
        ld      a,' '
        call    preview           ; erase OLD preview before changing nextkind
spnew:  call    randkind
        ld      (nextkind),a
        ld      a,'#'
        call    preview           ; show NEXT piece as inverse spaces
        ld      a,1
        ld      (prevdraw),a
        xor     a
        ld      (rot),a
        ld      (py),a
        ld      a,3
        ld      (px),a
        call    prep
        call    hit
        ret     z
        ld      a,1
        ld      (dead),a
        ret

; Pseudorandom shape 0..6, based on Z80 refresh counter.
randkind:
        ld      a,(seed)
        rrca
        xor     0b8h
        ld      b,a
        ld      a,r
        xor     b
        ld      (seed),a
        and     7
        cp      7
        ret     nz
        xor     a
        ret

prep:   ld      a,(px)
        ld      (tx),a
        ld      a,(py)
        ld      (ty),a
        ld      a,(rot)
        ld      (tr),a
        ret
install:
        ld      a,(tx)
        ld      (px),a
        ld      a,(ty)
        ld      (py),a
        ld      a,(tr)
        ld      (rot),a
        ret

; HL -> four packed block offsets for candidate type/orientation.
; Each packed byte = (dy << 4) | dx, with 0<=dx,dy<=3.
shapept:
        ld      a,(kind)
        add     a,a
        add     a,a
        add     a,a
        add     a,a
        ld      b,a
        ld      a,(tr)
        add     a,a
        add     a,a
        add     a,b
        ld      e,a
        ld      d,0
        ld      hl,shapes
        add     hl,de
        ret

; Convert row A, column C (0..9) to address HL within board.
; Clobbers A,B,D,E.
cellptr:
        add     a,a             ; 2*y
        ld      d,a
        add     a,a             ; 4*y
        add     a,a             ; 8*y
        add     a,d             ; 10*y
        add     a,c
        ld      e,a
        ld      d,0
        ld      hl,board
        add     hl,de
        ret

; Decode packed A to candidate cell cx,cy.
; No assumptions about range (hit checks bounds first).
decode: ld      c,a
        and     0fh
        ld      e,a
        ld      a,(tx)
        add     a,e
        ld      (cx),a
        ld      a,c
        rrca
        rrca
        rrca
        rrca
        and     0fh
        ld      e,a
        ld      a,(ty)
        add     a,e
        ld      (cy),a
        ret

; Candidate collision: Z=clear, NZ=blocked.
hit:    call    shapept
        ld      b,4
hitloop:
        ld      a,(hl)
        call    decode
        ld      a,(cx)
        cp      10
        jr      nc,hitbad
        ld      a,(cy)
        cp      20
        jr      nc,hitbad
        push    bc
        push    hl
        ld      a,(cx)
        ld      c,a
        ld      a,(cy)
        call    cellptr
        ld      a,(hl)
        pop     hl
        pop     bc
        or      a
        jr      nz,hitbad
        inc     hl
        djnz    hitloop
        xor     a
        ret
hitbad:
        ld      a,1
        or      a
        ret

 ; Video state is set ONCE per four-cell sprite (not per cell).
; A='#' draws inverse spaces, A=' ' erases with normal spaces.
; Soroc ESC ')' / ESC '(' is supported by Zapple-II's 6502 driver.
setvideo:
        cp      ' '
        jr      z,voff
        ld      de,invon
        jp      putstr
voff:   ld      de,invoff
        jp      putstr

; Draw/erase four live cells with four cursor packets, two spaces each.
sprite: call    setvideo
        ld      a,(tx)         ; preserve candidate of move being tested
        ld      (savtx),a
        ld      a,(ty)
        ld      (savty),a
        ld      a,(tr)
        ld      (savtr),a
        call    prep
        call    shapept
        ld      b,4
sploop: ld      a,(hl)
        call    decode
        ld      a,(cy)
        add     a,34            ; board row 0 -> screen row 2 -> ASCII+32
        ld      (onebuf+2),a
        ld      a,(cx)
        add     a,a             ; two screen columns per cell
        add     a,62            ; board col 0 -> screen col 30 -> ASCII+32
        ld      (onebuf+3),a
        push    bc
        push    hl
        ld      de,onebuf
        call    putstr
        pop     hl
        pop     bc
        inc     hl
        djnz    sploop
        ld      a,(savtx)
        ld      (tx),a
        ld      a,(savty)
        ld      (ty),a
        ld      a,(savtr)
        ld      (tr),a
        ld      de,invoff      ; don't leave status text inverse
        jp      putstr

; Paint four preview cells as two-column blocks starting at x=58, y=4..7.
; Uses nextkind and rotation zero, without touching active piece state.
preview:
        call    setvideo
        ld      a,(nextkind)
        add     a,a
        add     a,a
        add     a,a
        add     a,a
        ld      e,a
        ld      d,0
        ld      hl,shapes
        add     hl,de
        ld      b,4
prloop: ld      a,(hl)
        ld      c,a
        and     0fh
        add     a,a             ; two screen columns per cell
        add     a,90            ; preview starts at screen column 58
        ld      (onebuf+3),a
        ld      a,c
        rrca
        rrca
        rrca
        rrca
        and     0fh
        add     a,36            ; screen row 4 -> ASCII 36
        ld      (onebuf+2),a
        push    bc
        push    hl
        ld      de,onebuf
        call    putstr
        pop     hl
        pop     bc
        inc     hl
        djnz    prloop
        ld      de,invoff
        jp      putstr

; Store live piece blocks into board.
lock:   call    prep
        call    shapept
        ld      b,4
lkloop: ld      a,(hl)
        call    decode
        push    bc
        push    hl
        ld      a,(cx)
        ld      c,a
        ld      a,(cy)
        call    cellptr
        ld      (hl),1
        pop     hl
        pop     bc
        inc     hl
        djnz    lkloop
        ret

; Check bottom-up; repeat a row after removing it (multi-line clears).
sweep:  xor     a
        ld      (changed),a
        ld      a,19
        ld      (scanrow),a
swrow:  ld      a,(scanrow)
        ld      c,0
        call    cellptr
        ld      b,10
swtest: ld      a,(hl)
        or      a
        jr      z,swnext
        inc     hl
        djnz    swtest
        ld      a,1
        ld      (changed),a
        ld      a,(lines)
        inc     a
        ld      (lines),a
        call    shiftdn
        jr      swrow          ; check same row again
swnext: ld      a,(scanrow)
        or      a
        jr      z,swdone
        dec     a
        ld      (scanrow),a
        jr      swrow
swdone: ld      a,(changed)
        or      a
        ret     z
        call    redraw
        call    score
        ret

; Remove scanrow: LDDR copies earlier rows down 10 bytes, then blank row 0.
shiftdn:
        ld      a,(scanrow)
        or      a
        jr      z,szero
        add     a,a
        ld      d,a
        add     a,a
        add     a,a
        add     a,d             ; A = row*10, fits in 8 bits
        ld      c,a
        ld      b,0
        ld      hl,board-1
        add     hl,bc           ; source = board + row*10 - 1
        push    hl
        ld      de,10
        add     hl,de
        ex      de,hl           ; dest = source + 10
        pop     hl
        lddr
szero:  ld      hl,board
        ld      b,10
        xor     a
szloop: ld      (hl),a
        inc     hl
        djnz    szloop
        ret

 ; Redraw only after cleared lines: one cursor move per row.
; Build a mixed normal/inverse row buffer, toggling only when needed.
; Worst case 4 + (10*4) + 2 + 1 = 47 bytes.
redraw: xor     a
        ld      (drawrow),a
rdrow:  ld      a,(drawrow)
        ld      c,0
        call    cellptr
        ld      de,rowbuf+4
        ld      b,10
        xor     a
        ld      (rmode),a
rdbit:  ld      a,(hl)
        or      a
        jr      z,rdempty
        ld      a,(rmode)
        or      a
        jr      nz,rdcont
        ld      a,27
        ld      (de),a
        inc     de
        ld      a,')'
        ld      (de),a
        inc     de
        ld      a,1
        ld      (rmode),a
        jr      rdcont
rdempty:
        ld      a,(rmode)
        or      a
        jr      z,rdcont
        ld      a,27
        ld      (de),a
        inc     de
        ld      a,'('
        ld      (de),a
        inc     de
        xor     a
        ld      (rmode),a
rdcont:
        ld      a,' '
        ld      (de),a
        inc     de
        ld      (de),a          ; second character of the same cell
        inc     de
        inc     hl
        djnz    rdbit
        ld      a,(rmode)
        or      a
        jr      z,rdend
        ld      a,27
        ld      (de),a
        inc     de
        ld      a,'('
        ld      (de),a
        inc     de
rdend:  ld      a,'$'
        ld      (de),a
        ld      a,(drawrow)
        add     a,34
        ld      (rowbuf+2),a
        ld      de,rowbuf
        call    putstr
        ld      a,(drawrow)
        inc     a
        ld      (drawrow),a
        cp      20
        jr      nz,rdrow
        ret

; Initialise centred screen with 20-column-wide interior (22 total). No updates to border in play.
frame:  ld      de,clearstr
        call    putstr
        ld      de,header
        call    putstr
        ld      de,topbar
        call    putstr
        ld      de,nextlbl
        call    putstr
        xor     a
        ld      (drawrow),a
frrow:  ld      a,(drawrow)
        add     a,34
        ld      (frmbuf+2),a
        ld      de,frmbuf
        call    putstr
        ld      a,(drawrow)
        inc     a
        ld      (drawrow),a
        cp      20
        jr      nz,frrow
        ld      de,botbar
        call    putstr
        ret

score:  ld      a,(lines)
        ld      b,'0'
sc100:  cp      100
        jr      c,sc10
        sub     100
        inc     b
        jr      sc100
sc10:   ld      (scoretmp),a
        ld      a,b
        ld      (scline+10),a
        ld      a,(scoretmp)
        ld      b,'0'
sc10a:  cp      10
        jr      c,sc1
        sub     10
        inc     b
        jr      sc10a
sc1:   ld      (scoretmp),a
        ld      a,b
        ld      (scline+11),a
        ld      a,(scoretmp)
        add     a,'0'
        ld      (scline+12),a
        ld      de,scline
        jp      putstr

pause:  ld      de,pausmsg
        call    putstr
paw:    call    getkey
        and     0dfh
        cp      'P'
        jr      nz,paw
        ld      de,unpause
        call    putstr
        jp      main

gameover:
        ld      de,overmsg
        call    putstr
        jp      exit
quit:   ld      de,quitmsg
        call    putstr
exit:   call    vtshow          ; restore cursor on QUIT and GAME OVER
        ld      sp,(oldsp)
        ret

; VT100 cursor visibility is terminal state, independent of SOROC.
; Use BDOS 9 directly: the sequences are already ANSI, not Soroc data.
; Escape sequences: ESC [ ? 25 l (hide), ESC [ ? 25 h (show).
vthide: ld      a,(term)
        or      a
        ret     z
        ld      de,hidecur
        ld      c,9
        jp      0005h
vtshow: ld      a,(term)
        or      a
        ret     z
        ld      de,showcur
        ld      c,9
        jp      0005h

; Terminal choice is local to SLOPTRIS; no system TERM changes.
; Menu uses plain ASCII CR/LF so it works on either type of terminal.
trmopts:
        xor     a
        ld      (term),a
        ld      (escstat),a
        ld      de,trmmsg
        call    putstr
trmwait:
        call    getkey
        or      a
        jr      z,trmwait
        cp      '2'
        jr      z,trmvt
        cp      '1'
        ret     z
        cp      13
        jr      nz,trmwait
        ret
trmvt:  ld      a,1
        ld      (term),a
        ret

; Decode ANSI/VT100 cursor keys while preserving the original Apple II
; one-byte arrow codes and A/D/W/S controls.  State survives no-key polls.
; ESC [ A/B/C/D and application keypad ESC O A/B/C/D both work.
gamekey:
        call    getkey
        or      a
        ret     z
        ld      b,a
        ld      a,(escstat)
        or      a
        jr      z,gknorm
        cp      1
        jr      nz,gkfinal
        ld      a,b
        cp      '['
        jr      z,gkarm
        cp      'O'
        jr      z,gkarm
        xor     a
        ld      (escstat),a
        ret
gkarm:  ld      a,2
        ld      (escstat),a
        xor     a
        ret
gkfinal:
        xor     a
        ld      (escstat),a
        ld      a,b
        cp      'A'
        jr      z,gkup
        cp      'B'
        jr      z,gkdown
        cp      'C'
        jr      z,gkright
        cp      'D'
        jr      z,gkleft
        xor     a
        ret
gkup:   ld      a,0bh
        ret
gkdown: ld      a,0ah
        ret
gkright:
        ld      a,15h
        ret
gkleft: ld      a,08h
        ret
gknorm:
        ld      a,b
        cp      27
        jr      nz,gkret
        ld      a,1
        ld      (escstat),a
        xor     a
        ret
gkret: ld      a,b
        ret

; SOROC uses the original fast BDOS-9 output path below.
; VT100 translates the same small drawing streams into a 160-byte
; scratch buffer, then outputs them with a *single* BDOS-9 call.
; This handles cursor bytes equal to '$' (screen row/column 4) too.
putstr: ld      a,(term)
        or      a
        jp      nz,putansi
        jp      putsor

putansi:
        ld      hl,anbuf
anloop: ld      a,(de)
        cp      '$'
        jr      z,anend
        cp      27
        jr      z,anesc
        ld      (hl),a
        inc     hl
        inc     de
        jr      anloop
anesc:  inc     de
        ld      a,(de)
        cp      '*'
        jr      z,ancls
        cp      '='
        jr      z,anpos
        cp      ')'
        jr      z,aninv
        cp      '('
        jr      z,annorm
        ; Preserve unknown escapes rather than silently dropping them.
        ld      a,27
        ld      (hl),a
        inc     hl
        ld      a,(de)
        ld      (hl),a
        inc     hl
        inc     de
        jr      anloop
ancls:  push    de
        ld      de,aclear
        call    ancopy
        pop     de
        inc     de
        jr      anloop
aninv:  push    de
        ld      de,ainvon
        call    ancopy
        pop     de
        inc     de
        jr      anloop
annorm: push    de
        ld      de,ainvoff
        call    ancopy
        pop     de
        inc     de
        jr      anloop
anpos:  push    de
        ld      de,acsi
        call    ancopy
        pop     de
        inc     de              ; Soroc row + 32
        ld      a,(de)
        sub     31              ; VT100 row is 1-based
        call    andec
        ld      a,3bh           ; Udo assembler: use hex for ';'
        ld      (hl),a
        inc     hl
        inc     de              ; Soroc column + 32
        ld      a,(de)
        sub     31
        call    andec
        ld      a,'H'
        ld      (hl),a
        inc     hl
        inc     de
        jr      anloop
anend:  ld      (hl),'$'
        ld      de,anbuf
        ld      c,9
        jp      0005h

; Copy a zero-terminated ANSI fragment DE -> HL; caller saves input DE.
ancopy: ld      a,(de)
        or      a
        ret     z
        ld      (hl),a
        inc     hl
        inc     de
        jr      ancopy

; Print A (0..99) as one or two decimal digits at (HL); advances HL.
andec:  ld      c,'0'
anded0: cp      10
        jr      c,anded1
        sub     10
        inc     c
        jr      anded0
anded1: ld      b,a
        ld      a,c
        cp      '0'
        jr      z,anded2
        ld      (hl),a
        inc     hl
anded2: ld      a,b
        add     a,'0'
        ld      (hl),a
        inc     hl
        ret

; BDOS 9 is fast, but its '$' terminator conflicts with Soroc's
; row/column byte 36 (= screen row or column 4).  Fall back to four
; BDOS 2 calls for that cursor prefix, then use BDOS 9 for the payload.
; This keeps output minimal AND handles all 20 board rows/columns.
putsor: ld      a,(de)
        cp      27
        jr      nz,pfast
        inc     de
        ld      a,(de)
        dec     de
        cp      '='
        jr      nz,pfast
        push    de
        inc     de
        inc     de
        ld      a,(de)
        cp      '$'
        jr      z,pslow
        inc     de
        ld      a,(de)
        cp      '$'
        jr      z,pslow
        pop     de
pfast:  ld      c,9
        jp      0005h
pslow:  pop     de
        ld      b,4
psloop: push    bc
        push    de
        ld      a,(de)
        ld      e,a
        ld      c,2
        call    0005h
        pop     de
        inc     de
        pop     bc
        djnz    psloop
        ld      c,9
        jp      0005h

; Fetch BIOS CONST/CONIN entry addresses using CP/M's WBOOT vector.
; In Zapple-II, (0001h) -> AUX BIOS WBOOT at DF03h, so CONST
; and CONIN follow at WBOOT+3 and WBOOT+6.  This avoids relying
; on BDOS 6 polling, and works with raw Apple II arrow characters.
initkeys:
        ld      hl,(0001h)
        ld      de,3
        add     hl,de
        ld      (keyconst+1),hl
        add     hl,de
        ld      (keyin+1),hl
        ret

; Returns A=0 if no key, otherwise 7-bit key; no echo.
getkey:
keyconst:
        call    0000h          ; patched to BIOS CONST
        or      a
        ret     z
keyin:  call    0000h          ; patched to BIOS CONIN
        and     07fh
        ret

delay:  ld      bc,3500        ; tune for Zapple-II/SoftCard speed
waitlp: dec     bc
        ld      a,b
        or      c
        jr      nz,waitlp
        ret

; Seven pieces, four 4-cell rotations each, packed as dy:dx.
; Rotating L/J/T/S/Z in a 3x3 square; I in a 4x4 square.
shapes:
; I: ---- / #### / ---- / ----
        DEFB 10h,11h,12h,13h
        DEFB 02h,12h,22h,32h
        DEFB 20h,21h,22h,23h
        DEFB 01h,11h,21h,31h
; O
        DEFB 01h,02h,11h,12h
        DEFB 01h,02h,11h,12h
        DEFB 01h,02h,11h,12h
        DEFB 01h,02h,11h,12h
; T
        DEFB 01h,10h,11h,12h
        DEFB 01h,11h,12h,21h
        DEFB 10h,11h,12h,21h
        DEFB 01h,10h,11h,21h
; S
        DEFB 01h,02h,10h,11h
        DEFB 00h,10h,11h,21h
        DEFB 11h,12h,20h,21h
        DEFB 01h,11h,12h,22h
; Z
        DEFB 00h,01h,11h,12h
        DEFB 02h,11h,12h,21h
        DEFB 10h,11h,21h,22h
        DEFB 01h,10h,11h,20h
; J
        DEFB 00h,10h,11h,12h
        DEFB 01h,02h,11h,21h
        DEFB 10h,11h,12h,22h
        DEFB 01h,11h,20h,21h
; L
        DEFB 02h,10h,11h,12h
        DEFB 01h,11h,21h,22h
        DEFB 10h,11h,12h,20h
        DEFB 00h,01h,11h,21h

; VT100 DECTCEM: hide cursor during gameplay, restore on exit.
; These strings use BDOS 9 ($ terminator), not the ANSI fragment copier.
hidecur:DEFB 27
        DEFM '[?25l'
        DEFB '$'
showcur:DEFB 27
        DEFM '[?25h'
        DEFB '$'

; ANSI byte fragments are NUL-terminated (not CP/M '$'-terminated).
acsi:   DEFB 27,'[',0
aclear: DEFB 27
        DEFM '[2J'
        DEFB 27
        DEFM '[H'
        DEFB 0
ainvon: DEFB 27
        DEFM '[7m'
        DEFB 0
ainvoff:DEFB 27
        DEFM '[0m'
        DEFB 0
trmmsg:DEFB 13,10
        DEFM 'SLOPTRIS - terminal selection'
        DEFB 13,10
        DEFM '1 - SOROC / Apple II'
        DEFB 13,10
        DEFM '2 - VT100 / Telnet'
        DEFB 13,10
        DEFM 'Choice [1]: $'

clearstr:
        DEFB 27,'*','$'
header: DEFB 27,'=',32,32
        DEFM 'SLOPTRIS  LEFT/RIGHT=move  UP=rotate  DOWN=down  SPACE=drop  P=pa'
        DEFM 'use Q=quit'
        DEFB '$'
nextlbl:
        DEFB 27,'=',34,89
        DEFM 'NEXT:'
        DEFB '$'
invon:  DEFB 27,')','$'
invoff: DEFB 27,'(','$'
topbar: DEFB 27,'=',33,61
        DEFM '+--------------------+'
        DEFB '$'
botbar: DEFB 27,'=',54,61
        DEFM '+--------------------+'
        DEFB '$'
frmbuf: DEFB 27,'=',34,61
        DEFM '|                    |'
        DEFB '$'
rowbuf: DEFB 27,'=',34,62
        DEFS 48 ; max row contents with inverse transitions
onebuf: DEFB 27,'=',34,62,' ',' ','$'
scline: DEFB 27,'=',55,33
        DEFM 'LINES 000'
        DEFB '$'
pausmsg:
        DEFB 27,'=',55,50
        DEFM 'PAUSED  (P to resume)'
        DEFB '$'
unpause:
        DEFB 27,'=',55,50
        DEFM '                     '
        DEFB '$'
overmsg:DEFB 27,'=',55,50
        DEFM 'GAME OVER'
        DEFB '$'
quitmsg:DEFB 27,'=',55,50
        DEFM 'QUIT'
        DEFB '$'

term:   DEFB 0 ; 0=Soroc, 1=VT100
escstat:DEFB 0 ; ANSI input sequence state
anbuf:  DEFS 160 ; worst translated row fits comfortably
oldsp:  DEFW 0
px:     DEFB 0
py:     DEFB 0
rot:    DEFB 0
kind:   DEFB 0
tx:     DEFB 0
ty:     DEFB 0
tr:     DEFB 0
cx:     DEFB 0
cy:     DEFB 0
savtx:  DEFB 0
savty:  DEFB 0
savtr:  DEFB 0
nextkind:DEFB 0
prevdraw:DEFB 0
rmode:  DEFB 0
seed:   DEFB 1
tick:   DEFB 0
scoretmp:DEFB 0
lines:  DEFB 0
dead:   DEFB 0
changed:DEFB 0
scanrow:DEFB 0
drawrow:DEFB 0
board:  DEFS 200
        DEFS 128 ; local stack
stktop:
        end
