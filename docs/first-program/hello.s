; hello.s - your first online 6502 program (trail-net, docs/FIRST-PROGRAM.md): say HI to the server, print the answer.
; Ophis:  ophis hello.s -o HELLO      then, on a ProDOS disk with BASIC.SYSTEM, NET.bin saved as NET (BIN), from the
; 40-column prompt:   BLOAD NET,A$4000    BRUN HELLO
.alias  AUXMOVE $C311           ; the //e's firmware: copy A1..A2 to A4, main to aux memory when the carry is set
.alias  COUT    $FDED           ; the ROM: print a character
.alias  CROUT   $FD8E           ; the ROM: a new line
.alias  NET_BUF $6824           ; where the NET file answers, in main memory (drivers/net_top.s, as shipped)
.alias  KEEP    $0300           ; BASIC's zero page $60-$6F while the NET file uses it
        .org $6000
        ldx #15
save:   lda $60,x
        sta KEEP,x
        dex
        bpl save
        ldx #0                  ; three copies into aux memory: this program, the NET file, the line
move:   ldy #0
mv:     lda moves,x             ; A1 from, A2 to, A3 (unused), A4 where: zero page $3C-$43
        sta $3C,y
        inx
        iny
        cpy #8
        bne mv
        txa
        pha
        sec                     ; main to aux
        jsr AUXMOVE
        pla
        tax
        cpx #24
        bne move
        lda #0                  ; PROBE: find the card (a CoGS card first)
        jsr net
        bcs fail
        lda #1                  ; LINE: send the line, read one line back
        jsr net
        bcs fail
        ldx #0
show:   lda NET_BUF,x           ; the answer: OK <server> <time> <message>
        beq done
        ora #$80
        jsr COUT
        inx
        bne show
fail:   ldx #0
fl:     lda nolink,x
        beq done
        ora #$80
        jsr COUT
        inx
        bne fl
done:   jsr CROUT
        ldx #15
rest:   lda KEEP,x
        sta $60,x
        dex
        bpl rest
        rts
net:    sta $3C                 ; the operation
        sta $C003               ; read aux memory: the next byte comes from aux, where this program was copied too
        sta $C005               ; write aux memory
        jsr $3A00               ; the NET file
        sta $C002               ; main memory again (STA leaves the carry as the NET file set it)
        sta $C004
        rts
moves:  .word $6000, end, 0, $6000              ; this program (the four lines above must be in both banks)
        .word $4000, $45FF, 0, $3A00            ; the NET file, BLOADed at $4000
        .word line, line+10, 0, $AFA0           ; the line, where LINE reads it
line:   .byte "HI FIRST 1", 0
nolink: .byte "NO LINK", 0
end:
