#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
UNIT_DIR="$HOME/.config/systemd/user"
mkdir -p "$UNIT_DIR"
chmod +x "$DIR/backup.sh" "$DIR/restore.sh"

cat > "$UNIT_DIR/opencart-backup.service" <<EOF
[Unit]
Description=OpenCart backup to Google Drive

[Service]
Type=oneshot
ExecStart=$DIR/backup.sh
EOF

cat > "$UNIT_DIR/opencart-backup.timer" <<'EOF'
[Unit]
Description=Daily OpenCart backup

[Timer]
OnCalendar=*-*-* 03:00
Persistent=true
RandomizedDelaySec=10min

[Install]
WantedBy=timers.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now opencart-backup.timer
sudo loginctl enable-linger "$USER"

echo "Scheduled. Running the first backup now..."
if systemctl --user start opencart-backup.service; then
  echo "First backup succeeded."
else
  echo "First backup FAILED - see the log below."
fi
journalctl --user -u opencart-backup.service -n 15 --no-pager -o cat

echo
echo "Next scheduled run:"
systemctl --user list-timers opencart-backup.timer --no-pager
