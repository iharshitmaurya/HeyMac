#!/bin/bash
set -euo pipefail

MODULE_PATH="/usr/local/lib/pam/pam_faceunlock.so"
SUDO_LOCAL="/etc/pam.d/sudo_local"
BACKUP="/etc/pam.d/sudo_local.bak-faceunlock"

if [ -f "$SUDO_LOCAL" ]; then
    echo "Removing face-unlock line from $SUDO_LOCAL (leaving any other edits intact)..."
    sudo sed -i '' '\#'"$MODULE_PATH"'#d' "$SUDO_LOCAL"
fi

if [ -f "$BACKUP" ]; then
    echo "Removing install-time backup $BACKUP (no longer needed)..."
    sudo rm -f "$BACKUP"
fi

echo "Removing installed module..."
sudo rm -f "$MODULE_PATH"

echo "Uninstalled. sudo should behave exactly as it did before face-unlock was installed."
