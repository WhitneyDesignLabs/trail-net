#!/usr/bin/env python3
"""ssc_relay.py — INDEPENDENCE's serial relay: an Apple II with a Super Serial Card (or the Pico SSC) and a PC on its cable
reach the game server over the internet. Lines go both ways, unchanged; each is printed; a dropped server is dialled again.

    python3 ssc_relay.py --port COM3 --server 203.0.113.7:6502          (Windows: the serial adapter's COM port)
    python3 ssc_relay.py --port /dev/ttyUSB0 --baud 9600 --server trail.example.org:6502

The Apple sends a line ending in CR and reads the answer's lines (CR LF); the relay forwards bytes as they come, so it
needs no knowledge of the protocol. Needs pyserial (pip install pyserial). Ctrl-C stops it.
"""
import argparse
import socket
import sys
import threading
import time

try:
    import serial
except ImportError:
    sys.exit("ssc_relay: needs pyserial - pip install pyserial")


def log(direction, data, buf):
    """print whole lines as they pass ('>' Apple to server, '<' server to Apple)"""
    buf[0] += data
    while True:
        cut = min((i for i in (buf[0].find(b"\r"), buf[0].find(b"\n")) if i >= 0), default=-1)
        if cut < 0:
            return
        line, buf[0] = buf[0][:cut], buf[0][cut + 1:]
        if line:
            print(f"{direction} {line.decode('ascii', 'replace')}", flush=True)


def relay(args):
    host, _, port = args.server.rpartition(":")
    try:
        sp = serial.serial_for_url(args.port, args.baud, timeout=0.1)
    except (serial.SerialException, ValueError) as e:      # R2a: a port that is wrong or in use says so, no traceback
        sys.exit(f"ssc_relay: cannot open {args.port} ({e}). Is it the serial adapter's port, and is nothing else using it?")
    print(f"ssc_relay: {args.port} @ {args.baud} <-> {host}:{port}", flush=True)
    up, down = [b""], [b""]
    while True:
        try:
            sock = socket.create_connection((host, int(port)), timeout=10)
        except OSError as e:
            print(f"ssc_relay: no server ({e}); again in {args.retry} s", flush=True)
            time.sleep(args.retry)
            continue
        sock.settimeout(None)
        print("ssc_relay: connected", flush=True)
        gone = threading.Event()

        def from_server():
            try:
                while not gone.is_set():
                    data = sock.recv(256)
                    if not data:
                        break
                    sp.write(data)
                    log("<", data, down)
            except OSError:
                pass
            gone.set()

        threading.Thread(target=from_server, daemon=True).start()
        try:
            while not gone.is_set():
                data = sp.read(256)
                if data:
                    sock.sendall(data)
                    log(">", data, up)
        except OSError:
            pass
        gone.set()
        sock.close()
        print("ssc_relay: the server dropped; dialling again", flush=True)
        time.sleep(1)


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--port", required=True, help="the serial port (COM3, /dev/ttyUSB0)")
    ap.add_argument("--baud", type=int, default=9600)
    ap.add_argument("--server", required=True, help="host:port of the game server (the address on the product page)")
    ap.add_argument("--retry", type=float, default=5.0, help="seconds between tries when the server does not answer")
    try:
        relay(ap.parse_args())
    except KeyboardInterrupt:
        pass
