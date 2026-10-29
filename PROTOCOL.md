# The trail protocol

One small plaintext protocol, the same over every transport: a TCP socket (port 6502), a serial line (through
`ssc_relay.py`), a WebSocket (through `ws_relay.py`). It was made for 8-bit computers, so:

- **Lines:** ASCII, one command per line, ended by CR or LF.
- **Replies:** each ends with CR LF. Read a reply to its LF: the CoGS card's notes say why.
- **Reply format:** every reply starts with `OK`, `ERR` or a record letter (`N`, `L`, `U`, `END`).
- **Length:** no reply line is longer than 76 characters, so it fits an 80-column screen with room to spare.
- **Numbers** are decimal and space-separated, so a client can pick them out without a parser.

## Commands

| Command | Reply |
|---|---|
| `HI <game> <ver>` | `OK <server> <utc-iso> <motd>`: says which game this session is for (the default is `INDEP`) |
| `TIME` | `OK <utc-iso>` |
| `RND` | `OK <0..65535>`: a true random number |
| `COUNT` | `OK <parties> <river> <road>`: how many have signed the wall, by route |
| `REG <call> <n0> <n1> <n2> <n3> <n4> <days> <route> <trade> <score> <fp>` | `OK <rank> <parties>`: a party signs the wall (see below) |
| `WALL [n]` | `N <count>`, then `L <call> <n0> ... <n4> <days> <route> <trade>` n times, then `END`: the wall, newest first |
| `NOTE <room> <text...>` | `OK`: a note left in a room for the next player |
| `NOTES <room> [n]` | `N <count>`, then `L <text>` n times, then `END` |
| `LINK <n>` | `OK <line>`, then `U <url>` (`U -` when there is none): a node of the game's links file (`links.txt`, `links.urls`) |
| `VISIT <n>` | `OK <visits>`: an anonymous count per node |
| `BYE` | `OK` |

**REG's fields:**
- `n0` is the player's own name and `n1`-`n4` the companions'.
- `fp` is the save's fingerprint, a CRC-16 in hex; there is one record per call and fingerprint.
- The rank is by score, higher first.
- The game computes the score itself; the server only orders by it.

## For players' text

The wall and the notes are text that players type, so the server:
- **Filters words.** A name or a note's word that hits the list is written as `----`. The line is never refused: the
  Apple always gets its `OK`. The list is a file beside the server, `badwords.txt`: one word a line, `#` comments, and
  a trailing `*` matches any word that starts with it. This repository does not publish one.
- **Limits each address.** An address gets REG 10 times an hour and NOTE 20 times; past that the answer is still `OK`
  and the line is dropped.
- **Lets the keeper strike a party** (`trail_admin.py strike <id>`), which takes it off the wall and out of the ranks.

## Storage

One sqlite file (`trail.db`). The schema and its migrations are in `trail_server.py`.
