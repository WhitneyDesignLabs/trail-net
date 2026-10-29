#!/usr/bin/env python3
"""trail_admin.py — the game server's keeper's tool (R1): what the wall shows and what the logs say, by hand.

    python3 trail_admin.py [--db /var/lib/trail/trail.db] list [n]        the newest n parties (default 40): id, call, names,
                                                                           days, route, trade, score, struck
    python3 trail_admin.py strike <id>                                     hide a party from WALL (and from the ranks)
    python3 trail_admin.py unstrike <id>                                   show it again
    python3 trail_admin.py notes <room> [n]                                a room's notes, newest first, with their ids
    python3 trail_admin.py unnote <id>                                     delete a note

The database is the server's (TRAIL_DB, else trail.db here; the Pi's install: /var/lib/trail/trail.db). It is safe to run
while the server runs: sqlite takes the writes one at a time.
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import trail_server as ts  # noqa: E402  (the schema and its migrations)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--db", default=os.environ.get("TRAIL_DB", "trail.db"))
    ap.add_argument("--game", default="INDEP")
    ap.add_argument("cmd", choices=["list", "strike", "unstrike", "notes", "unnote"])
    ap.add_argument("arg", nargs="*")
    a = ap.parse_args(argv)
    st = ts.Store(a.db)
    c = st.c
    if a.cmd == "list":
        n = int(a.arg[0]) if a.arg else 40
        rows = c.execute("SELECT id, call, n0, n1, n2, n3, n4, days, route, trade, score, struck, ts FROM parties "
                         "WHERE game=? ORDER BY id DESC LIMIT ?", (a.game, n)).fetchall()
        for r in rows:
            print(f"{r[0]:5d}  {r[1]:10s} {' '.join(x for x in r[2:7] if x):45s} {r[7]:3d} {r[8]:5s} {r[9]:>2s} {r[10]:5d}"
                  f"{'  STRUCK' if r[11] else ''}  {r[12]}")
        print(f"{len(rows)} parties shown")
    elif a.cmd in ("strike", "unstrike"):
        if not a.arg:
            ap.error(f"{a.cmd} <id>")
        n = c.execute("UPDATE parties SET struck=? WHERE id=?", (1 if a.cmd == "strike" else 0, int(a.arg[0]))).rowcount
        c.commit()
        print(f"{a.cmd}: {n} party" + ("" if n == 1 else " (no such id)"))
        return 0 if n else 1
    elif a.cmd == "notes":
        if not a.arg:
            ap.error("notes <room> [n]")
        rows = c.execute("SELECT id, text, ts FROM notes WHERE game=? AND room=? ORDER BY id DESC LIMIT ?",
                         (a.game, int(a.arg[0]), int(a.arg[1]) if len(a.arg) > 1 else 40)).fetchall()
        for r in rows:
            print(f"{r[0]:5d}  {r[1]}  ({r[2]})")
        print(f"{len(rows)} notes in room {a.arg[0]}")
    elif a.cmd == "unnote":
        if not a.arg:
            ap.error("unnote <id>")
        n = c.execute("DELETE FROM notes WHERE id=?", (int(a.arg[0]),)).rowcount
        c.commit()
        print(f"unnote: {n} note" + ("" if n == 1 else " (no such id)"))
        return 0 if n else 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
