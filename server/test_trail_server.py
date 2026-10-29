"""pytest for server v0: the protocol through Session (no sockets), then once through a real TCP round trip."""
import asyncio, os, tempfile
import trail_server as ts

def fresh():
    d = tempfile.mkdtemp(); return ts.Store(os.path.join(d, "t.db")), d

def test_protocol_round():
    store, d = fresh(); s = ts.Session(store)
    assert s.handle("HI INDEP 1")[0].startswith("OK TRAILSRV0")
    assert s.handle("COUNT") == ["OK 0 0 0"]
    assert s.handle("REG VALLEY41 ALEX DALE MARA JUNE OTIS 9 RIVER 5 120 abcd") == ["OK 1 1"]
    assert s.handle("REG VALLEY42 PAT AL BO CY DI 7 ROAD 2 150 ffff") == ["OK 1 2"]       # R1: the higher score ranks first
    assert s.handle("REG VALLEY43 SCOTT AL BO CY DI 6 RIVER 6 90 eeee") == ["OK 3 3"]
    assert s.handle("COUNT") == ["OK 3 2 1"]
    wall = s.handle("WALL")
    assert wall[0] == "N 3" and wall[-1] == "END" and wall[1].startswith("L VALLEY43 SCOTT AL") and len(wall[1]) <= ts.MAXLINE
    assert wall[1].endswith(" 6") and wall[2].endswith(" 2")          # R1: the trade is the L line's last field
    # re-registering the same call+fp replaces, not duplicates
    s.handle("REG VALLEY41 ALEX DALE MARA JUNE OTIS 8 RIVER 5 130 abcd"); assert s.handle("COUNT") == ["OK 3 2 1"]
    assert s.handle("NOTE 6 two jars same mountain") == ["OK"]
    assert s.handle("NOTES 6") == ["N 1", "L two jars same mountain", "END"]
    assert s.handle("VISIT 1") == ["OK 1"] and s.handle("VISIT 1") == ["OK 2"]
    assert s.handle("LINK 1") == ["ERR NONODE"]
    assert s.handle("NOPE") == ["ERR UNKNOWN"] and s.handle("REG x") == ["ERR ARGS"]
    r = s.handle("RND"); assert r[0].startswith("OK ") and 0 <= int(r[0][3:]) < 65536
    assert s.handle("") == []

def test_links_file(tmp_path):
    (tmp_path / "links.txt").write_text('# x\nLINK 1 JARS      "WALT\'S JARS ARE REAL."   note\nLINK 2 TRIKE "THE TRIKE IS REAL."  note\n')
    (tmp_path / "links.urls").write_text("1 https://example.org/ash\n")
    store, d = fresh(); store.load_links("INDEP", str(tmp_path / "links.txt")); s = ts.Session(store)
    assert s.handle("LINK 1") == ["OK WALT'S JARS ARE REAL.", "U https://example.org/ash"]
    assert s.handle("LINK 2") == ["OK THE TRIKE IS REAL.", "U -"]
    assert all(len(x) <= ts.MAXLINE for x in s.handle("LINK 1"))

def test_tcp_round_trip():
    store, d = fresh()
    async def go():
        srv = await asyncio.start_server(lambda r, w: handler(r, w), "127.0.0.1", 0)
        port = srv.sockets[0].getsockname()[1]
        async def handler(reader, writer):
            sess = ts.Session(store)
            while True:
                raw = await ts.read_line(reader)
                if not raw: break
                for out in sess.handle(raw.decode()): writer.write((out + "\r\n").encode())
                await writer.drain()
            writer.close()
        async with srv:
            r, w = await asyncio.open_connection("127.0.0.1", port)
            w.write(b"HI INDEP 1\rCOUNT\r"); await w.drain()
            l1 = await r.readline(); l2 = await r.readline()
            w.close()
            return l1, l2
    l1, l2 = asyncio.run(go())
    assert l1.startswith(b"OK TRAILSRV0") and l1.endswith(b"\r\n") and l2 == b"OK 0 0 0\r\n"
