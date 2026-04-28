#!/usr/bin/env bash

# File: install.sh
# Production-grade Restic backup installer

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYSTEMD_DIR="${SCRIPT_DIR}/systemd"
USER_BIN="/usr/local/bin"

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root to install systemd services and set permissions."
   echo "Run with: sudo ./install.sh"
   exit 1
fi

echo "================================================="
echo "   Restic Google Cloud Backup - Installation"
echo "================================================="

# 1. Check dependencies
if ! command -v restic &> /dev/null; then
    echo "Installing restic..."
    apt-get update && apt-get install -y restic
else
    echo "Restic is already installed."
fi

# 2. Secure script permissions
echo "Securing scripts..."
chmod 700 "${SCRIPT_DIR}/backup.sh"
chmod 700 "${SCRIPT_DIR}/restore.sh"
chmod 600 "${SCRIPT_DIR}/.env.example"
chmod 644 "${SCRIPT_DIR}/exclude.txt"
chmod 644 "${SCRIPT_DIR}/include.txt"

if [[ -f "${SCRIPT_DIR}/.env" ]]; then
    chmod 600 "${SCRIPT_DIR}/.env"
fi
if [[ -f "/opt/restic-backup/.restic_password" ]]; then
    chmod 600 "/opt/restic-backup/.restic_password"
fi

# 3. Ask about scheduling method
echo ""
echo "How would you like to schedule the backup?"
echo "  1) Systemd Timer (Recommended - prevents overlaps, persistent scheduling)"
echo "  2) Cron Job"
read -rp "Enter choice [1 or 2]: " choice

if [[ "$choice" == "1" ]]; then
    echo "Installing Systemd Timer..."
    # Copy systemd files
    cp "${SYSTEMD_DIR}/restic-backup.service" /etc/systemd/system/
    cp "${SYSTEMD_DIR}/restic-backup.timer" /etc/systemd/system/

    # Reload daemon and enable timer
    systemctl daemon-reload
    systemctl enable --now restic-backup.timer

    echo "Systemd timer activated. Check status with: systemctl status restic-backup.timer"
else
    echo "Cron Job selected. Please add the following line to your crontab using 'crontab -e':"
    echo ""
    echo "0 0 * * * ${SCRIPT_DIR}/backup.sh >> ${SCRIPT_DIR}/logs/cron.log 2>&1"
    echo ""
    echo "Note: The backup script itself includes file locking (flock) to prevent overlapping cron runs."
fi

echo "Installation complete!"
echo "Make sure to configure ${SCRIPT_DIR}/.env and place your GCP credentials correctly."
