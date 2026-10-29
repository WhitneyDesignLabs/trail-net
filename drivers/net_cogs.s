; net_cogs.s — E5b: the CoGS card's second half (its first, the probe and the byte read, is net.s's tail). A title's NET
; file includes it after NET.CFG (independence/src/net_top.s: aux $3EF8 up, to $3FFF at most).
; The card (a2cogs.com, Rev 3.2: a Pico 2 W and a W5500; DHCP, DNS, TCP and TLS are the card's) speaks in frames both
; ways, [op][length low][length high][payload] (reference/cogs/techref.txt ch. 3-5). Socket 0, plain TCP. Each line is a
; connection of its own: CLOSE and CONNECT to NET.CFG's server (its address as text: the card parses it), CONNECTED, then
; the line as one SEND. The answer comes back as DATA frames ($91: the socket byte, then the bytes), read as one stream;
; every other frame (CLOSE's and SEND's answers, an ERROR, a link event) is read and dropped. The protocol has no time
; limit of its own (the card answers every command); every wait here is net.s's 2 s. No write waits for room: a line
; writes under 120 bytes and the card's FIFO is 4 KB.

; cg_drain — LINE's first step (nt_drain, kind 3): the card's FIFO flushed (an answer to an old line), then CLOSE and
; CONNECT built in NT_RX - the fixed bytes, the port low byte first, the server as text ("158.101.9.238") - and written.
; Carry clear: CONNECTED, result 0.
cg_drain:
        ldx nt_iol
        lda #$04                ; CONTROL: the card's FIFO flushed
        sta $C004,x             ; (cg_left: cd_w's first frame sets it)
        ldy #8
cd_t:   lda cg_tpl,y
        sta NT_RX,y
        dey
        bpl cd_t
        lda nt_conf+23          ; the port (NET.CFG's high byte first)
        sta NT_RX+9
        lda nt_conf+22
        sta NT_RX+10
        ldy #12                 ; the host from NT_RX+12: four numbers and dots
        ldx #0
cd_q:   stx NZ_Y
        lda nt_conf+18,x
        jsr cg_num
        lda #'.
        sta NT_RX,y
        iny
        ldx NZ_Y
        inx
        cpx #4
        bne cd_q
        dey                     ; (no dot after the last; carry set by the cpx)
        tya
        sbc #12
        sta NT_RX+11            ; the host's length
        adc #4                  ; (carry set) CONNECT's length: socket, flags, port, the length byte, the host
        sta NT_RX+5
        sty NZ_N                ; the bytes to write
        ldy #0
        ldx nt_iol
cd_o:   lda NT_RX,y
        sta $C000,x             ; (an indexed store's dummy read of DATA: the card puts that byte back, techref 2.5)
        iny
        cpy NZ_N
        bne cd_o
cd_w:   jsr cg_frame            ; until CONNECTED (CLOSE's answer, and anything else, dropped)
        bcs cd_x
        cmp #$90
        beq cd_c
        jsr cg_skip
        bcc cd_w
cd_x:   rts
cd_c:   jsr cg_pop              ; its socket
        jsr cg_pop              ; its result: 0, open (carry clear)
        beq cd_x
        sec
        rts

; cg_flush — LINE's last step (nt_flush, kind 3): the line (NT_TX, 0-ended, at most 79) and a CR as one SEND on socket 0,
; its frame's head written in front of the line (NT_TX-4: the pattern player's free $AF9C), the CR over the line's 0
cg_flush:
        ldy #0
cf_n:   lda NT_TX,y
        beq cf_e
        iny
        cpy #79
        bne cf_n
cf_e:   lda #$0D
        sta NT_TX,y
        iny
        iny                     ; SEND's length: the socket byte, the line, the CR
        sty NT_TX-3
        lda #$11
        sta NT_TX-4
        lda #0
        sta NT_TX-2
        sta NT_TX-1
        iny
        iny
        iny
        sty NZ_N                ; the frame's bytes: its head and the payload
        ldy #0
        ldx nt_iol
cf_o:   lda NT_TX-4,y
        sta $C000,x
        iny
        cpy NZ_N
        bne cf_o
        clc
        rts

; cg_get — a byte of the answer in A (nt_get, kind 3): socket 0's DATA frames read through; carry set when none came in
; about 2 s. A CR is dropped: the LF of the server's CR LF ends a line, so the answer's last line leaves no byte of its
; frame behind. The card's slot ROM shares this FIFO: a ProDOS call to its units (the engine's look for a side, Gate C
; on the //e) read a leftover LF as a frame's head and never came back.
cg_get: ldx nt_iol
cg_g:   lda cg_left
        ora cg_left+1
        beq cg_f
        jsr cg_pop
        bcs cg_x
        cmp #$0D
        beq cg_g
        clc                     ; (the cmp's carry: a byte came)
        rts
cg_f:   jsr cg_frame
        bcs cg_x
        cmp #$91                ; DATA: the socket byte, then the bytes
        bne cg_s
        jsr cg_pop
        jmp cg_g
cg_s:   jsr cg_skip
        bcc cg_f
cg_x:   rts

; cg_frame — a frame's head: A = its op, cg_left its payload's length; carry set when none came in 2 s
cg_frame:
        jsr cg_rd
        bcs cfr_x
        pha
        jsr cg_rd
        sta cg_left
        jsr cg_rd
        sta cg_left+1
        pla
cfr_x:  rts
; cg_pop — the frame's next byte in A (its Z / N set); carry set when none came
cg_pop: lda cg_left
        bne cpo_d
        dec cg_left+1
cpo_d:  dec cg_left
        jmp cg_rd
; cg_skip — the rest of the frame read and dropped (carry clear when it was all there)
cg_skip:
        lda cg_left
        ora cg_left+1
        beq ck_x
        jsr cg_pop
        bcc cg_skip
ck_x:   rts
