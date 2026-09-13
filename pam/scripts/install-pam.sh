#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAM_ROOT="$(dirname "$SCRIPT_DIR")"

MODULE_DIR="/usr/local/lib/pam"
MODULE_PATH="$MODULE_DIR/pam_faceunlock.so"
SUDO_LOCAL="/etc/pam.d/sudo_local"
BACKUP="/etc/pam.d/sudo_local.bak-faceunlock"
PAM_LINE="auth       sufficient     $MODULE_PATH"

echo "Building pam_faceunlock.so..."
(cd "$PAM_ROOT" && make)

echo "Running unit tests before installing..."
(cd "$PAM_ROOT" && make test)

echo "Installing module to $MODULE_PATH (requires sudo)..."
sudo mkdir -p "$MODULE_DIR"
sudo cp "$PAM_ROOT/pam_faceunlock.so" "$MODULE_PATH"
sudo chown root:wheel "$MODULE_PATH"
sudo chmod 644 "$MODULE_PATH"

if [ -f "$SUDO_LOCAL" ] && [ ! -f "$BACKUP" ]; then
    echo "Backing up existing $SUDO_LOCAL to $BACKUP"
    sudo cp "$SUDO_LOCAL" "$BACKUP"
fi

if [ -f "$SUDO_LOCAL" ] && grep -qF "$MODULE_PATH" "$SUDO_LOCAL"; then
    echo "sudo_local already references pam_faceunlock.so -- nothing to add."
else
    echo "$PAM_LINE" | sudo tee -a "$SUDO_LOCAL" > /dev/null
    echo "Added face-unlock line to $SUDO_LOCAL."
fi

cat <<'EOF'

Installed. IMPORTANT SAFETY STEP:
  Keep THIS terminal window open. Open a NEW terminal window and run a
  harmless sudo command there (e.g. `sudo -v`) to confirm sudo still works.
  Only close this terminal after that succeeds.

  If sudo is broken, run this terminal's rescue command immediately:
    sudo cp /etc/pam.d/sudo_local.bak-faceunlock /etc/pam.d/sudo_local
  (or, if there was no pre-existing sudo_local: sudo rm /etc/pam.d/sudo_local)

  To fully uninstall later: pam/scripts/uninstall-pam.sh
EOF
