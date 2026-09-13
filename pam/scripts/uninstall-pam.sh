#!/bin/bash
set -euo pipefail

MODULE_PATH="/usr/local/lib/pam/pam_faceunlock.so"
SUDO_LOCAL="/etc/pam.d/sudo_local"
BACKUP="/etc/pam.d/sudo_local.bak-faceunlock"

if [ -f "$BACKUP" ]; then
    echo "Restoring $SUDO_LOCAL from backup taken at install time..."
    sudo cp "$BACKUP" "$SUDO_LOCAL"
    sudo rm -f "$BACKUP"
elif [ -f "$SUDO_LOCAL" ]; then
    echo "No pre-install backup exists (sudo_local didn't exist before install) -- removing the face-unlock line only..."
    sudo sed -i '' '\#'"$MODULE_PATH"'#d' "$SUDO_LOCAL"
fi

echo "Removing installed module..."
sudo rm -f "$MODULE_PATH"

echo "Uninstalled. sudo should behave exactly as it did before face-unlock was installed."
