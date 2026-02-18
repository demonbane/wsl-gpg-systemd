#!/usr/bin/env bash
set -euo pipefail

SOCK="${SSH_AUTH_SOCK_PATH:-/run/user/$(id -u)/gnupg/S.gpg-agent.ssh}"
GPG_SIGN_KEY="${GPG_SIGN_KEY:-}"
SSH_TIMEOUT="${SSH_TIMEOUT:-15}"
GPG_TIMEOUT="${GPG_TIMEOUT:-20}"

print_diag() {
	echo
	echo "=== diagnostics ==="
	systemctl --user show gpg-agent.socket -p ActiveState -p NAccepted || true
	systemctl --user show gpg-agent-ssh.socket -p ActiveState -p NAccepted || true
	systemctl --user list-units 'gpg-agent@*.service' 'gpg-agent-ssh@*.service' --all --no-pager || true
	journalctl --user -b -u 'gpg-agent@*' -u 'gpg-agent-ssh@*' -n 40 --no-pager || true
}

if [ -z "$GPG_SIGN_KEY" ]; then
	GPG_SIGN_KEY="$(gpg --list-secret-keys --with-colons 2>/dev/null | awk -F: '/^sec:/ { print $5; exit }')"
fi

if [ -z "$GPG_SIGN_KEY" ]; then
	echo "FAIL: no signing key found. Set GPG_SIGN_KEY to your key ID/fingerprint."
	exit 1
fi

echo "[1/4] checking SSH agent via $SOCK"
if ! SSH_AUTH_SOCK="$SOCK" timeout "$SSH_TIMEOUT" ssh-add -l >/dev/null 2>&1; then
	echo "FAIL: ssh-add -l failed"
	print_diag
	exit 1
fi

echo "[2/4] checking gpg-agent reachability"
if ! timeout "$GPG_TIMEOUT" gpg-connect-agent "GETINFO version" /bye >/dev/null 2>&1; then
	echo "FAIL: gpg-connect-agent reachability check failed"
	print_diag
	exit 1
fi

echo "[3/4] checking GPG signing via key $GPG_SIGN_KEY"
if ! printf 'integration-check %s\n' "$(date -Is)" | timeout "$GPG_TIMEOUT" gpg --armor --clearsign --local-user "$GPG_SIGN_KEY" >/dev/null 2>&1; then
	echo "FAIL: gpg clearsign failed"
	print_diag
	exit 1
fi

echo "[4/4] checks passed"
