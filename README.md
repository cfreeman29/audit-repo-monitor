# 📘 Audit Repository Monitor

A tiny, self-contained utility for **Ubuntu** systems that sends **Slack alerts** when the audit log repository (e.g., `/var/log/audit`) reaches a defined capacity threshold (default **75%**). Designed for fast rollout across many Docker/Linux hosts with a single `git clone && sudo ./install.sh`.

---

## 🚀 Why this exists

Security and compliance frameworks (e.g., DISA STIG / NIST 800‑53 AU controls) require immediate warning to SAs/ISSOs when **audit storage** approaches capacity. This project provides a minimal, dependency-light solution using **Bash + systemd**—no Prometheus, no agents, no heavyweight stack.

- **Immediate warning** at or above a threshold (default **75%**)
- **Recovery notice** when usage drops back below the threshold
- Works whether `/var/log/audit` is on a **shared** partition or a **dedicated** mount

---

## ✨ Features

- ✅ Monitors `/var/log/audit` (or any path you configure)
- 📣 Slack alerts via Incoming Webhook (optional channel override supported)
- ⚙️ Threshold configurable (percent) per host
- 🧮 Supports either **filesystem %** (for mount points) or **directory GB quota**
- 🔁 systemd **timer** checks every minute (default; configurable)
- 🧱 Idempotent **installer**; safe to re-run
- 🧹 Clean **uninstaller**
- 🧪 Quick test flow to verify the integration

---

## 📦 Repository layout

```
audit-repo-monitor/
├─ install.sh
├─ uninstall.sh
├─ files/
│  ├─ check-audit-usage.sh
│  ├─ audit-repo-monitor.service
│  ├─ audit-repo-monitor.timer
│  └─ audit-repo-monitor.conf.example
└─ README.md
```

- `install.sh` renders `/etc/audit-repo-monitor.conf` from your flags (webhook, channel, threshold, etc.), installs the script and units, and enables the timer.
- `check-audit-usage.sh` contains the monitoring logic.
- `audit-repo-monitor.service` / `audit-repo-monitor.timer` schedule execution.
- `uninstall.sh` removes everything cleanly.

---

## 🛠️ Requirements

- Ubuntu / Debian-like host (tested on Ubuntu)
- `bash`, `systemd`
- `curl` and `jq` (installer will install on Ubuntu/Debian; otherwise install yourself)
- Slack Incoming Webhook URL

> No email/SMTP needed. This repo is **Slack-only** out-of-the-box.

---

## ⚡ Quick start (most users)

```bash
git clone <YOUR-REPO-URL> /opt/audit-repo-monitor
cd /opt/audit-repo-monitor

sudo ./install.sh \
  --webhook "https://hooks.slack.com/services/XXX/YYY/ZZZ" \
  --channel "#security-alerts" \
  --threshold 75 \
  --dir-max-gb 8
```

- `--webhook` (**required**): Slack Incoming Webhook URL.
- `--channel` (**optional**): override channel if your webhook isn’t channel-bound.
- `--threshold` (**optional**): percent; default `75`.
- `--dir-max-gb` (**optional**): directory quota (GB) for `/var/log/audit` **if it’s not a dedicated partition**.

### Test alerts quickly

Lower threshold temporarily, run the service once, then restore:

```bash
sudo sed -i 's/^THRESHOLD=.*/THRESHOLD=1/' /etc/audit-repo-monitor.conf
sudo systemctl start audit-repo-monitor.service    # expect ALERT in Slack

sudo sed -i 's/^THRESHOLD=.*/THRESHOLD=75/' /etc/audit-repo-monitor.conf
sudo systemctl start audit-repo-monitor.service    # expect RECOVERY in Slack
```

---

## 🔧 Installing at scale

On each host:

```bash
git clone <YOUR-REPO-URL> /opt/audit-repo-monitor
cd /opt/audit-repo-monitor
sudo ./install.sh --webhook "https://hooks.slack.com/services/XXX/YYY/ZZZ" \
                  --channel "#security-alerts" \
                  --threshold 75 \
                  --dir-max-gb 8
```

Tips:
- Use `--force` to overwrite existing config/scripts if you update the repo.
- Use `--dry-run` to show actions without changing the system.
- If `/var/log/audit` is its **own mount** on some hosts, set `DIR_MAX_GB=""` in `/etc/audit-repo-monitor.conf` (or re-run `install.sh --force` with updated defaults). The script will automatically use **filesystem %** from `df` for mount points.

---

## ⚙️ How it works

1. **Configuration** lives in `/etc/audit-repo-monitor.conf`:
   - `AUDIT_PATHS`: paths to monitor (default: `/var/log/audit`)
   - `THRESHOLD`: percent threshold (default: `75`)
   - `DIR_MAX_GB`: list of `path:GB` quota pairs (used when path is not a mount)
   - `SLACK_WEBHOOK` and optional `SLACK_CHANNEL`
   - `SYSTEM_TAG`: host identifier (defaults to `hostname -f`)
2. **Execution** via `systemd timer` every 60 seconds (configurable).
3. For each path, the script determines:
   - If it’s a **mount point** → use `df` to get filesystem usage %.
   - Otherwise → compute directory usage with `du -sb` and compare to configured **GB quota**.
4. **Alerting** via Slack when `usage >= THRESHOLD` (sends once per breach).
5. **Recovery** message when usage returns below threshold (sends once per recovery).

This de-spams alerts while still notifying immediately on breach and on recovery.

---

## 🧩 Example: `/etc/audit-repo-monitor.conf`

```bash
# Single audit repository
AUDIT_PATHS="/var/log/audit"

# Alert threshold (percent)
THRESHOLD=75

# OPTION A: /var/log/audit on a shared partition → use directory quota
DIR_MAX_GB="/var/log/audit:8"

# OPTION B: /var/log/audit is its own mount → comment out the line above
# DIR_MAX_GB=""

# Slack
SLACK_WEBHOOK="https://hooks.slack.com/services/PASTE/YOURS/HERE"
# SLACK_CHANNEL="#security-alerts"   # optional

# Label in messages
SYSTEM_TAG="$(hostname -f)"
```

---

## 🔍 Verifying your setup

- Check timer status:  
  ```bash
  systemctl status audit-repo-monitor.timer
  ```
- See last run / logs:  
  ```bash
  journalctl -u audit-repo-monitor.service --no-pager -n 100
  ```
- Dry run install on a new host (no changes):
  ```bash
  sudo ./install.sh --webhook "https://hooks.slack.com/services/..." --dry-run
  ```

---

## 🧪 Tuning & operations

- **Interval**: Edit `/etc/systemd/system/audit-repo-monitor.timer`:
  ```ini
  [Timer]
  OnBootSec=1min
  OnUnitActiveSec=60s   # increase for fewer checks, decrease for more
  ```
  Then `sudo systemctl daemon-reload && sudo systemctl restart audit-repo-monitor.timer`.

- **Multiple paths**: You can monitor more than one path:
  ```bash
  AUDIT_PATHS="/var/log/audit /some/other/audit/dir"
  DIR_MAX_GB="/var/log/audit:8 /some/other/audit/dir:20"
  ```

- **Hostname label**: Override `SYSTEM_TAG` to a CMDB name or role:
  ```bash
  SYSTEM_TAG="prod-classroom-02"
  ```

---

## 🔐 Security considerations

- The script reads sizes and posts to Slack only; no privileged network actions beyond webhook POST.
- Restrict repo and config permissions:
  - `/usr/local/bin/check-audit-usage.sh` → `0755`
  - `/etc/audit-repo-monitor.conf` → `0644` (contains webhook URL; protect your host accordingly)
- Consider scoping your Slack webhook to a dedicated channel and limit who can read `/etc/audit-repo-monitor.conf`.

---

## 🧹 Uninstall

```bash
cd /opt/audit-repo-monitor
sudo ./uninstall.sh
```

What it does:
- Disables/stops the timer
- Removes systemd units, script, config, and state dir

---

## ❓ FAQ

**Q: Does this rotate or prune logs?**  
A: No. It only **monitors** and **alerts**. Use `auditd`/logrotate policies to manage retention.

**Q: Can we alert Teams/email instead of Slack?**  
A: This repo is Slack-only by default. You can fork and swap the `slack_post` function to call your preferred destination.

**Q: Will it spam Slack every minute above threshold?**  
A: No. It sends a **single alert** when crossing the threshold and one **recovery** when it drops back below.

**Q: What happens if `/var/log/audit` is empty or missing?**  
A: `du -sb` returns `0`; you won’t get alerts unless the path grows. Ensure your audit pipeline is writing to this path.

**Q: Do I need to restart after editing the config?**  
A: No restart is required; the script reloads the config each run. You can trigger an immediate run with:
```bash
sudo systemctl start audit-repo-monitor.service
```

---

## 🧭 Troubleshooting

- **No alerts arriving**  
  - Confirm `SLACK_WEBHOOK` is correct in `/etc/audit-repo-monitor.conf`.
  - Run once and check exit code / logs:
    ```bash
    sudo /usr/local/bin/check-audit-usage.sh; echo $?
    journalctl -u audit-repo-monitor.service -n 50 --no-pager
    ```
  - Temporarily set `THRESHOLD=1` to force an alert.

- **Always 0% when using directory mode**  
  - Ensure `DIR_MAX_GB` includes the exact path (e.g., `/var/log/audit:8`).
  - If `/var/log/audit` is a mount point, either remove it from `DIR_MAX_GB` or set `DIR_MAX_GB=""` and let the script use filesystem `%`.

- **Permission errors on install**  
  - Run `install.sh` with `sudo` (root required to install system files/units).

- **Timer not running**  
  - `systemctl list-timers | grep audit-repo-monitor`
  - `sudo systemctl enable --now audit-repo-monitor.timer`

---

## 🔄 Updating

If you change files in `files/` (script or units), re-run:

```bash
sudo ./install.sh --webhook "https://hooks.slack.com/services/..." --force
```

This overwrites the installed files and reloads systemd units.

---

## 🧰 Developer notes

- **Script**: POSIX-ish Bash, `set -euo pipefail`
- **Units**: `Type=oneshot` service, timer-driven
- **State**: `/var/lib/audit-repo-monitor/*.state` prevents alert spam and tracks recovery edges
- **Logs**: Use `journalctl -u audit-repo-monitor.service` for execution logs (Slack posts are not echoed unless errors occur)

---

## 📄 License

MIT License. See `LICENSE` (or include your organization’s preferred license).

---

## 🗓️ Changelog (template)

- **v1.0.0** — Initial release: Slack alerting, threshold + recovery, directory and mount detection, installer/uninstaller, docs.
