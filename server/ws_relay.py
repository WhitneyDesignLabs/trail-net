#!/usr/bin/env python3
"""ws_relay.py — R4 Gate D: a browser emulator's Super Serial Card to the game server. A browser cannot open a TCP socket;
it can open a WebSocket. Each WebSocket session gets its own TCP connection to trail_server.py, and the bytes go both ways
unchanged (the Apple sends a line ending in CR, the server answers in lines ending CR LF: ssc_relay.py's contract, so the
game cannot tell a browser from a cable). A dropped server ends the session; the page reconnects.

    python3 ws_relay.py [--listen 0.0.0.0:6503] [--server 127.0.0.1:6502] [--origin https://example.org ...]

Needs websockets (pip install websockets; install.sh puts it in the server's venv). --origin limits which pages may
connect (default: any). Runs beside trail_server.py: server/install/trail-ws.service.
"""
import argparse
import asyncio
import sys

try:
    import websockets
except ImportError:
    sys.exit("ws_relay: needs websockets - pip install websockets")


async def session(ws, server, n):
    host, _, port = server.rpartition(":")
    try:
        r, w = await asyncio.open_connection(host, int(port))
    except OSError as e:
        print(f"[{n}] no server at {server}: {e}", flush=True)
        await ws.close(1011, "no server")
        return
    print(f"[{n}] open", flush=True)

    async def up():                                     # the browser's bytes to the server
        async for msg in ws:
            w.write(msg if isinstance(msg, bytes) else msg.encode("latin-1"))
            await w.drain()

    async def down():                                   # the server's bytes to the browser, as binary frames
        while data := await r.read(1024):
            await ws.send(data)

    tasks = [asyncio.ensure_future(up()), asyncio.ensure_future(down())]
    await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
    for t in tasks:
        t.cancel()
    w.close()
    await ws.close()
    print(f"[{n}] closed", flush=True)


async def main(a):
    host, _, port = a.listen.rpartition(":")
    count = [0]

    async def handler(ws, *_path):                      # (websockets < 13 passes the path too)
        count[0] += 1
        await session(ws, a.server, count[0])

    kw = {"origins": a.origin} if a.origin else {}
    async with websockets.serve(handler, host, int(port), max_size=4096, **kw):
        print(f"ws_relay: ws://{a.listen} -> {a.server}", flush=True)
        await asyncio.Future()


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--listen", default="0.0.0.0:6503")
    ap.add_argument("--server", default="127.0.0.1:6502")
    ap.add_argument("--origin", nargs="*")
    try:
        asyncio.run(main(ap.parse_args()))
    except KeyboardInterrupt:
        pass
