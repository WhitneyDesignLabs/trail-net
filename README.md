# trail-net

How two new Apple II games, **INDEPENDENCE** and **HOME.BASE**, go online. This is a small line-protocol server, the
6502 drivers for three network cards, and the relays and disk server around them, published so that others can build
the same kind of online software for 8-bit machines.

The games themselves (their engine, parser, content and art tools) are not here. What is here is enough to put your own
6502 program on the same wire.

## What is in it

```
server/                  the game server and its helpers (Python 3)
  trail_server.py        the server: one plaintext protocol (PROTOCOL.md), TCP port 6502, sqlite storage
  trail_admin.py         the keeper's tool: list, notes, strike a party from the wall
  ws_relay.py            WebSocket <-> the server, for an emulator in a browser (Apple2TS with a WebSocket serial card)
  ssc_relay.py           a serial port <-> the server, for a Super Serial Card on a PC's cable
  disk_origin.py         a writable network disk for the CoGS card: ranged GET and ranged PUT on a folder of .po images
  count_http.py          the wall's count as JSON over HTTP (GET /count), for web pages such as a game lobby
  test_trail_server.py   the server's tests
  install/               install.sh (a Raspberry Pi or an Ubuntu VM: systemd units, a venv, the firewall, Caddy for
                         TLS, the disks, /count and a /play/ folder), the units, Caddyfile.web, deploy-web.sh,
                         backup.sh, uninstall.sh
drivers/                 the NET file: the 6502 side (Ophis assembler)
  net.s                  the common part, the Super Serial Card, the Uthernet II (W5100), the CoGS card's first half
  net_cogs.s             the CoGS card's second half
  net_top.s, net_env.inc, net_conf.inc   the file as the games build it; build.sh -> NET.bin (1,532 B)
  NET-FILE.md            how a program calls it: where it loads, the four operations, the reply block, the card order,
                         the addresses' layout
  COGS-NOTES.md          what we learned on the CoGS card
netcheck/NETCHECK.dsk    a bootable sample client (P probe, H hello, C count): binary only
PROTOCOL.md              the server's commands and replies
```

## Run a server

On a Raspberry Pi (Raspberry Pi OS) or a small Ubuntu VM (a free-tier cloud machine is plenty), as root:

    sudo sh server/install/install.sh

That puts the server in `/opt/trail` with its database in `/var/lib/trail/trail.db`, and starts `trail-server` (TCP
6502) and `trail-ws` (the WebSocket relay). The keeper's tool:

    sudo -u trail /opt/trail/venv/bin/python /opt/trail/trail_admin.py --db /var/lib/trail/trail.db list

For a browser on an https page, and for the CoGS card's network disks, give it a host name:

    sudo sh server/install/install.sh --web <a-b-c-d>.sslip.io

Caddy then answers `wss://<host>:6503` with a Let's Encrypt certificate, and serves `/disks/` and `/DISKS/`: read-only
images from `/srv/disks`, and writable ones from `/srv/disks-rw` through `disk_origin.py`.

`/count` on every site answers the protocol's COUNT as JSON, `{"parties": n, "river": n, "road": n}` (`?game=<id>` for
another game), with a 15-second cache and CORS open, so any web page can show a live count. INDEPENDENCE's is
`https://158-101-9-238.sslip.io/count`. No domain is needed:
`<a-b-c-d>.sslip.io` resolves to a.b.c.d. A cloud firewall must admit TCP 80 (the certificate), 6502 and 6503.

**The word filter.** The wall and the notes are text players type, so the server can blank listed words (PROTOCOL.md).
This repository publishes no list. Put your own `server/badwords.txt` beside the server: one word a line, `#` comments,
`word*` for every word that starts so. Without one the filter is off.

## Put a 6502 program on the wire

Build the drivers with Ophis:

    OPHIS=<ophis> bash drivers/build.sh

Load `NET.bin` into auxiliary memory at `$3A00`, and call it as `drivers/NET-FILE.md` says: PROBE finds the card, LINE
sends a line and reads the reply. Three cards are supported:

| Card | How it reaches the server | What the Apple sets |
|---|---|---|
| **CoGS** (Rob Perissi, a2cogs.com) | Wi-Fi or Ethernet, the card does DHCP and TCP | only the server and its port |
| **Uthernet II** | Ethernet, the W5100 in indirect mode, TCP on socket 0 | the Apple's IP, mask, gateway, the server and port |
| **Super Serial Card** (and the A2Pico's SSC firmware) | 9600 8N1 to a PC running `ssc_relay.py --port COM3 --server <host>:6502` | nothing |

In an emulator, AppleWin's Uthernet II and SSC both work. Apple2TS works in a browser with the WebSocket serial card
(`ws_relay.py`).

## The other way online with a CoGS card

trail-net is the raw-TCP path: your program talks a line protocol to a server of your own. The CoGS card also offers a
way with no server of your own: Rob Perissi's **cogs-gameroom** (github.com/rperissi/cogs-gameroom), HTTP and JSON to
the card's Game Room lobby, where players find each other. Pick by what your game needs: a shared world you keep
(trail-net), or matchmaking and messages through the lobby (cogs-gameroom).

## Boot from a URL, and release candidates without SD cards

The CoGS card mounts a ProDOS-order image from an HTTP URL and boots it (`drivers/COGS-NOTES.md`). We used it to test
every release candidate the same day it was built:
- **Every build uploads `LATEST.PO`** to `/srv/disks-rw`, writable, renamed into place (a new ETag, so the card fetches
  it again).
- **The tester's card mounts `http://<host>/DISKS/LATEST.PO` once.** After that, each reboot plays the newest build,
  and SAVE works.
- **Releases sit beside it** under their own names (`INDEP1-1.0.PO`), read-only. A write there gets 405, so the card
  shows the disk as write-protected.

Type `http://` in lower case on the card. Make the path answer in capitals as well, because that is how the Apple types
it.

## Credits

Made by Scott Whitney / Whitney Design Labs, written and programmed with Claude (Anthropic) working to his design, for
INDEPENDENCE and HOME.BASE (github.com/WhitneyDesignLabs).
- **The CoGS card** and its Technical Reference: Rob Perissi.
- **The browser emulator:** Apple2TS by Chris Torrence and its contributors.
- **The Uthernet II:** a WIZnet W5100.
- **The assembler:** Ophis, by Michael Martin.

MIT licence (LICENSE).
