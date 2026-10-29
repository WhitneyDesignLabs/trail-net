# NETCHECK.dsk: a sample client

A bootable ProDOS disk (128K Apple IIe or later) that tests a network card against a trail server:

| Key | Does |
|---|---|
| **P** | probes again: which card, which slot, and whether the server answers (`NET: COGS CARD, SLOT 7 UP.`) |
| **H** | says hello (`HI`) and shows the reply |
| **C** | asks how many parties have signed the wall (`COUNT`) |
| **S** | sets an Uthernet II's addresses and saves them on a disk (NET.CFG) |
| **ESC** | reboots |

It runs the NET file in `../drivers/` exactly as the games do. Its banner names the build it came from.

**Binary only.** NETCHECK is built from INDEPENDENCE's engine with a menu put in (`engine/tests/NETCHECK/` in the game's
tree). Its source does not separate from that tree, so it is not here. To write your own client, start from
`../drivers/NET-FILE.md`.
