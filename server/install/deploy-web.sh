#!/bin/bash
# deploy-web.sh — R9-N2: web/ (both games in the browser) onto the cloud as /srv/play, served by Caddy at /play/:
# https://<host>/play/ (443; a cloud firewall must admit it) and https://<host>:6503/play/. Friday's rebuild is
#     bash web/build.sh && bash server/install/deploy-web.sh
# The folder goes up whole into /srv/play.new and is swapped in (the old one kept as /srv/play.old), then Caddy reloads:
# a player mid-page never gets half of each. The host and the login are the argument, user@host (your SSH key).
#     bash server/install/deploy-web.sh ubuntu@203.0.113.7
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
WEB="$ROOT/web"
[ $# -ge 1 ] || { echo "deploy-web.sh: user@host"; exit 1; }
AT="$1"
[ -f "$WEB/index.html" ] && [ -d "$WEB/apple2ts" ] && [ -f "$WEB/disks/SHA256SUMS.txt" ] || {
    echo "deploy-web.sh: web/ is not built (bash web/build.sh)"; exit 1; }
SSH="ssh -o BatchMode=yes -o ConnectTimeout=15"
tar -C "$WEB" -cf - . | $SSH "$AT" 'set -e
sudo rm -rf /srv/play.new && sudo mkdir -p /srv/play.new && sudo tar -C /srv/play.new -xf - --no-same-owner
sudo rm -rf /srv/play.old
if [ -d /srv/play ]; then sudo mv /srv/play /srv/play.old; fi
sudo mv /srv/play.new /srv/play
sudo systemctl reload caddy
cd /srv/play/disks && sha256sum -c --quiet SHA256SUMS.txt && echo "deploy-web.sh: /srv/play in place, its disks check"'
H="${AT#*@}"
echo "deploy-web.sh: https://$(echo "$H" | tr . -).sslip.io/play/  and :6503/play/"
