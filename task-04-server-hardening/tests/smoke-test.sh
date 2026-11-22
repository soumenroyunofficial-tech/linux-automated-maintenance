#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
echo "[TEST] Bash syntax"
bash -n "$ROOT/scripts/provision.sh"
bash -n "$ROOT/scripts/backup.sh"
bash -n "$ROOT/tests/smoke-test.sh"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
echo "[TEST] Placeholder SSH key must be rejected"
if CONFIG_FILE="$ROOT/config/server-hardening.conf.example" bash "$ROOT/scripts/provision.sh" --dry-run >"$tmp" 2>&1; then
  echo "FAIL: placeholder config accepted" >&2; exit 1
fi
grep -q "Replace SSH_PUBLIC_KEY placeholder" "$tmp"
echo "[TEST] Valid configuration dry-run completes without applying changes"
cat >"$tmp" <<'CONFIG'
ADMIN_USER="opsadmin"
SSH_PORT="2222"
SSH_PUBLIC_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEexampleKeyMaterialForSyntaxTestOnly test"
BACKUP_DIR="/tmp/server-hardening-test-backups"
RETENTION_DAYS="14"
CONFIG
CONFIG_FILE="$tmp" bash "$ROOT/scripts/provision.sh" --dry-run >"$tmp.output"
grep -q "Provisioning complete" "$tmp.output"
rm -f "$tmp.output"
echo "[TEST] Invalid backup retention must be rejected"
if RETENTION_DAYS=0 bash "$ROOT/scripts/backup.sh" >"$tmp" 2>&1; then
  echo "FAIL: invalid retention accepted" >&2; exit 1
fi
grep -q "RETENTION_DAYS must be 1..365" "$tmp"
echo "All smoke tests passed."
