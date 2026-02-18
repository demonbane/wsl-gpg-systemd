#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOCK="${SSH_AUTH_SOCK_PATH:-/run/user/$(id -u)/gnupg/S.gpg-agent.ssh}"
GPG_SIGN_KEY="${GPG_SIGN_KEY:-}"
GPGCONF_WIN="${GPGCONF_WIN:-$HOME/.local/bin/gpgconf-windows.exe}"

cat <<'MSG'
Cold-start check
- This script reinstalls units, then runs SSH-first and GPG checks.
MSG

echo "[1/5] stopping Windows gpg-agent/scdaemon"
if [ -x "$GPGCONF_WIN" ]; then
	timeout 10 "$GPGCONF_WIN" --kill gpg-agent || true
	timeout 10 "$GPGCONF_WIN" --kill scdaemon || true
elif command -v gpgconf.exe >/dev/null 2>&1; then
	timeout 10 gpgconf.exe --kill gpg-agent || true
	timeout 10 gpgconf.exe --kill scdaemon || true
else
	echo "WARN: no Windows gpgconf found; continuing without forced stop"
fi

echo "[2/5] running installer"
"$ROOT_DIR/install"

echo "[3/5] reloading/restarting user units"
systemctl --user daemon-reload
systemctl --user restart gpg-agent-launch.service
systemctl --user stop 'gpg-agent@*.service' 'gpg-agent-ssh@*.service' || true
systemctl --user reset-failed 'gpg-agent@*' 'gpg-agent-ssh@*' || true
systemctl --user restart gpg-agent.socket gpg-agent-ssh.socket

echo "[4/5] SSH-first check"
if ! SSH_AUTH_SOCK="$SOCK" timeout 15 ssh-add -l >/dev/null 2>&1; then
	echo "FAIL: SSH-first check failed"
	exit 1
fi

if [ -z "$GPG_SIGN_KEY" ]; then
	GPG_SIGN_KEY="$(gpg --list-secret-keys --with-colons 2>/dev/null | awk -F: '/^sec:/ { print $5; exit }')"
fi
if [ -z "$GPG_SIGN_KEY" ]; then
	echo "FAIL: no signing key found. Set GPG_SIGN_KEY to your key ID/fingerprint."
	exit 1
fi

echo "[5/5] GPG reachability/signing check"
if ! timeout 20 gpg-connect-agent "GETINFO version" /bye >/dev/null 2>&1; then
	echo "FAIL: gpg-connect-agent reachability check failed"
	exit 1
fi
if ! printf 'cold-start-check %s\n' "$(date -Is)" | timeout 20 gpg --armor --clearsign --local-user "$GPG_SIGN_KEY" >/dev/null 2>&1; then
	echo "FAIL: GPG clearsign check failed"
	exit 1
fi

echo "PASS: cold-start check completed"
