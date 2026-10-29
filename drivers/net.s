; net.s — E5-B: the network layer's auxiliary side, the head of a title's NET file (aux PL_NET, $3A00; read through STAGE
; by the main side's net_mount, at most 1,920 B). The engine reaches it through the pattern player's PLE_NET (drwplay.s
; e_net), which switches 80STORE OFF around the call: $3A00-$3FFF is inside $2000-$3FFF, which with 80STORE and HIRES
; on would be MAIN's HGR page whatever RAMRD says (Known Quirk 39); with it off, RAMRD / RAMWRT (on: the stub's) make it
; this file's own. The code touches the card's I/O ($C080-$C0FF, the slots' ROM bytes for the probe), its own buffers
; (NT_RX at $3980, NT_TX at $AFA0) and the main side's block NET_BUF, written with RAMWRT switched off for the store (the code keeps
; running from aux: RAMRD stays on). Zero page $3C-$95 is the player's (put back on exit): this file uses $60-$6F in it.
; NMOS 6502 only. Never more than about 2 s on the wire; a link that does not answer is NO LINK, never a hang.
;   P_SRC 0  PROBE   find a link: NET_BUF+NB_KIND / +NB_SLOT (0 = none); carry clear when found. E5b: a CoGS card
;                    first (its ID register), then the Super Serial Card (its firmware's ID bytes), then (E5-D) an
;                    Uthernet II: a W5100 in indirect mode, found by a write and read back of its registers in a slot
;                    with no ProDOS block device and not slot 6
;   P_SRC 1  LINE    send NT_TX (0-ended, the main side put it there) and a CR, then read one line back (LINE's read)
;   P_SRC 2  NEXT    read one more line (WALL's and NOTES' records): into NET_BUF, 0-ended, at most 76 characters
;   P_SRC 3  CLOSE   the link idle again (the SSC: nothing; a socket: closed)
;   carry set: no link, or no line within the time (the line is empty)
; The main side's block NET_BUF (the title says where: INDEPENDENCE's is GAMEDATA's free $6820): +0 the line (80 B),
; +80 the link's kind (0 none, 1 SSC, 2 Uthernet II, 3 CoGS), +81 its slot, +82 the line's numbers (E5-C: four 16-bit values,
; low byte first, 0 when absent: each a run of digits after a space - OK 12 57, N 3 - so the main side needs no parser).
        .include "net_env.inc"           ; (trail-net: the two constants it needs; in INDEPENDENCE, the engine's drwplay.inc)
.alias  NB_LINE   0
.alias  NB_KIND   80
.alias  NB_SLOT   81
.alias  NB_NUMS   82
.alias  NT_TX     $AFA0         ; the line to send (0-ended, 80 B; the main side's AUXMOVE: E5-E, out of $2000-$3FFF - Known
                              ;   Quirk 39 - into the pattern player's free $AF9C-$AFFF)
.alias  NT_RX     $3980         ; the line read (0-ended; E5b: under the file, in Parser 2.0's margin - its work area
                              ;   ends at wa_end, $3792 now: the build checks it stays under $3980; the file may run to $3FFF)
.alias  NT_MAX    76            ; the protocol's longest line
.alias  NZ_IO     $60           ; 2: the card's I/O ($C088 + 16 x slot for the SSC)
.alias  NZ_T      $62           ; 3: the timeout's count
.alias  NZ_Y      $65
.alias  NZ_N      $66           ; 2: a number being read
.alias  NZ_A      $68           ; 2: its value before the digit (x 10)
.alias  NZ_D      $6A           ; the digit
.alias  KIND_NONE 0
.alias  KIND_SSC  1
.alias  KIND_W5100 2
.alias  KIND_COGS 3
.alias  NZ_W      $6B           ; 2: the W5100's TX write / RX read pointer being moved

        .org PL_NET
nt_entry:
        lda nt_iol              ; the card's I/O into zero page (the player put the zero page back after the last call)
        sta NZ_IO
        lda nt_ioh
        sta NZ_IO+1
        lda P_SRC
        cmp #4
        bcs nt_no
        asl
        tax
        lda nt_ops+1,x
        pha
        lda nt_ops,x
        pha
        rts
nt_ops: .word cg_probe-1, nt_line-1, nt_next-1, nt_close-1
nt_no:  sec
        rts

;---------------------------------------------------------------
; PROBE — the slots 1-7, the Super Serial Card by its firmware's ID bytes (the Pascal 1.1 protocol: $Cn05 $38, $Cn07 $18,
; $Cn0B $01, $Cn0C $31 - the SSC, AppleWin's and the Pico card's alike). Found: it is reset and set to 9600 baud, 8N1.
;---------------------------------------------------------------
nt_probe:
        ldx #1
np_lp:  txa
        ora #$C0
        sta NZ_IO+1
        lda #0
        sta NZ_IO
        ldy #$05
        lda (NZ_IO),y
        cmp #$38
        bne np_nx
        ldy #$07
        lda (NZ_IO),y
        cmp #$18
        bne np_nx
        ldy #$0B
        lda (NZ_IO),y
        cmp #$01
        bne np_nx
        ldy #$0C
        lda (NZ_IO),y
        cmp #$31
        beq np_ssc
np_nx:  inx
        cpx #8
        bne np_lp
        jmp w_probe             ; E5-D: no SSC: an Uthernet II?
np_ssc: stx NZ_Y
        txa                     ; the 6551 at $C088 + 16 x slot
        asl
        asl
        asl
        asl
        ora #$88
        sta nt_iol
        sta NZ_IO
        lda #$C0
        sta nt_ioh
        sta NZ_IO+1
        jsr ssc_init
        lda #KIND_SSC
        ldx NZ_Y
        jsr nt_kind
        clc
        rts
; nt_kind — A = the kind, X = the slot: into main's NET_BUF (RAMWRT off for the two stores; the code runs on in aux)
nt_kind:
        sta $C004
        sta NET_BUF+NB_KIND
        stx NET_BUF+NB_SLOT
        sta $C005
        sta nt_k
        rts

;---------------------------------------------------------------
; LINE / NEXT / CLOSE
;---------------------------------------------------------------
nt_line:
        lda nt_k
        beq nt_fail
        jsr nt_drain            ; nothing stale in front of the answer (E5-D: and the W5100's socket open)
        bcs nt_fail
        ldy #0
nl_tx:  lda NT_TX,y
        beq nl_cr
        sty NZ_Y
        jsr nt_put
        bcs nt_fail
        ldy NZ_Y
        iny
        cpy #79                 ; (a request may run to 79: REG with five names of eight; a reply is cut at NT_MAX)
        bne nl_tx
nl_cr:  lda #$0D
        jsr nt_put
        bcs nt_fail
        jsr nt_flush            ; (the W5100: the line is one SEND)
        bcs nt_fail
nt_next:
        lda nt_k
        beq nt_fail
        jsr nt_read             ; one line into NT_RX
        php
        jsr nt_give             ; and into main's NET_BUF (empty when it failed)
        plp
        rts
nt_fail:
        lda #0
        sta NT_RX
        jsr nt_give
        sec
        rts
nt_close:                       ; (E5b: a CoGS socket is closed by the next line's CLOSE, or the server's idle time)
        lda nt_k
        cmp #KIND_W5100
        bne nc_x
        lda #$08                ; the socket: DISCON, then CLOSE (the next line opens it again)
        jsr w_cmd
        lda #$10
        jsr w_cmd
nc_x:   sec
        rts

; the kind's own byte out / in / drain / flush (E5-D): the SSC's, the W5100's or (E5b) the CoGS card's
nt_put: ldx nt_k
        cpx #KIND_W5100
        beq w_putj
        bcs nf_c                ; (CoGS: nothing - cg_flush sends the line whole)
        jmp ssc_put
w_putj: jmp w_put
nt_get: ldx nt_k
        cpx #KIND_W5100
        beq w_getj
        bcs cg_getj
        jmp ssc_get
w_getj: jmp w_get
cg_getj:
        jmp cg_get
nt_drain:
        ldx nt_k
        cpx #KIND_W5100
        beq w_drainj
        bcs cg_drainj
        jsr ssc_drain
nf_c:   clc
        rts
w_drainj:
        jmp w_drain
cg_drainj:
        jmp cg_drain
nt_flush:
        ldx nt_k
        cpx #KIND_W5100
        beq w_flushj
        bcs cg_flushj
        clc
        rts
w_flushj:
        jmp w_flush
cg_flushj:
        jmp cg_flush

; nt_read — a line from the link into NT_RX, 0-ended: CR or LF ends it (a LF or CR before any character is skipped),
; at most NT_MAX characters kept; carry set when no character came for 2 s
nt_read:
        ldy #0
nr_lp:  sty NZ_Y
        jsr nt_get
        ldy NZ_Y
        bcs nr_to
        and #$7F
        cmp #$0D
        beq nr_eol
        cmp #$0A
        beq nr_eol
        cpy #NT_MAX
        bcs nr_lp               ; (past the protocol's width: dropped)
        sta NT_RX,y
        iny
        bne nr_lp
nr_eol: cpy #0
        beq nr_lp               ; (the LF of a CR LF, or an empty line)
        lda #0
        sta NT_RX,y
        clc
        rts
nr_to:  lda #0
        sta NT_RX,y
        sec
        rts

; nt_give — NT_RX into main's NET_BUF line, and its numbers (E5-C) into NET_BUF+NB_NUMS (RAMWRT off: the stores go to
; main; the reads stay aux's, so a number is built in zero page and stored whole)
nt_give:
        sta $C004
        ldy #0
ng_lp:  lda NT_RX,y
        sta NET_BUF+NB_LINE,y
        beq ng_end
        iny
        cpy #NT_MAX+1
        bne ng_lp
ng_end: ldx #7
        lda #0
nn_z:   sta NET_BUF+NB_NUMS,x
        dex
        bpl nn_z
        ldx #0                  ; X = the next number's offset (0, 2, 4, 6)
        ldy #0
nn_lp:  lda NT_RX,y
        beq nn_end
        iny
        cmp #$20
        bne nn_lp
        lda NT_RX,y             ; a space: a digit next starts a number
        sec
        sbc #'0
        cmp #10
        bcs nn_lp
        lda #0
        sta NZ_N
        sta NZ_N+1
nd_lp:  lda NT_RX,y
        sec
        sbc #'0
        cmp #10
        bcs nd_end
        sta NZ_D
        lda NZ_N                ; N = N x 10 + the digit
        sta NZ_A
        lda NZ_N+1
        sta NZ_A+1
        asl NZ_N
        rol NZ_N+1
        asl NZ_N
        rol NZ_N+1
        lda NZ_N
        clc
        adc NZ_A
        sta NZ_N
        lda NZ_N+1
        adc NZ_A+1
        sta NZ_N+1
        asl NZ_N
        rol NZ_N+1
        lda NZ_N
        clc
        adc NZ_D
        sta NZ_N
        bcc nd_nc
        inc NZ_N+1
nd_nc:  iny
        bne nd_lp
nd_end: lda NZ_N
        sta NET_BUF+NB_NUMS,x
        lda NZ_N+1
        sta NET_BUF+NB_NUMS+1,x
        inx
        inx
        cpx #8
        bcc nn_lp
nn_end: sta $C005
        rts

;---------------------------------------------------------------
; the Super Serial Card: a 6551 ACIA at nt_io (data +0, status +1, command +2, control +3)
;---------------------------------------------------------------
ssc_init:
        ldy #1
        sta (NZ_IO),y           ; a write to the status register: the programmed reset
        ldy #3
        lda #$1E                ; control: 9600 baud (1110), 8 bits (00), one stop bit
        sta (NZ_IO),y
        ldy #2
        lda #$0B                ; command: no parity, the transmitter on (RTS low), no interrupts, DTR on
        sta (NZ_IO),y
        rts
; ssc_put — A out; carry set when the transmitter stayed busy for the timeout (a card that never sends)
ssc_put:
        pha
        jsr nt_arm
sp_w:   ldy #1
        lda (NZ_IO),y
        and #$10                ; TDRE
        bne sp_go
        jsr nt_tick
        bcc sp_w
        pla
        rts                     ; (carry set)
sp_go:  pla
        ldy #0
        sta (NZ_IO),y
        clc
        rts
; ssc_get — a byte in A; carry set when none came in about 2 s
ssc_get:
        jsr nt_arm
sg_w:   ldy #1
        lda (NZ_IO),y
        and #$08                ; RDRF
        bne sg_go
        jsr nt_tick
        bcc sg_w
        rts
sg_go:  ldy #0
        lda (NZ_IO),y
        clc
        rts
; ssc_drain — whatever is waiting is read and dropped
ssc_drain:
        ldy #1
        lda (NZ_IO),y
        and #$08
        beq sd_x
        ldy #0
        lda (NZ_IO),y
        jmp ssc_drain
sd_x:   rts

;---------------------------------------------------------------
; E5-D: the Uthernet II - a WIZnet W5100 in indirect mode at $C084 + 16 x slot: +0 MR, +1 / +2 the register address
; (high, low), +3 the data (the address moves on by itself: MR's AI). Socket 0, TCP, to the server of nt_conf. A line
; is written into the socket's 2 KB TX buffer ($4000) and sent whole (SEND); bytes come back from its RX buffer
; ($6000) one at a time (RECV after each: the protocol's lines are short). A socket that is not ESTABLISHED is opened
; again before a line (CONNECT, inside the 2 s); none: no link for this line.
;---------------------------------------------------------------
w_probe:
        ldx #0
wp_lp:  stx NZ_Y
        lda wp_slots,x
        beq wp_none
        sta NZ_D                ; (the slot)
        ora #$C0                ; a ProDOS block device's ROM ($Cn01 $20, $Cn03 $00, $Cn05 $03) is never touched
        sta NZ_IO+1
        lda #0
        sta NZ_IO
        ldy #$01
        lda (NZ_IO),y
        cmp #$20
        bne wp_try
        ldy #$03
        lda (NZ_IO),y
        bne wp_try
        ldy #$05
        lda (NZ_IO),y
        cmp #$03
        beq wp_nx
wp_try: lda NZ_D
        asl
        asl
        asl
        asl
        ora #$84
        sta NZ_IO
        lda #$C0
        sta NZ_IO+1
        ldy #0
        lda #$80                ; MR: reset
        sta (NZ_IO),y
        lda #$03                ; MR: indirect, the address moving on
        sta (NZ_IO),y
        lda (NZ_IO),y
        cmp #$03
        bne wp_nx
        lda #$00                ; the gateway register: $55 $AA written, read back
        ldx #$01
        jsr w_at
        lda #$55
        jsr w_wr
        lda #$AA
        jsr w_wr
        lda #$00
        ldx #$01
        jsr w_at
        jsr w_rd
        cmp #$55
        bne wp_nx
        jsr w_rd
        cmp #$AA
        beq wp_got
wp_nx:  ldx NZ_Y
        inx
        bne wp_lp
wp_none:
        lda #KIND_NONE
        ldx #0
        jsr nt_kind
        sec
        rts
wp_got: lda NZ_IO
        sta nt_iol
        lda NZ_IO+1
        sta nt_ioh
        lda #$00                ; the addresses: gateway, mask, MAC, IP ($0001-$0012, one run)
        ldx #$01
        jsr w_at
        ldx #0
wg_c:   lda nt_conf,x
        jsr w_wr
        inx
        cpx #18
        bne wg_c
        lda #$00                ; RMSR, TMSR: 2 KB a socket
        ldx #$1A
        jsr w_at
        lda #$55
        jsr w_wr
        lda #$55
        jsr w_wr
        lda #KIND_W5100
        ldx NZ_D
        jsr nt_kind
        clc
        rts
wp_slots: .byte 5, 4, 7, 3, 2, 1, 0      ; (6 never: the Disk II's)

; w_at — A / X = a register's address (high / low); w_wr — A into it (the address moves on); w_rd — A from it
w_at:   ldy #1
        sta (NZ_IO),y
        iny
        txa
        sta (NZ_IO),y
        rts
w_wr:   ldy #3
        sta (NZ_IO),y
        rts
w_rd:   ldy #3
        lda (NZ_IO),y
        rts
; w_cmd — A = a socket-0 command into S0_CR, then the W5100 takes it (S0_CR 0 again)
w_cmd:  pha
        lda #$04
        ldx #$01
        jsr w_at
        pla
        jsr w_wr
wc_w:   lda #$04
        ldx #$01
        jsr w_at
        jsr w_rd
        bne wc_w
        rts
; w_sr — A = S0_SR (the socket's state)
w_sr:   lda #$04
        ldx #$03
        jsr w_at
        jmp w_rd
; w_drain — the socket ESTABLISHED (opened and connected again if not: carry set when it will not), and whatever waits
; in it read and dropped
w_drain:
        jsr w_sr
        cmp #$17                ; ESTABLISHED
        beq wd_lp
        lda #$10                ; CLOSE, then OPEN as TCP from local port $C000 + a count, CONNECT to nt_conf's server
        jsr w_cmd
        lda #$04
        ldx #$00
        jsr w_at
        lda #$01                ; S0_MR: TCP
        jsr w_wr
        lda #$04
        ldx #$04
        jsr w_at
        lda #$C0
        jsr w_wr
        inc nt_lport
        lda nt_lport
        jsr w_wr
        lda #$01                ; OPEN
        jsr w_cmd
        lda #$04                ; the server: S0_DIPR, S0_DPORT ($040C-$0411)
        ldx #$0C
        jsr w_at
        ldx #0
wd_d:   lda nt_conf+18,x
        jsr w_wr
        inx
        cpx #6
        bne wd_d
        lda #$04                ; CONNECT
        jsr w_cmd
        jsr nt_arm
wd_c:   jsr w_sr
        cmp #$17
        beq wd_lp
        cmp #$00                ; CLOSED: refused
        beq wd_no
        jsr nt_tick
        bcc wd_c
wd_no:  sec
        rts
wd_lp:  jsr w_rsr
        beq wd_ok
        jsr w_byte
        jmp wd_lp
wd_ok:  lda #$04                ; and the TX write pointer, for the line to come
        ldx #$24
        jsr w_at
        jsr w_rd
        sta NZ_W+1
        jsr w_rd
        sta NZ_W
        clc
        rts
; w_put — A into the TX buffer at the write pointer (sent by w_flush)
w_put:  pha
        lda NZ_W+1
        and #$07
        ora #$40
        ldx NZ_W
        jsr w_at
        pla
        jsr w_wr
        inc NZ_W
        bne wpu_x
        inc NZ_W+1
wpu_x:  clc
        rts
; w_flush — the write pointer back into S0_TX_WR, and SEND
w_flush:
        lda #$04
        ldx #$24
        jsr w_at
        lda NZ_W+1
        jsr w_wr
        lda NZ_W
        jsr w_wr
        lda #$20                ; SEND
        jsr w_cmd
        clc
        rts
; w_rsr — Z clear when S0_RX_RSR says a byte waits
w_rsr:  lda #$04
        ldx #$26
        jsr w_at
        jsr w_rd
        sta NZ_A
        jsr w_rd
        ora NZ_A
        rts
; w_get — a byte in A from the socket; carry set when none came in about 2 s
w_get:  jsr nt_arm
wgt_w:  jsr w_rsr
        bne w_byte
        jsr nt_tick
        bcc wgt_w
        rts
; w_byte — one byte from the RX buffer at S0_RX_RD, the pointer on, RECV
w_byte: lda #$04
        ldx #$28
        jsr w_at
        jsr w_rd
        sta NZ_W+1
        jsr w_rd
        sta NZ_W
        lda NZ_W+1
        and #$07
        ora #$60
        ldx NZ_W
        jsr w_at
        jsr w_rd
        pha
        inc NZ_W
        bne wb_n
        inc NZ_W+1
wb_n:   lda #$04
        ldx #$28
        jsr w_at
        lda NZ_W+1
        jsr w_wr
        lda NZ_W
        jsr w_wr
        lda #$40                ; RECV
        jsr w_cmd
        pla
        clc
        rts
; nt_conf (the title's top file, after this file: independence/src/net_top.s) — E5-D: the Uthernet II's addresses
; (data/net.txt → net_conf.inc, tools/build/make-netconf.py): gateway, subnet mask, MAC, the Apple's IP (18 B, the
; W5100's $0001-$0012 in that order), then the server's IP and port (6 B)
nt_lport: .byte 0

; the timeout: nt_arm sets about 2 s - the kind's own count of waits (nt_tmo: the SSC's loop is ~30 cycles a wait,
; 65,536 waits; the W5100's reads its registers, ~70: fewer; the CoGS card's ~31, as the SSC's); nt_tick counts one and
; sets carry at zero. Both keep A and X (E5b: cg_rd's register index); nt_arm clobbers Y.
nt_arm: lda #0
        sta NZ_T
        ldy nt_k
        lda nt_tmo,y
        sta NZ_T+1
        lda #NT_SECS2
        sta NZ_T+2
        rts
nt_tmo: .byte 0, 0, $5A, 0             ; (the W5100's: py65 measured 2.50 s at $70)
nt_tick:
        dec NZ_T
        bne nk_go
        dec NZ_T+1
        bne nk_go
        dec NZ_T+2
        beq nk_out
nk_go:  clc
        rts
nk_out: sec
        rts
.alias  NT_SECS2  1             ; 65,536 waits of ~30 cycles: about 2 s at 1 MHz

nt_iol: .byte 0                 ; the card's I/O, kept here between calls
nt_ioh: .byte 0
nt_k:   .byte 0                 ; the link's kind (0 = none)
cg_left: .byte 0, 0             ; E5b: the CoGS frame's payload bytes not yet read

;---------------------------------------------------------------
; E5b: the CoGS card, its first half (here, under NET.CFG); the second is engine/src/net_cogs.s, after NET.CFG (the
; title's top file includes it there: independence/src/net_top.s). The card's registers are $C000,x with X = nt_iol
; ($80 + 16 x slot): DATA +0, STATUS +1 (bit 7: a byte waits for the host), CONTROL +4, ID +5, VERSION +6
; (reference/cogs/techref.txt ch. 2).
;---------------------------------------------------------------
; cg_probe — PROBE's first look: slots 7 down to 1, never 6 (the Disk II's: its I/O moves the head) or 0 (the language
; card's switches). A CoGS card reads ID $A2, a VERSION, and a STATUS that is not an empty slot's floating $FF (techref
; 2.3). Found: both FIFOs flushed, kind 3. None: the Super Serial Card, then an Uthernet II (nt_probe). The CoGS card
; is looked for first: an SSC in another slot would win, and the Uthernet probe's writes to +4 are a CoGS soft reset.
cg_probe:
        ldx #$F0
cp_lp:  cpx #$E0
        beq cp_nx
        lda $C005,x
        cmp #$A2
        bne cp_nx
        lda $C006,x
        beq cp_nx
        lda $C001,x
        cmp #$FF
        bne cp_got
cp_nx:  txa
        sec
        sbc #$10
        tax
        cpx #$80
        bne cp_lp
        jmp nt_probe
cp_got: stx nt_iol
        lda #$0C                ; CONTROL: the host's FIFO and the card's flushed, the frame parser reset
        sta $C004,x             ; (an indexed store's dummy read of +4 is LINKQ's: no side effect)
        txa
        lsr
        lsr
        lsr
        lsr
        and #$07
        tax
        lda #KIND_COGS
        jsr nt_kind
        clc
        rts
; cg_rd — a byte from the card in A, its Z / N set (X = nt_iol); carry set when none came in about 2 s
cg_rd:  jsr nt_arm
cr_w:   lda $C001,x
        bmi cr_go
        jsr nt_tick
        bcc cr_w
        rts
cr_go:  lda $C000,x
        clc
        rts
; cg_num — A (0-255) as decimal digits into NT_RX at Y (Y moved on): no leading zero (the card's address parser would
; read 009 as octal). X, NZ_N clobbered.
cg_num: ldx #2
cn_f:   cmp cg_pow,x            ; the powers above the value make no digit
        bcs cn_d
        dex
        bne cn_f
cn_d:   pha
        lda #'0-1
        sta NZ_N
        pla
        sec
cn_s:   inc NZ_N
        sbc cg_pow,x
        bcs cn_s
        adc cg_pow,x            ; (one too many: back again, carry set)
        pha
        lda NZ_N
        sta NT_RX,y
        iny
        pla
        dex
        bpl cn_d
        rts
cg_pow: .byte 1, 10, 100
; the frames' fixed bytes: CLOSE socket 0, then CONNECT's head (its length, socket 0, flags 0: plain TCP)
cg_tpl: .byte $12, 1, 0, 0, $10, 0, 0, 0, 0
