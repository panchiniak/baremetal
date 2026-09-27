#!/usr/bin/env bash
# setup-vm-ssh.sh — Enable SSH from one VM (origin) to another (target)
#                    and optionally grant passwordless sudo on the target.
#
# Usage:
#   ./setup-vm-ssh.sh <origin-ip> <target-ip> [--sudo]
#
# Examples:
#   ./setup-vm-ssh.sh 192.168.56.10 192.168.56.11           # SSH key only
#   ./setup-vm-ssh.sh 192.168.56.10 192.168.56.11 --sudo    # SSH key + passwordless sudo
#
# Prerequisites:
#   - Both VMs are running and reachable from the host via SSH as vagrant@<ip>.
#   - The host's SSH key is already authorised on both VMs (done by Vagrantfile).
set -euo pipefail

SSH_USER="vagrant"
SSH_OPTS="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10"

# ── Argument parsing ──────────────────────────────────────────────────────────
usage() {
  echo "Usage: $0 <origin-ip> <target-ip> [--sudo]"
  echo
  echo "  origin-ip   IP of the source VM (the one that will SSH out)"
  echo "  target-ip   IP of the destination VM (the one being connected to)"
  echo "  --sudo      Also enable passwordless sudo for vagrant on the target"
  exit 1
}

ORIGIN_IP=""
TARGET_IP=""
ENABLE_SUDO=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sudo)   ENABLE_SUDO=true; shift ;;
    --help|-h) usage ;;
    -*)       echo "Unknown option: $1"; usage ;;
    *)
      if [[ -z "$ORIGIN_IP" ]]; then
        ORIGIN_IP="$1"
      elif [[ -z "$TARGET_IP" ]]; then
        TARGET_IP="$1"
      else
        echo "Too many arguments."; usage
      fi
      shift
      ;;
  esac
done

if [[ -z "$ORIGIN_IP" || -z "$TARGET_IP" ]]; then
  usage
fi

echo "[setup-vm-ssh] Origin : ${SSH_USER}@${ORIGIN_IP}"
echo "[setup-vm-ssh] Target : ${SSH_USER}@${TARGET_IP}"
echo "[setup-vm-ssh] Sudo   : ${ENABLE_SUDO}"
echo

# ── Step 1: Ensure origin has an SSH key pair ─────────────────────────────────
echo "[setup-vm-ssh] Ensuring ${SSH_USER}@${ORIGIN_IP} has an SSH key pair..."

# shellcheck disable=SC2029
ssh $SSH_OPTS "${SSH_USER}@${ORIGIN_IP}" bash -s <<'ORIGIN_SCRIPT'
set -euo pipefail
KEY_PATH="$HOME/.ssh/id_ed25519"
if [ ! -f "$KEY_PATH" ]; then
  echo "  Generating ed25519 key..."
  ssh-keygen -t ed25519 -f "$KEY_PATH" -N "" -q
  echo "  Key generated: $KEY_PATH"
else
  echo "  Key already exists: $KEY_PATH"
fi
ORIGIN_SCRIPT

# ── Step 2: Fetch origin's public key ────────────────────────────────────────
echo "[setup-vm-ssh] Fetching origin's public key..."

ORIGIN_PUBKEY="$(ssh $SSH_OPTS "${SSH_USER}@${ORIGIN_IP}" cat '~/.ssh/id_ed25519.pub')"

if [[ -z "$ORIGIN_PUBKEY" ]]; then
  echo "ERROR: Could not read public key from origin."
  exit 1
fi
echo "  Public key: ${ORIGIN_PUBKEY:0:50}..."

# ── Step 3: Authorise origin's key on target ─────────────────────────────────
echo "[setup-vm-ssh] Adding origin's public key to ${SSH_USER}@${TARGET_IP} authorized_keys..."

# The public key contains spaces (e.g. "ssh-ed25519 AAAA... user@host"), so
# passing it as a positional argument to `bash -s` would word-split it.
# We use an *unquoted* heredoc so the local shell expands $ORIGIN_PUBKEY
# inline.  Remote-side variables use \$ to survive local expansion.
# shellcheck disable=SC2029
ssh $SSH_OPTS "${SSH_USER}@${TARGET_IP}" bash -s <<TARGET_KEY_SCRIPT
set -euo pipefail
PUBKEY='${ORIGIN_PUBKEY}'
AUTH_KEYS="\$HOME/.ssh/authorized_keys"
mkdir -p "\$HOME/.ssh"
chmod 700 "\$HOME/.ssh"
touch "\$AUTH_KEYS"
chmod 600 "\$AUTH_KEYS"
if grep -qxF "\$PUBKEY" "\$AUTH_KEYS" 2>/dev/null; then
  echo "  Key already authorised on target."
else
  echo "\$PUBKEY" >> "\$AUTH_KEYS"
  echo "  Key added to target's authorized_keys."
fi
TARGET_KEY_SCRIPT

# ── Step 4: Add target host key to origin's known_hosts ──────────────────────
echo "[setup-vm-ssh] Adding target host key to origin's known_hosts..."

# shellcheck disable=SC2029
ssh $SSH_OPTS "${SSH_USER}@${ORIGIN_IP}" bash -s -- "$TARGET_IP" <<'KNOWN_HOSTS_SCRIPT'
set -euo pipefail
TARGET_IP="$1"
KNOWN_HOSTS="$HOME/.ssh/known_hosts"
touch "$KNOWN_HOSTS"
# Remove stale entries (if any) and re-scan.
ssh-keygen -R "$TARGET_IP" -f "$KNOWN_HOSTS" 2>/dev/null || true
ssh-keyscan -H "$TARGET_IP" >> "$KNOWN_HOSTS" 2>/dev/null
echo "  Target host key added to origin's known_hosts."
KNOWN_HOSTS_SCRIPT

# ── Step 5: Verify SSH connectivity ──────────────────────────────────────────
echo "[setup-vm-ssh] Verifying SSH from origin to target..."

# shellcheck disable=SC2029
VERIFY_OUTPUT="$(ssh $SSH_OPTS "${SSH_USER}@${ORIGIN_IP}" \
  "ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 ${SSH_USER}@${TARGET_IP} 'echo SSH_OK'" 2>&1)" || true

if echo "$VERIFY_OUTPUT" | grep -q "SSH_OK"; then
  echo "  ✔ SSH from origin → target works."
else
  echo "  ✘ SSH verification failed. Output:"
  echo "    $VERIFY_OUTPUT"
  echo "  You may need to check VM networking or firewall rules."
  exit 1
fi

# ── Step 6 (optional): Passwordless sudo on target ───────────────────────────
if [[ "$ENABLE_SUDO" = true ]]; then
  echo "[setup-vm-ssh] Enabling passwordless sudo for ${SSH_USER} on target..."

  # shellcheck disable=SC2029
  ssh $SSH_OPTS "${SSH_USER}@${TARGET_IP}" bash -s -- "$SSH_USER" <<'SUDO_SCRIPT'
set -euo pipefail
SUDOER="$1"
SUDOERS_FILE="/etc/sudoers.d/${SUDOER}-nopasswd"
RULE="${SUDOER} ALL=(ALL) NOPASSWD:ALL"
if [ -f "$SUDOERS_FILE" ] && grep -qxF "$RULE" "$SUDOERS_FILE" 2>/dev/null; then
  echo "  Passwordless sudo already configured."
else
  echo "$RULE" | sudo tee "$SUDOERS_FILE" > /dev/null
  sudo chmod 0440 "$SUDOERS_FILE"
  # Validate syntax.
  if sudo visudo -cf "$SUDOERS_FILE" >/dev/null 2>&1; then
    echo "  ✔ Passwordless sudo enabled for ${SUDOER}."
  else
    echo "  ✘ sudoers syntax error — removing file to avoid lockout."
    sudo rm -f "$SUDOERS_FILE"
    exit 1
  fi
fi
SUDO_SCRIPT

  # Quick verify.
  echo "[setup-vm-ssh] Verifying passwordless sudo on target..."
  SUDO_CHECK="$(ssh $SSH_OPTS "${SSH_USER}@${TARGET_IP}" "sudo -n whoami" 2>&1)" || true
  if echo "$SUDO_CHECK" | grep -q "root"; then
    echo "  ✔ sudo -n whoami → root (passwordless sudo works)."
  else
    echo "  ✘ Passwordless sudo verification failed: $SUDO_CHECK"
    exit 1
  fi
fi

echo
echo "[setup-vm-ssh] Done."
echo "  From inside ${ORIGIN_IP}, run:  ssh ${SSH_USER}@${TARGET_IP}"
if [[ "$ENABLE_SUDO" = true ]]; then
  echo "  On ${TARGET_IP}, ${SSH_USER} can now use:  sudo <command>  (no password)"
fi
