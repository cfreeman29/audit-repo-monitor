#!/usr/bin/env bash
set -euo pipefail

BIN_DST="/usr/local/bin/check-audit-usage.sh"
CONF_DST="/etc/audit-repo-monitor.conf"
SVC_DST="/etc/systemd/system/audit-repo-monitor.service"
TMR_DST="/etc/systemd/system/audit-repo-monitor.timer"
STATE_DIR="/var/lib/audit-repo-monitor"

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (sudo)." >&2; exit 1
fi

systemctl disable --now audit-repo-monitor.timer 2>/dev/null || true
rm -f "$TMR_DST" "$SVC_DST"
systemctl daemon-reload || true

rm -f "$BIN_DST"
rm -f "$CONF_DST"
rm -rf "$STATE_DIR"

echo "Uninstalled audit-repo-monitor."
