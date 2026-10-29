#!/bin/sh
# uninstall.sh — takes back what install.sh put in (R2a): the service stopped and disabled, its unit, /opt/trail. The
# database stays in /var/lib/trail (and the user trail with it) unless --purge: then they go too. As root:
#     sudo sh uninstall.sh [--purge]
# python3-venv, if install.sh had apt install it, stays (other programs may use it).
set -eu
PREFIX="${PREFIX:-}"
UNIT="$PREFIX/etc/systemd/system/trail-server.service"
if [ -z "$PREFIX" ] && [ "$(id -u)" != 0 ]; then
    echo "uninstall.sh: run it as root (sudo sh uninstall.sh)"; exit 1
fi
if [ -z "$PREFIX" ] && command -v systemctl >/dev/null 2>&1; then
    systemctl disable --now trail-server.service 2>/dev/null || true
    systemctl disable --now trail-ws.service 2>/dev/null || true
fi
rm -f "$UNIT" "$PREFIX/etc/systemd/system/trail-ws.service"
[ -z "$PREFIX" ] && command -v systemctl >/dev/null 2>&1 && systemctl daemon-reload
rm -rf "$PREFIX/opt/trail"
if [ "${1:-}" = "--purge" ]; then
    rm -rf "$PREFIX/var/lib/trail"
    if [ -z "$PREFIX" ] && id trail >/dev/null 2>&1; then userdel trail; fi
    echo "uninstall.sh: the server, its database and the user trail are gone."
else
    echo "uninstall.sh: the server is gone; its database stays in $PREFIX/var/lib/trail (--purge removes it and the user trail)."
fi
