#!/usr/bin/env python3
"""count_http.py — R9-D7: the wall's count over HTTP, for web pages (the CoGS Game Room lobby lists a game with a live
count). GET /count -> {"parties": n, "river": n, "road": n}: the same three numbers the protocol's COUNT answers, from
the server's own code (trail_server.Session), so the two can never disagree. ?game=<id> picks another game (default
INDEP). Cache-Control max-age=15, CORS *. Read only: it answers COUNT and nothing else.

    python3 count_http.py --db /var/lib/trail/trail.db --listen 127.0.0.1:6506      (Caddy routes /count to it)
"""
import argparse
import json
import os
import re
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import trail_server as ts  # noqa: E402


class Handler(BaseHTTPRequestHandler):
    server_version = "trail-count"
    sys_version = ""

    def do_GET(self):
        u = urlparse(self.path)
        if u.path.rstrip("/") != "/count":
            return self.answer(404, {"error": "not found"})
        game = (parse_qs(u.query).get("game") or ["INDEP"])[0].upper()
        if not re.fullmatch(r"[A-Z0-9]{1,12}", game):
            return self.answer(400, {"error": "bad game"})
        store = ts.Store(self.server.db)                   # a connection a request (the server's threads are its own)
        try:
            m = re.fullmatch(r"OK (\d+) (\d+) (\d+)", ts.Session(store, game=game).handle("COUNT")[0])
        finally:
            store.c.close()
        if not m:
            return self.answer(500, {"error": "count"})
        self.answer(200, {"parties": int(m[1]), "river": int(m[2]), "road": int(m[3])})

    def answer(self, code, obj):
        body = (json.dumps(obj) + "\n").encode("ascii")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "max-age=15")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):                  # (no addresses in the log: the server keeps none either)
        pass


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--db", default="trail.db")
    ap.add_argument("--listen", default="127.0.0.1:6506")
    a = ap.parse_args(argv)
    host, port = a.listen.rsplit(":", 1)
    srv = ThreadingHTTPServer((host, int(port)), Handler)
    srv.db = a.db
    srv.serve_forever()


if __name__ == "__main__":
    main()
