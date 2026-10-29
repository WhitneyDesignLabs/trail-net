#!/usr/bin/env python3
"""server v0 — the Tier 1 game server (E5 staging; Cowork, 2026-10-18). One small plaintext protocol, three transports.

Protocol (ASCII, one command per line, CR or LF terminated; replies end with CR LF; every reply starts with OK, ERR or a
record letter; the Apple II never sees more than 76 characters on a line):
  HI <game> <ver>                     -> OK <server> <utc-iso> <motd>
  REG <call> <n0> <n1> <n2> <n3> <n4> <days> <route> <trade> <score> <fp>   -> OK <rank> <parties>
                                         (n0 the player's own name, n1-n4 the companions; fp: the save fingerprint,
                                         CRC-16 hex; one record per call+fp; R1: the rank is on the score, higher
                                         first - parcels x 10 + cash / 10 + (30 - days) - scrutiny x 5, the game's
                                         sum; trade 1-6, 6 the Peddler)
  WALL [n]                            -> N <count>   then  L <call> <n0> <n1> <n2> <n3> <n4> <days> <route> <trade>  ×n
                                         then  END    (R1: the trade last: the game chalks a Peddler's row with a dash)
  COUNT                               -> OK <parties> <river> <road>
  NOTE <room> <text...>               -> OK                      (Tier 1 ghost notes, HOME.BASE-style)
  NOTES <room> [n]                    -> N <count> / L <text> ×n / END
  LINK <n>                            -> OK <line>  then  U <url>   (links.txt nodes; two lines, each ≤ 76: the game
                                         prints the OK line and shows the U line on a page; U - when no url)
  VISIT <n>                           -> OK <visits>             (the wall of jars: anonymous counts per node)
  TIME                                -> OK <utc-iso>
  RND                                 -> OK <0..65535>           (true random for the deck, when a card asks the server)
  BYE                                 -> OK
Transports: TCP (asyncio, default port 6502) for Uthernet II / CoGS raw socket / AppleWin; serial (--serial COM3 9600)
for the SSC bridge; --stdio for tests and pipes. Storage: sqlite (trail.db). No secrets here; the LLM agent (Tier 3) is a
separate client of this server, later.
R1 (the release): the wall is public text players type, so - a word filter (badwords.txt beside this file, --badwords):
a name or a note's word that hits is written as ----, never refused (the Apple always gets its OK); a per-address limit
(REG 10 an hour, NOTE 20 an hour: past it the answer is still OK and the line is dropped); a struck party (trail_admin.py
strike <id>) is off the wall and out of the ranks. The keeper's tool is trail_admin.py; server/install/ puts it on a Pi.
"""
import argparse, asyncio, collections, datetime, os, random, re, sqlite3, sys, time

MAXLINE = 76
DB_PATH = os.environ.get("TRAIL_DB", "trail.db")

SCHEMA = """
CREATE TABLE IF NOT EXISTS parties (id INTEGER PRIMARY KEY, game TEXT, call TEXT, n0 TEXT, n1 TEXT, n2 TEXT, n3 TEXT, n4 TEXT,
  days INTEGER, route TEXT, trade TEXT, score INTEGER, fp TEXT, ts TEXT, struck INTEGER DEFAULT 0, UNIQUE(call, fp));
CREATE TABLE IF NOT EXISTS notes (id INTEGER PRIMARY KEY, game TEXT, room INTEGER, text TEXT, ts TEXT);
CREATE TABLE IF NOT EXISTS visits (game TEXT, node INTEGER, count INTEGER, PRIMARY KEY (game, node));
CREATE TABLE IF NOT EXISTS links (game TEXT, node INTEGER, url TEXT, line TEXT, PRIMARY KEY (game, node));
"""

def now(): return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
def clean(s, n=MAXLINE): return "".join(ch for ch in s if 32 <= ord(ch) < 127)[:n]

BADWORDS_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "badwords.txt")
LEET = str.maketrans("013457@$!|", "OIEASTASII")

class Filter:
    """R1: badwords.txt - a word a line ('#' comments); a word ending in * matches any word it starts. A token is matched
    in capitals with the usual digit-for-letter swaps undone (0 O, 1 I, 3 E, 4 A, 5 S, 7 T, @ A, $ S) and other marks
    dropped; a hit becomes ----. Never a refusal: the line is kept, the word is not."""
    def __init__(self, path=BADWORDS_PATH):
        self.exact, self.prefix = set(), []
        if path and os.path.exists(path):
            for ln in open(path, encoding="utf-8"):
                w = ln.split("#", 1)[0].strip().upper()
                if w.endswith("*"): self.prefix.append(w[:-1])
                elif w: self.exact.add(w)
    def bad(self, token):
        t = re.sub(r"[^A-Z]", "", token.upper().translate(LEET))
        return bool(t) and (t in self.exact or any(t.startswith(p) for p in self.prefix))
    def scrub(self, text):
        return " ".join("----" if self.bad(w) else w for w in text.split())

class Limits:
    """R1: a per-address count of REG and NOTE lines in the last hour (REG 10, NOTE 20); over it: OK, and dropped."""
    CAPS = {"REG": 10, "NOTE": 20}
    def __init__(self, clock=time.time):
        self.clock, self.seen = clock, collections.defaultdict(collections.deque)
    def allow(self, peer, cmd):
        q, t = self.seen[(peer, cmd)], self.clock()
        while q and t - q[0] >= 3600: q.popleft()
        if len(q) >= self.CAPS[cmd]: return False
        q.append(t); return True

class Store:
    def __init__(self, path=DB_PATH):
        self.c = sqlite3.connect(path); self.c.executescript(SCHEMA)
        if "struck" not in [r[1] for r in self.c.execute("PRAGMA table_info(parties)")]:     # R1: a v0 database
            self.c.execute("ALTER TABLE parties ADD COLUMN struck INTEGER DEFAULT 0"); self.c.commit()
    def load_links(self, game, path):
        """links.txt: LINK <n> <object> "<line>" <source...>  (the URL column is server-side: links.urls beside it)"""
        urls = {}
        up = os.path.splitext(path)[0] + ".urls"
        if os.path.exists(up):
            for ln in open(up):
                if ln.strip() and not ln.startswith("#"):
                    n, url = ln.split(None, 1); urls[int(n)] = url.strip()
        for ln in open(path):
            if not ln.startswith("LINK"): continue
            parts = ln.split('"'); head = parts[0].split(); n = int(head[1]); line = parts[1] if len(parts) > 1 else ""
            self.c.execute("INSERT OR REPLACE INTO links VALUES (?,?,?,?)", (game, n, urls.get(n, ""), line))
        self.c.commit()

class Session:
    def __init__(self, store, game="INDEP", peer="-", limits=None, words=None):
        self.s = store; self.game = game; self.rnd = random.SystemRandom()
        self.peer = peer; self.limits = limits or Limits(); self.words = words or Filter()
    def handle(self, line):
        """one command line -> list of reply lines (without terminators)"""
        line = clean(line.strip(), 200)
        if not line: return []
        cmd, *args = line.split()
        cmd = cmd.upper()
        try:
            fn = getattr(self, "do_" + cmd, None)
            if not fn: return ["ERR UNKNOWN"]
            return fn(args)
        except Exception as e:  # never let the Apple hang on a traceback
            return ["ERR " + clean(type(e).__name__, 20)]
    def do_HI(self, a):
        if a: self.game = clean(a[0], 8).upper()
        return [f"OK TRAILSRV0 {now()} LIGHTS ARE ON"]
    def do_TIME(self, a): return [f"OK {now()}"]
    def do_RND(self, a): return [f"OK {self.rnd.randrange(65536)}"]
    def do_BYE(self, a): return ["OK"]
    def do_REG(self, a):
        if len(a) < 11: return ["ERR ARGS"]
        call, n0, n1, n2, n3, n4, days, route, trade, score, fp = (clean(x, 10).upper() for x in a[:11])
        if not self.limits.allow(self.peer, "REG"):                         # R1: past the hour's ten: OK, and dropped
            return ["OK 0 0"]
        call, n0, n1, n2, n3, n4 = (self.words.scrub(x) for x in (call, n0, n1, n2, n3, n4))
        self.s.c.execute("INSERT OR REPLACE INTO parties (game,call,n0,n1,n2,n3,n4,days,route,trade,score,fp,ts) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)",
                         (self.game, call, n0, n1, n2, n3, n4, int(days), route, trade, int(score), fp, now()))
        self.s.c.commit()
        rank = self.s.c.execute("SELECT COUNT(*)+1 FROM parties WHERE game=? AND score>? AND struck=0", (self.game, int(score))).fetchone()[0]   # R1: the score, higher first
        total = self.s.c.execute("SELECT COUNT(*) FROM parties WHERE game=?", (self.game,)).fetchone()[0]
        return [f"OK {rank} {total}"]
    def do_WALL(self, a):
        n = min(int(a[0]) if a else 10, 40)
        rows = self.s.c.execute("SELECT call,n0,n1,n2,n3,n4,days,route,trade FROM parties WHERE game=? AND struck=0 ORDER BY id DESC LIMIT ?", (self.game, n)).fetchall()
        return [f"N {len(rows)}"] + [clean("L " + " ".join(str(x) for x in r)) for r in rows] + ["END"]
    def do_COUNT(self, a):
        q = lambda w="": self.s.c.execute(f"SELECT COUNT(*) FROM parties WHERE game=? {w}", (self.game,)).fetchone()[0]
        river = self.s.c.execute("SELECT COUNT(*) FROM parties WHERE game=? AND route='RIVER'", (self.game,)).fetchone()[0]
        road = self.s.c.execute("SELECT COUNT(*) FROM parties WHERE game=? AND route='ROAD'", (self.game,)).fetchone()[0]
        return [f"OK {q()} {river} {road}"]
    def do_NOTE(self, a):
        if len(a) < 2: return ["ERR ARGS"]
        if not self.limits.allow(self.peer, "NOTE"):                        # R1: past the hour's twenty: OK, and dropped
            return ["OK"]
        self.s.c.execute("INSERT INTO notes (game,room,text,ts) VALUES (?,?,?,?)", (self.game, int(a[0]), self.words.scrub(clean(" ".join(a[1:]), 72)), now()))
        self.s.c.commit(); return ["OK"]
    def do_NOTES(self, a):
        if not a: return ["ERR ARGS"]
        n = min(int(a[1]) if len(a) > 1 else 5, 20)
        rows = self.s.c.execute("SELECT text FROM notes WHERE game=? AND room=? ORDER BY id DESC LIMIT ?", (self.game, int(a[0]), n)).fetchall()
        return [f"N {len(rows)}"] + [clean("L " + r[0]) for r in rows] + ["END"]
    def do_LINK(self, a):
        if not a: return ["ERR ARGS"]
        r = self.s.c.execute("SELECT url,line FROM links WHERE game=? AND node=?", (self.game, int(a[0]))).fetchone()
        if not r: return ["ERR NONODE"]
        return [clean("OK " + r[1]), clean("U " + (r[0] or "-"))]
    def do_VISIT(self, a):
        if not a: return ["ERR ARGS"]
        self.s.c.execute("INSERT INTO visits VALUES (?,?,1) ON CONFLICT(game,node) DO UPDATE SET count=count+1", (self.game, int(a[0])))
        self.s.c.commit()
        return [f"OK {self.s.c.execute('SELECT count FROM visits WHERE game=? AND node=?', (self.game, int(a[0]))).fetchone()[0]}"]

async def read_line(reader, limit=200):
    """a line ended by CR, LF or CR LF (the Apple sends CR); b'' at EOF"""
    buf = bytearray()
    while True:
        b = await reader.read(1)
        if not b: return bytes(buf) if buf else b""
        if b in (b"\r", b"\n"):
            if buf or b == b"\n": return bytes(buf) + b"\n"
            continue                      # a stray LF after a CR
        buf += b
        if len(buf) > limit: return bytes(buf) + b"\n"

IDLE = 600       # R5: a connection silent this long is closed (a W5100 reset or a power-off never says goodbye)

def log(*a):
    """R5: one line a connection event and a command (its word, the answer's first word, the time taken) - never a note's
    text or a name, never an address: enough for a keeper to see what arrived and when"""
    if LOG: print(datetime.datetime.now(datetime.timezone.utc).strftime("%H:%M:%S"), *a, flush=True)
LOG = True

async def tcp_main(store, host, port, limits=None, words=None, idle=None):
    limits, words = limits or Limits(), words or Filter()
    idle = idle or IDLE
    nconn = [0]
    async def client(reader, writer):
        peer = (writer.get_extra_info("peername") or ("-",))[0]
        sess = Session(store, peer=peer, limits=limits, words=words)
        nconn[0] += 1; cid = nconn[0]; why = "eof"
        log(f"#{cid} open")
        try:
            while True:
                try:
                    raw = await asyncio.wait_for(read_line(reader), idle)
                except asyncio.TimeoutError:
                    why = "idle"; break
                if not raw: break
                line = raw.decode("ascii", "replace")
                t = time.time(); outs = sess.handle(line)
                for out in outs:
                    writer.write((out + "\r\n").encode("ascii", "replace"))
                await writer.drain()
                if line.strip():
                    log(f"#{cid} {clean(line.split()[0], 8).upper()} -> {outs[0].split()[0] if outs else '-'} "
                        f"({(time.time() - t) * 1000:.0f} ms)")
                if line.strip().upper().startswith("BYE"): break
        except (asyncio.IncompleteReadError, ConnectionResetError, BrokenPipeError):
            why = "reset"
        finally:
            log(f"#{cid} closed ({why})")
            writer.close()
    srv = await asyncio.start_server(client, host, port)
    print(f"trail server v0 on {host}:{port}  db={DB_PATH}", flush=True)
    async with srv: await srv.serve_forever()

def serial_main(store, port, baud, words=None):
    import serial  # pyserial
    sess = Session(store, peer=port, words=words); buf = b""
    with serial.Serial(port, baud, timeout=0.2) as sp:
        print(f"trail server v0 on {port} @ {baud}", flush=True)
        while True:
            b = sp.read(64)
            if not b: continue
            buf += b
            while b"\r" in buf or b"\n" in buf:
                i = min(x for x in (buf.find(b"\r"), buf.find(b"\n")) if x >= 0)
                line, buf = buf[:i].decode("ascii", "replace"), buf[i + 1:]
                for out in sess.handle(line): sp.write((out + "\r\n").encode("ascii", "replace"))

def stdio_main(store, words=None):
    sess = Session(store, peer="stdio", words=words)
    for line in sys.stdin:
        for out in sess.handle(line): print(out, flush=True)

if __name__ == "__main__":
    ap = argparse.ArgumentParser(); ap.add_argument("--host", default="0.0.0.0"); ap.add_argument("--port", type=int, default=6502)
    ap.add_argument("--serial"); ap.add_argument("--baud", type=int, default=9600); ap.add_argument("--stdio", action="store_true")
    ap.add_argument("--links", help="load a title's links.txt (and links.urls beside it)"); ap.add_argument("--game", default="INDEP")
    ap.add_argument("--badwords", default=BADWORDS_PATH, help="the word filter's list (R1: badwords.txt beside this file)")
    ap.add_argument("--idle", type=int, default=IDLE, help="R5: seconds a TCP connection may stay silent (default 600)")
    ap.add_argument("--quiet", action="store_true", help="R5: no connection log")
    a = ap.parse_args(); store = Store(); words = Filter(a.badwords); LOG = not a.quiet
    if a.links: store.load_links(a.game, a.links)
    if a.stdio: stdio_main(store, words)
    elif a.serial: serial_main(store, a.serial, a.baud, words)
    else: asyncio.run(tcp_main(store, a.host, a.port, words=words, idle=a.idle))
