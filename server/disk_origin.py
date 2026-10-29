#!/usr/bin/env python3
"""disk_origin.py — a writable disk image for the CoGS card's network disk (E5b, after Gate E).

The card reads a mounted image with ranged GETs and writes a block back with a ranged PUT (Technical Reference 4.9.3,
6.6, Appendix B: "PUT on a disk image path with Content-Range: bytes a-b/*"). Caddy alone serves the read-only images
in /srv/disks (a PUT there gets 405, which latches the card's mount read-only); this serves the ones that must take a
SAVE: every file in --dir, by name in any case (an Apple II types capitals), on 127.0.0.1, behind Caddy.

    python3 disk_origin.py --dir /srv/disks-rw --listen 127.0.0.1:6505

GET / HEAD: the file, a Range honoured with 206. PUT: Content-Range bytes a-b/* (or /<size>) writes b-a+1 bytes at a in
place, 200; a range outside the file 416; no Content-Range 400. Every image response says X-CoGS-Writable: 1, and an
ETag of the file's inode and size: the card keys its flash cache by it, so a new image (make-dist writes it beside the
old and renames it over: a new inode) is fetched again, while the card's own writes (in place) keep the tag - the card
drops a block it writes from its caches itself. No Last-Modified (a write would change it). No X-CoGS-Poll.
One line a request to stderr (the journal): method, name, range, status.
"""
import argparse
import os
import re
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LOCK = threading.Lock()
RANGE = re.compile(r"bytes=(\d*)-(\d*)$")
CRANGE = re.compile(r"bytes (\d+)-(\d+)/(\d+|\*)$")


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "disk_origin"
    sys_version = ""

    def path_of(self):
        """The file in --dir that the request names (its last path part, any case), or None."""
        name = self.path.split("?", 1)[0].rstrip("/").rsplit("/", 1)[-1].upper()
        for f in os.listdir(self.server.dir):
            if f.upper() == name and not f.startswith("."):
                return os.path.join(self.server.dir, f)
        return None

    def done(self, code, body=b"", headers=()):
        self.send_response(code)
        for k, v in headers:
            self.send_header(k, v)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body and self.command != "HEAD":
            self.wfile.write(body)

    def image_headers(self, st):
        return [("Accept-Ranges", "bytes"), ("ETag", f'"{st.st_ino:x}-{st.st_size:x}"'), ("X-CoGS-Writable", "1"),
                ("Content-Type", "application/octet-stream"), ("Cache-Control", "no-store")]

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        p = self.path_of()
        if p is None:
            return self.done(404)
        with LOCK:
            with open(p, "rb") as f:
                st = os.fstat(f.fileno())
                size = st.st_size
                rng = self.headers.get("Range")
                if not rng:
                    data = f.read() if self.command == "GET" else b""
                    self.send_response(200)
                    for k, v in self.image_headers(st):
                        self.send_header(k, v)
                    self.send_header("Content-Length", str(size))
                    self.end_headers()
                    if self.command == "GET":
                        self.wfile.write(data)
                    return
                m = RANGE.match(rng.strip())
                if not m or (m.group(1) == "" and m.group(2) == ""):
                    return self.done(416, headers=[("Content-Range", f"bytes */{size}")])
                if m.group(1) == "":                       # bytes=-n: the last n
                    a, b = max(0, size - int(m.group(2))), size - 1
                else:
                    a = int(m.group(1))
                    b = min(int(m.group(2)), size - 1) if m.group(2) else size - 1
                if a >= size or b < a:
                    return self.done(416, headers=[("Content-Range", f"bytes */{size}")])
                f.seek(a)
                data = f.read(b - a + 1)
        self.send_response(206)
        for k, v in self.image_headers(st):
            self.send_header(k, v)
        self.send_header("Content-Range", f"bytes {a}-{b}/{size}")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        if self.command == "GET":
            self.wfile.write(data)

    def do_PUT(self):
        n = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(n) if n else b""
        p = self.path_of()
        if p is None:
            return self.done(404)
        m = CRANGE.match((self.headers.get("Content-Range") or "").strip())
        if not m:
            return self.done(400, b"PUT needs Content-Range: bytes a-b/*\n")
        a, b = int(m.group(1)), int(m.group(2))
        with LOCK:
            size = os.path.getsize(p)
            if b < a or b >= size or len(body) != b - a + 1:
                return self.done(416, headers=[("Content-Range", f"bytes */{size}")])
            with open(p, "r+b") as f:
                f.seek(a)
                f.write(body)
                f.flush()
                os.fsync(f.fileno())
                st = os.fstat(f.fileno())
        self.done(200, headers=[("ETag", f'"{st.st_ino:x}-{st.st_size:x}"'), ("X-CoGS-Writable", "1")])

    def log_request(self, code="-", size="-"):
        rng = self.headers.get("Range") or self.headers.get("Content-Range") or ""
        sys.stderr.write(f"{self.command} {self.path} {rng} -> {code}\n")
        sys.stderr.flush()

    def log_message(self, fmt, *args):
        sys.stderr.write((fmt % args) + "\n")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--dir", default="/srv/disks-rw")
    ap.add_argument("--listen", default="127.0.0.1:6505")
    a = ap.parse_args(argv)
    host, port = a.listen.rsplit(":", 1)
    srv = ThreadingHTTPServer((host, int(port)), Handler)
    srv.dir = a.dir
    sys.stderr.write(f"disk_origin on {a.listen}, {a.dir}\n")
    srv.serve_forever()


if __name__ == "__main__":
    main()
