# The NET file: what a client calls

`NET.bin` (`build.sh`, 1,532 bytes) is the network layer of INDEPENDENCE and HOME.BASE's engine: three card drivers
behind one entry point. This page is everything a new 6502 program needs to call it. The engine around it is not part
of this repository.

## Where it lives and how it is called

- **Loading.** Load the file into **auxiliary memory at `$3A00`**. It may run to `$3FFF`.
- **Calling.** Put the operation in **zero page `$3C`** and **JSR `$3A00`**, running in auxiliary memory: RAMRD and
  RAMWRT on (`$C003`, `$C005`).
- **80STORE off.** It must be off for the call (`$C000`). With 80STORE and HIRES on, `$2000-$3FFF` is main memory's
  hi-res page whatever RAMRD says, and the file would read the picture instead of itself.
- **Your caller** is a few bytes that switch the banks, set `$3C`, call, and switch back. INDEPENDENCE's goes through
  its picture player, which already runs in auxiliary memory.
- **Zero page `$60-$6F`** is the file's own while it runs. Save it first if your program uses it.
- **NMOS 6502 only.** Every wait is about 2 seconds at 1 MHz: a card that does not answer is "no link", never a hang.

## The operations (`$3C`)

| Op | Name | Does | Carry |
|---|---|---|---|
| 0 | PROBE | finds a card and sets it up; writes its kind and slot into NET_BUF | clear: found |
| 1 | LINE | sends the line at aux `$AFA0` (0-ended, at most 79 characters) and a CR, then reads one reply line | clear: a reply came |
| 2 | NEXT | reads the next line of a reply of several lines (WALL, NOTES) | clear: a line came |
| 3 | CLOSE | lets the link go idle (the Uthernet II's socket is closed; the others need nothing) | - |

The reply goes into **NET_BUF**, a 120-byte block in **main** memory at an address the program chooses (`net_top.s`
`NET_BUF`; INDEPENDENCE's is `$6824`). The file writes it with RAMWRT switched off for the stores:

| Offset | What |
|---|---|
| +0 | the reply line, 0-ended, at most 76 characters (empty when there was none) |
| +80 | the link's kind: 0 none, 1 Super Serial Card, 2 Uthernet II, 3 CoGS |
| +81 | its slot |
| +82 | the reply's first four numbers, 16 bits each, low byte first (`OK 12 57` gives 12 and 57; 0 when absent) |

The line to send goes in at aux `$AFA0` (the firmware's AUXMOVE, `$C311`, does it). The file reads the reply into aux
`$3980` first, then copies it out.

## Which card (PROBE's order)

1. **A CoGS card**, in slot 7 down to 1, never 6 or 0. Its ID register (`$C085 + 16 x slot`) reads `$A2`, it has a
   VERSION, and its STATUS is not `$FF`.
2. **A Super Serial Card**, in slots 1-7, found by its firmware's ID bytes: `$Cn05 = $38`, `$Cn07 = $18`,
   `$Cn0B = $01`, `$Cn0C = $31` (AppleWin's and the A2Pico's SSC firmware answer the same). It is reset to 9600 baud,
   8N1. A PC on its cable runs `../server/ssc_relay.py`.
3. **An Uthernet II** (a W5100 in indirect mode), in slots 5, 4, 7, 3, 2, 1. Never slot 6, and never a slot whose ROM
   is a ProDOS block device. It is found by a register written and read back.

A machine with two cards uses the first one found.

## NET.CFG: the addresses, at a fixed place in the file

The Uthernet II needs its addresses. The CoGS card needs only the server's address and port; it gets its own address
by DHCP. Both come from 25 bytes at **`$3EDF-$3EF7`** in the file, file offset `$04DF`:

| Byte | What |
|---|---|
| 0 | 1 once a NET SETUP has written them |
| 1-4 | the gateway |
| 5-8 | the subnet mask |
| 9-14 | the card's MAC (the Uthernet II's) |
| 15-18 | the Apple's own IP |
| 19-22 | the server's IP |
| 23-24 | the server's port, high byte first (6502 = `$19 $66`) |

To change them on the disk: OPEN the file, SET_MARK to `$04DF`, WRITE the 25 bytes. The file keeps its blocks. To
build them in, edit `net_conf.inc`.

## The server

The server's lines are in `../PROTOCOL.md`. Each LINE opens a fresh exchange: the CoGS card closes and reconnects its
socket every line, and the Uthernet II opens its socket at the first.
