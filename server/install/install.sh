#!/bin/sh
# install.sh — the game server on a Raspberry Pi (Raspberry Pi OS) or an Ubuntu box (R1). Run from this folder, as root:
#     sudo sh install.sh
# It makes a system user "trail", copies the server into /opt/trail (trail_server.py, trail_admin.py, badwords.txt,
# INDEPENDENCE's links.txt), builds a Python venv there with pyserial, keeps the database in /var/lib/trail/trail.db,
# and installs and starts the systemd unit trail-server.service (TCP port 6502). Run it again to update: the database
# and badwords.txt are kept (a newer badwords.txt is put beside the old as badwords.txt.new).
# For a test without root or systemd: PREFIX=/tmp/trailtest NO_SYSTEMD=1 sh install.sh (everything under PREFIX).
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
SERVER="$(cd "$HERE/.." && pwd)"
PREFIX="${PREFIX:-}"
OPT="$PREFIX/opt/trail"
VAR="$PREFIX/var/lib/trail"
UNIT="$PREFIX/etc/systemd/system/trail-server.service"
WSUNIT="$PREFIX/etc/systemd/system/trail-ws.service"
DISKUNIT="$PREFIX/etc/systemd/system/trail-disks.service"
DISKS_RW="${DISKS_RW:-/srv/disks-rw}"   # E5b: --web also serves the CoGS card's network disks: /srv/disks read-only by
DISKPORT="${DISKPORT:-6505}"          # Caddy, /DISKS/LATEST.PO writable by disk_origin.py on 127.0.0.1:$DISKPORT
PORT="${PORT:-6502}"
WSPORT="${WSPORT:-6503}"      # R4: ws_relay.py, a browser emulator's serial card (WSPORT=0: no relay)
# R4b: sudo sh install.sh --web <hostname> - the relay behind TLS for a page served over https (a browser refuses ws://
# from one): Caddy answers wss://<hostname>:$WSPORT with a Let's Encrypt certificate (HTTP-01: port 80 must reach the
# box) and passes it to ws_relay on 127.0.0.1:$WSPORT+1. No domain needed: <a-b-c-d>.sslip.io resolves to a.b.c.d.
WEBHOST="${WEBHOST:-}"
if [ "${1:-}" = "--web" ]; then WEBHOST="${2:?install.sh: --web <hostname>, e.g. 158-101-9-238.sslip.io}"; fi
WSLISTEN=0.0.0.0
OPEN="$PORT $WSPORT"
if [ -n "$WEBHOST" ] && [ "$WSPORT" != 0 ]; then
    WSSPORT=$WSPORT
    WSPORT=$((WSPORT + 1))
    WSLISTEN=127.0.0.1
    OPEN="$PORT 80 443 $WSSPORT"       # R9-N2: 443 for the play site (Oracle's edge needs its own rule too)
    DISKHOST="${DISKHOST:-$(echo "$WEBHOST" | sed -n 's/^\([0-9]*\)-\([0-9]*\)-\([0-9]*\)-\([0-9]*\)\.sslip\.io$/\1.\2.\3.\4/p')}"
    DISKHOST="${DISKHOST:-$WEBHOST}"   # the plain-HTTP site for the disks: the bare address of an <a-b-c-d>.sslip.io name
fi

if [ -z "$PREFIX" ] && [ "$(id -u)" != 0 ]; then
    echo "install.sh: run it as root (sudo sh install.sh)"; exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
    echo "install.sh: python3 is missing (sudo apt install python3 python3-venv)"; exit 1
fi
SYSPIP=""
if ! python3 -c "import venv, ensurepip" >/dev/null 2>&1; then
    if [ -z "$PREFIX" ] && command -v apt-get >/dev/null 2>&1; then apt-get install -y python3-venv
    elif python3 -c "import venv, serial" >/dev/null 2>&1; then SYSPIP=1     # no ensurepip, pyserial system-wide: use it
    else echo "install.sh: python3-venv is missing (sudo apt install python3-venv)"; exit 1; fi
fi
if [ -z "$PREFIX" ] && ! id trail >/dev/null 2>&1; then
    useradd --system --home-dir /var/lib/trail --shell /usr/sbin/nologin trail
fi
mkdir -p "$OPT" "$VAR/backups"
cp "$SERVER/trail_server.py" "$SERVER/trail_admin.py" "$SERVER/ws_relay.py" "$SERVER/disk_origin.py" "$HERE/backup.sh" "$OPT/"
if [ ! -f "$SERVER/badwords.txt" ]; then                # (trail-net: bring your own list; none is published)
    echo "install.sh: no server/badwords.txt - the word filter is off until there is one (README)"
elif [ -f "$OPT/badwords.txt" ] && ! cmp -s "$SERVER/badwords.txt" "$OPT/badwords.txt"; then
    cp "$SERVER/badwords.txt" "$OPT/badwords.txt.new"
else
    cp "$SERVER/badwords.txt" "$OPT/badwords.txt"
fi
for f in links.txt links.urls; do
    [ -f "$SERVER/$f" ] && cp "$SERVER/$f" "$OPT/$f"
done
if [ -n "$SYSPIP" ]; then
    [ -d "$OPT/venv" ] || python3 -m venv --without-pip --system-site-packages "$OPT/venv"
else
    [ -d "$OPT/venv" ] || python3 -m venv "$OPT/venv"
    "$OPT/venv/bin/pip" install --quiet --disable-pip-version-check pyserial websockets
fi
if [ -z "$PREFIX" ]; then chown -R trail:trail "$VAR"; fi
mkdir -p "$(dirname "$UNIT")"
sed -e "s|@OPT@|/opt/trail|g" -e "s|@VAR@|/var/lib/trail|g" -e "s|@PORT@|$PORT|g" "$HERE/trail-server.service" > "$UNIT"
if [ "$WSPORT" != 0 ]; then
    sed -e "s|@OPT@|/opt/trail|g" -e "s|@VAR@|/var/lib/trail|g" -e "s|@PORT@|$PORT|g" -e "s|@WSPORT@|$WSPORT|g" \
        -e "s|@WSLISTEN@|$WSLISTEN|g" "$HERE/trail-ws.service" > "$WSUNIT"
fi
if [ -n "$WEBHOST" ] && [ -z "$PREFIX" ] && [ "$WSPORT" != 0 ]; then
    command -v caddy >/dev/null 2>&1 || apt-get install -y caddy
    mkdir -p /etc/caddy
    if [ -f /etc/caddy/Caddyfile ] && ! grep -q "install.sh --web" /etc/caddy/Caddyfile; then
        cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.orig
    fi
    sed -e "s|@WEBHOST@|$WEBHOST|g" -e "s|@WSSPORT@|$WSSPORT|g" -e "s|@WSPORT@|$WSPORT|g" -e "s|@DISKHOST@|$DISKHOST|g" \
        -e "s|@DISKPORT@|$DISKPORT|g" -e "s|@DISKS_RW@|$DISKS_RW|g" "$HERE/Caddyfile.web" > /etc/caddy/Caddyfile
    caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
    mkdir -p /srv/disks "$DISKS_RW" /srv/play
    chown trail:trail "$DISKS_RW"
    sed -e "s|@OPT@|/opt/trail|g" -e "s|@DISKS_RW@|$DISKS_RW|g" -e "s|@DISKPORT@|$DISKPORT|g" "$HERE/trail-disks.service" > "$DISKUNIT"
fi
if [ -z "$PREFIX" ] && command -v iptables >/dev/null 2>&1 && iptables -S INPUT 2>/dev/null | grep -q -- "-j REJECT"; then
    # R4: Oracle Cloud's Ubuntu image ends INPUT with a REJECT (only 22 gets past it): the port goes in before that rule,
    # once, and is saved (netfilter-persistent) so a reboot keeps it. A Pi or a box without such a rule is left alone.
    for p in $OPEN; do
        [ "$p" = 0 ] && continue
        if ! iptables -C INPUT -m state --state NEW -p tcp --dport "$p" -j ACCEPT 2>/dev/null; then
            at=$(iptables -L INPUT --line-numbers -n | awk '$2 == "REJECT" {print $1; exit}')
            iptables -I INPUT "${at:-1}" -m state --state NEW -p tcp --dport "$p" -j ACCEPT
            echo "install.sh: port $p opened in iptables' INPUT (rule $at)"
        fi
    done
    if command -v netfilter-persistent >/dev/null 2>&1; then netfilter-persistent save; fi
fi
if [ -z "${NO_SYSTEMD:-}" ]; then
    systemctl daemon-reload
    systemctl enable --now trail-server.service
    systemctl restart trail-server.service
    if [ "$WSPORT" != 0 ]; then systemctl enable --now trail-ws.service; systemctl restart trail-ws.service; fi
    if [ -n "$WEBHOST" ] && [ "$WSPORT" != 0 ]; then
        systemctl enable --now trail-disks.service; systemctl restart trail-disks.service
        systemctl enable caddy; systemctl restart caddy
    fi
    sleep 1
    systemctl --no-pager --lines=3 status trail-server.service || true
fi
if [ -n "$WEBHOST" ] && [ "$WSPORT" != 0 ]; then
    echo "install.sh: the server is in $OPT, its database in $VAR/trail.db; port $PORT; the browser's wss://$WEBHOST:$WSSPORT (Caddy) -> 127.0.0.1:$WSPORT."
else
    echo "install.sh: the server is in $OPT, its database in $VAR/trail.db; port $PORT (the browser's WebSocket: $WSPORT)."
fi
echo "  the keeper's tool:  sudo -u trail $OPT/venv/bin/python $OPT/trail_admin.py --db $VAR/trail.db list"
echo "  a backup:           sudo -u trail sh $OPT/backup.sh   (or the cron line in backup.sh)"
