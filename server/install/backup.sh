#!/bin/sh
# backup.sh — a dated copy of the game server's database (R1). sqlite's own backup (safe while the server runs):
#     sh backup.sh [database] [folder]     (default /var/lib/trail/trail.db into /var/lib/trail/backups)
# Keeps the newest 30. A nightly cron line for the trail user (crontab -u trail -e):
#     15 4 * * * sh /opt/trail/backup.sh
set -eu
DB="${1:-${TRAIL_DB:-/var/lib/trail/trail.db}}"
DIR="${2:-$(dirname "$DB")/backups}"
mkdir -p "$DIR"
OUT="$DIR/trail-$(date -u +%Y%m%d-%H%M%S).db"
python3 - "$DB" "$OUT" <<'PY'
import sqlite3, sys
src, dst = sqlite3.connect(sys.argv[1]), sqlite3.connect(sys.argv[2])
with dst:
    src.backup(dst)
dst.close(); src.close()
PY
ls -1t "$DIR"/trail-*.db 2>/dev/null | tail -n +31 | while read -r old; do rm -f "$old"; done
echo "backup.sh: $OUT"
