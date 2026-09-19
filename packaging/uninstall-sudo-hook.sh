#!/bin/bash
# Removes the sudo face-unlock hook that older versions installed.
# Hey Mac runs this once (with an administrator prompt) if it finds the leftovers.
set -euo pipefail

MODULE_PATH="/usr/local/lib/pam/pam_faceunlock.so"
SUDO_LOCAL="/etc/pam.d/sudo_local"
BACKUP="/etc/pam.d/sudo_local.bak-faceunlock"
REFERENCE_COPY="/etc/pam.d/sudo.bak-faceunlock-reference"

if [ -f "$SUDO_LOCAL" ]; then
    echo "Removing the face-unlock line from $SUDO_LOCAL (leaving any other edits intact)..."
    sed -i '' '\#'"$MODULE_PATH"'#d' "$SUDO_LOCAL"
fi

rm -f "$BACKUP" "$REFERENCE_COPY" "$MODULE_PATH"

echo "Done. sudo behaves exactly as it did before face-unlock was installed."
