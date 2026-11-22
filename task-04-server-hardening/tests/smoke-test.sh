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
echo "[TEST] Invalid backup retention must be rejected"
if RETENTION_DAYS=0 bash "$ROOT/scripts/backup.sh" >"$tmp" 2>&1; then
  echo "FAIL: invalid retention accepted" >&2; exit 1
fi
grep -q "RETENTION_DAYS must be 1..365" "$tmp"
echo "All smoke tests passed."
