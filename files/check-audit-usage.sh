#!/usr/bin/env bash
set -euo pipefail

CONF="/etc/audit-repo-monitor.conf"
[ -f "$CONF" ] || { echo "Missing $CONF"; exit 2; }
# shellcheck disable=SC1090
source "$CONF"

[ -n "${SLACK_WEBHOOK:-}" ] || { echo "SLACK_WEBHOOK not set"; exit 3; }

STATE_DIR="/var/lib/audit-repo-monitor"
mkdir -p "$STATE_DIR"

# Build path -> max_gb for dir quotas (only used if not a separate mount)
declare -A MAX_GB
for kv in ${DIR_MAX_GB:-}; do
  p="${kv%%:*}"; g="${kv##*:}"
  [[ -n "$p" && -n "$g" ]] && MAX_GB["$p"]="$g"
done

slack_post () {
  local text="$1"
  if command -v jq >/dev/null 2>&1; then
    if [ -n "${SLACK_CHANNEL:-}" ]; then
      jq -n --arg text "$text" --arg ch "$SLACK_CHANNEL" '{text:$text, channel:$ch}'
    else
      jq -n --arg text "$text" '{text:$text}'
    fi | curl -sS -X POST -H 'Content-type: application/json' --data @- "$SLACK_WEBHOOK" >/dev/null
  else
    curl -sS -X POST -H 'Content-type: application/json' \
      --data "{\"text\":\"$text\"}" "$SLACK_WEBHOOK" >/dev/null
  fi
}

alert_msg () {
  local level="$1" path="$2" pct="$3" used="$4" cap="$5"
  cat <<MSG
*$level*: Audit repository *$path* is at *$pct%* on *$SYSTEM_TAG*
• Used: $used / Capacity: $cap
• Host: $SYSTEM_TAG
• Time: $(date -Is)
MSG
}

is_mountpoint() { mountpoint -q "$1"; }

check_mount() {
  local path="$1" line pct bu bc used_h cap_h
  line=$(df -P "$path" | awk 'NR==2{print}')
  pct=$(echo "$line" | awk '{print $5}' | tr -d '%')
  bu=$(echo "$line" | awk '{print $3}')
  bc=$(echo "$line" | awk '{print $2}')
  used_h=$(numfmt --to=iec --suffix=B "$((bu*1024))")
  cap_h=$(numfmt --to=iec --suffix=B "$((bc*1024))")
  echo "$pct" "$used_h" "$cap_h"
}

check_dir_quota() {
  local path="$1" max_gb="$2" used_bytes max_bytes pct used_h cap_h
  used_bytes=$(du -sb "$path" 2>/dev/null | awk '{print $1}'); : "${used_bytes:=0}"
  max_bytes=$(( max_gb * 1024 * 1024 * 1024 ))
  pct=$(( used_bytes * 100 / max_bytes ))
  used_h=$(numfmt --to=iec --suffix=B "$used_bytes")
  cap_h=$(numfmt --to=iec --suffix=B "$max_bytes")
  echo "$pct" "$used_h" "$cap_h"
}

EXIT=0
for p in ${AUDIT_PATHS}; do
  state="$STATE_DIR/$(echo "$p" | tr '/' '_').state"

  if is_mountpoint "$p"; then
    read -r pct used cap < <(check_mount "$p")
  else
    if [[ -n "${MAX_GB[$p]:-}" ]]; then
      read -r pct used cap < <(check_dir_quota "$p" "${MAX_GB[$p]}")
    else
      read -r pct used cap < <(check_mount "$p")
    fi
  fi

  if [ "$pct" -ge "${THRESHOLD}" ]; then
    if [ ! -f "$state" ]; then
      slack_post "$(alert_msg "ALERT" "$p" "$pct" "$used" "$cap")"
      echo "at=$(date -Is)" > "$state"
    fi
    EXIT=1
  else
    if [ -f "$state" ]; then
      slack_post "$(alert_msg "RECOVERY" "$p" "$pct" "$used" "$cap")"
      rm -f "$state"
    fi
  fi
done

exit $EXIT
