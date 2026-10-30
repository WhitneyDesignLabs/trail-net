# Your first online 6502 program, on the CoGS card

This page is a short program, about fifty lines of 6502 assembly, that an Apple IIe runs to say hello to a server on
the internet and print what the server says back. It uses this repository's network drivers exactly as they ship and a
server you run on your own PC. Nothing in the cloud is needed. The CoGS card is the easiest way to run it: it does the
Wi-Fi or Ethernet, DHCP and TCP itself, so the Apple only has to say where the server is.

What you will see on the Apple, after two commands:

    ]BLOAD NET,A$4000
    ]BRUN HELLO
    OK TRAILSRV0 2026-10-30T14:57:29Z LIGHTS ARE ON
    ]

## What you need

- **An Apple IIe with 128K** (an extended 80-column card), enhanced or not, or a IIc / IIgs. The program borrows the
  auxiliary 64K.
- **A CoGS card**, in any slot but 6 (slot 7 is usual), on the same network as your PC. No CoGS card? The same program
  runs on a Super Serial Card or an Uthernet II: see "Other cards" at the end.
- **A ProDOS disk with BASIC.SYSTEM** on it: any ProDOS 2.4 system disk will do. You will add two files to it.
- **A PC** with:
  - Python 3, to run the server;
  - the Ophis assembler (github.com/michaelcmartin/Ophis);
  - a way to put files on an Apple disk image: AppleCommander, or CiderPress II;
  - a way to get the image to the Apple: a Floppy Emu, ADTPro, or the CoGS card's own disk mounting.

## 1. Run the server on your PC

From this repository's folder:

    python server/trail_server.py

It answers on TCP port 6502 and keeps its data in `trail.db` in the folder you started it from. It prints one line when
it starts and one for each connection.

Find your PC's address on your network (`ipconfig` on Windows, `ip addr` on Linux): say `192.168.1.10`. If the PC has a
firewall, let TCP port 6502 in.

## 2. Tell the drivers where the server is

The drivers keep the server's address in the NET file's last bytes (`drivers/NET-FILE.md`, "NET.CFG"). As shipped they
point at INDEPENDENCE's public server, `158.101.9.238`, port 6502. To use your own, edit `drivers/net_conf.inc`. The
line holds 24 numbers; the server is the four bytes after the Apple's own IP, then the port, high byte first.

    ; gateway       mask              MAC (Uthernet II)           Apple's IP        server IP          port 6502
    nt_conf: .byte $C0,$A8,$01,$01, $FF,$FF,$FF,$00, $00,$08,$DC,$A2,$65,$02, $C0,$A8,$01,$FA, $C0,$A8,$01,$0A, $19,$66

Here the server is `$C0,$A8,$01,$0A`: 192.168.1.10 in hexadecimal. The CoGS card reads only the server and port, and
finds its own address by DHCP. (Skip this step to talk to the public server instead: HELLO works the same.)

## 3. Build the two files

    OPHIS=<path to ophis> bash drivers/build.sh            # -> drivers/NET.bin, 1,532 bytes
    ophis docs/first-program/hello.s -o HELLO              # -> HELLO, 157 bytes

## 4. Put them on the disk

With AppleCommander (`ac.jar`), into a copy of your ProDOS disk:

    java -jar ac.jar -p first.po NET BIN 0x4000 < drivers/NET.bin
    java -jar ac.jar -p first.po HELLO BIN 0x6000 < HELLO

## 5. Run it

Boot the disk to BASIC's `]` prompt, in 40 columns (no PR#3), and type:

    BLOAD NET,A$4000
    BRUN HELLO

The answer appears a moment later, and the server's window shows the visit:

    14:57:05 #1 open
    14:57:29 #1 HI -> OK (0 ms)

`NO LINK` instead means the card was not found or the server did not answer within about two seconds:
- Is the server running, and is port 6502 open in the PC's firewall?
- Is the address in `net_conf.inc` the PC's, and did you rebuild NET.bin after changing it?

## The program

`docs/first-program/hello.s`, whole:

```
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
```

## How it works, part by part

**The zero page.** The NET file uses zero page `$60-$6F` while it runs, and BASIC keeps its program's pointers there.
The program saves those sixteen bytes first and puts them back last, so BASIC never notices.

**Three copies into auxiliary memory.** The NET file runs in the Apple's second 64K, the auxiliary bank. The //e's
firmware has a routine for copying there, AUXMOVE at `$C311`: put the first address in `$3C`, the last in `$3E`, the
destination in `$42`, set the carry, and call it. The program uses it three times, from the table `moves`:
1. **The program itself, to the same addresses.** That is the trick in `net`, below.
2. **The NET file**, from where BLOAD put it (`$4000`) to `$3A00`, where it runs.
3. **The line to send**, "HI FIRST 1", to `$AFA0`, where the NET file reads it.

**The trampoline, `net`.** Switching the read bank (`STA $C003`, RAMRD) changes where the very next instruction comes
from. That is why the program copied itself into the auxiliary bank first: the switch lands in an identical copy, which
calls the NET file at `$3A00`, then switches back to main memory with `STA $C002` and `$C004`. STA does not change the
carry, so the NET file's answer (carry clear: it worked) survives the trip.

**Two operations.** The operation goes in zero page `$3C`:
1. **0, PROBE**, finds the card: a CoGS card first, then a Super Serial Card, then an Uthernet II.
2. **1, LINE**, sends the line and a carriage return, and waits for one line back.

**The answer.** The NET file writes the answer into main memory at `$6824` (NET_BUF), ending with a zero, and the
program prints it with the ROM's COUT. The server's HI answer is `OK`, the server's name, the time in UTC and its
message of the day.

## Next steps

- **Change the line.** `TIME` answers with the time, `RND` with a true random number, `COUNT` with the wall's count.
  `../PROTOCOL.md` lists every command. Keep the line within 79 characters, and change `line+10` to the line's length.
- **Read more than one line.** `WALL` answers with several lines. Call operation 2, NEXT, after LINE, until the line
  reads `END`.
- **Use the numbers.** The NET file also puts the answer's first four numbers at `NET_BUF+82`, sixteen bits each, so a
  program can use `OK 12 57` without parsing it.
- **Add a command.** The server is one Python file (`server/trail_server.py`); its commands are in one function. Add
  your own, and your Apple program has a new thing to ask.

## Other cards

The program does not change: PROBE finds whichever card is there.

- **A Super Serial Card**, with the PC on its cable. Run the relay beside the server:

      python server/ssc_relay.py --port COM3 --server 127.0.0.1:6502

  The relay passes each line to the server and the answer back, so NET.CFG does not matter.
- **AppleWin on the same PC.** Use its Super Serial Card in slot 2 on one end of a virtual serial pair (com0com:
  COM5 and COM6), with the relay on the other end (`--port COM6`).
- **An Uthernet II.** It needs every address in `net_conf.inc`: the Apple's own IP, the mask, the gateway and the
  server.

## How this page was checked

- **AppleWin 1.32, with a Super Serial Card.** The listing above, assembled, and the NET file built by `drivers/build.sh`
  as shipped. The program ran against `trail_server.py` on the same PC through `ssc_relay.py` and printed the answer at
  the top of this page.
- **The CoGS card, as a model.** AppleWin has no CoGS card, so the CoGS path was run in a 6502 simulator, with a model
  of the card built from its Technical Reference: PROBE found the card in slot 7, the card connected to the server named
  in NET.CFG, the server got `HI FIRST 1`, and the answer was printed.
- **Not yet on a real CoGS card.** Running it on one is the first thing the video shows.
