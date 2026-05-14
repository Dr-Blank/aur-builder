#!/bin/bash
set -euo pipefail

CRON="${CRON:-}"
RUN_ON_START="${RUN_ON_START:-0}"

if [ -z "$CRON" ]; then
    exec /build.sh
fi

if [ "$RUN_ON_START" = "1" ]; then
    echo "Running initial build before starting scheduler..."
    /build.sh
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

echo "Scheduled builds:"
cat "$crontab_file"

exec supercronic "$crontab_file"
