#!/bin/bash
set -euo pipefail

CRON="${CRON:-}"
RUN_ON_START="${RUN_ON_START:-0}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# systemd-nspawn (devtools clean chroot) requires /etc/machine-id
if [ ! -s /etc/machine-id ]; then
    sudo systemd-machine-id-setup 2>/dev/null || true
fi

if [ -z "$CRON" ]; then
    exec /build.sh
fi

if [ "$RUN_ON_START" = "1" ]; then
    log "Running initial build before starting scheduler..."
    /build.sh || log "Initial build failed (exit $?), scheduler starting anyway"
fi

# Schedule mode: parse |-separated cron expressions into a supercronic crontab
crontab_file="$(mktemp)"
IFS='|' read -ra schedules <<< "$CRON"
for schedule in "${schedules[@]}"; do
    schedule="${schedule#"${schedule%%[![:space:]]*}"}"  # ltrim
    schedule="${schedule%"${schedule##*[![:space:]]}"}"  # rtrim
    [[ -z "$schedule" ]] && continue
    echo "$schedule /build.sh"
done > "$crontab_file"

log "Scheduled builds:"
cat "$crontab_file"

exec supercronic "$crontab_file"
