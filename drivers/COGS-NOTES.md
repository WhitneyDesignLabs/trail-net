# The CoGS card: what we learned

The CoGS (Rev 3.2) is Rob Perissi's network coprocessor card for the Apple II: a2cogs.com. The card does Wi-Fi or
Ethernet, DHCP, DNS, TCP and TLS itself; the 6502 sees sixteen registers and a frame protocol. These notes come from
putting INDEPENDENCE online through it, October 2026, on an enhanced IIe. The card's own Technical Reference is the
authority. Where it and these notes differ, it wins.

## Setting up

- **Firmware 1.38.** It updates itself over the air. Since 1.38 a IIe boots slot 6 before the card, so keep the card in
  slot 7 and boot it with `PR#7` or from its menu.
- **Network.** Join Wi-Fi from the card's own menu, or plug in Ethernet. It takes its address by DHCP, so nothing is set
  on the Apple. The game's NET SETUP asks only for the server and its port.
- **Registers** at `$C080 + 16 x slot`: DATA +0, STATUS +1 (bit 7 data waiting, bit 6 ready to send, bit 4 link up,
  bit 3 error), the count waiting +2/+3, CONTROL +4, ID +5 (`$A2`), VERSION +6.
- **Frames** are `[op][length low][length high][payload]`. The driver uses socket 0: CLOSE, CONNECT to the server
  (given as text, `"158.101.9.238"`), SEND, then DATA frames read until the reply's line ends.

## The shared read queue: read every reply to its last byte

The card's slot ROM, its ProDOS and SmartPort block driver for the network disks, reads the **same card-to-host queue**
as a program's own frames.

Our first driver stopped reading a reply at its CR and left the LF of the server's CR LF in the queue. The next ProDOS
call to the card's units read that LF as the head of a frame and waited for bytes that never came. In INDEPENDENCE that
call was the engine's look for side B when the party left town, so the game froze with the picture up.

**Rule:** take every byte of every frame you start. The driver now drops CR and ends a line at LF, so the queue is
always left at a frame's head (`net_cogs.s`, `cg_get`).

## Booting a disk from a URL

The card mounts a ProDOS-order image (`.po`, 800K or 32M) from an HTTP or HTTPS URL as a block device, and boots it.
For a two-sided game this is a gift: one volume holds both sides, and nothing ever changes disks.
- **The server** must answer range requests with 206. `disk_origin.py` does, and so does Caddy's `file_server`.
- **Type the URL with `http://` in lower case.** The card did not recognise `HTTP://` and never asked. The Apple types
  the rest in capitals, so make the path match whatever case it arrives in. `Caddyfile.web` routes both cases.
- **Writes:** the card writes a block with a ranged **PUT** (`Content-Range: bytes a-b/*`).
  - An origin that answers **403, 405 or 501** latches the mount read-only, so ProDOS sees a write-protected disk:
    right for a shared release image.
  - An origin that answers 200 **must store the block**. One that answers 200 without storing makes SAVE look fine
    and loses the save.
  - For saves, use an origin that stores PUTs (`disk_origin.py`) or the card's own Image Manager share.
- **Caching:** the card keeps a flash cache keyed by the URL and the origin's ETag (or Last-Modified). Give a new image
  a new ETag; `disk_origin.py` uses the file's inode and size, and a rebuild is renamed into place.

**Release candidates from a URL** (the trick that made our last week). Every build writes a fresh image to the server
as `LATEST.PO`, writable. The tester's card mounts that URL once, and every reboot plays the newest build: no SD cards,
no floppies. Each release goes up beside it under its own name, read-only.

## What a save looks like on the wire

ProDOS saving a 1,040-byte file over an old one (block numbers of an 800K image):
- **Writes:** the file's index and data blocks (450, 452, 453), its directory (48, 45), then the volume's top
  directory, block 2, last.
- **Reads:** between the writes, 28-block windows (14,336-byte ranged GETs) as ProDOS reads what it is about to change.
- **Connections:** the card keeps two HTTP connections open, one for reads and one for writes. It reuses them across
  pauses of half a minute, and opens new ones after about 60 seconds idle.
