#!/usr/bin/env bash
# Automated Linux system maintenance: daily report, timestamped log, retention cleanup.
set -Eeuo pipefail
umask 077

BASE_DIR="${MAINTENANCE_DIR:-${HOME:-}/.local/state/linux-maintenance}"
LOG_DIR="${BASE_DIR}/logs"
REPORT_DIR="${BASE_DIR}/reports"
LOG_FILE="${LOG_DIR}/maintenance.log"
LOCK_DIR="${BASE_DIR}/maintenance.lock"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
TEMP_FILE=""
LOCK_ACQUIRED=0

timestamp() { date '+%Y-%m-%d %H:%M:%S'; }

log() {
    local level="$1"
    shift
    printf '%s [%s] %s\n' "$(timestamp)" "$level" "$*" | tee -a "$LOG_FILE"
}

on_error() {
    local status="$1" line="$2" command="$3"
    trap - ERR
    if [[ -n "${LOG_FILE:-}" && -d "${LOG_DIR:-}" ]]; then
        log "ERROR" "Command failed at line ${line}: ${command} (exit ${status})" || true
    else
        printf '%s [ERROR] Startup failed at line %s: %s (exit %s)\n' \
            "$(timestamp)" "$line" "$command" "$status" >&2
    fi
    exit "$status"
}

cleanup() {
    local status=$?
    if [[ -n "$TEMP_FILE" && -f "$TEMP_FILE" ]]; then
        rm -f -- "$TEMP_FILE" || true
    fi
    if (( LOCK_ACQUIRED == 1 )); then
        rmdir -- "$LOCK_DIR" 2>/dev/null || true
    fi
    return "$status"
}

trap 'on_error "$?" "$LINENO" "$BASH_COMMAND"' ERR
trap cleanup EXIT

if [[ -z "${HOME:-}" && -z "${MAINTENANCE_DIR:-}" ]]; then
    printf 'ERROR: HOME is unset. Set MAINTENANCE_DIR to continue.\n' >&2
    exit 1
fi

if [[ ! "$RETENTION_DAYS" =~ ^[0-9]+$ ]] ||
   (( RETENTION_DAYS < 1 || RETENTION_DAYS > 365 )); then
    printf 'ERROR: RETENTION_DAYS must be an integer from 1 to 365.\n' >&2
    exit 1
fi

required_commands=(date hostname uname uptime df free find mktemp mv rm tee mkdir rmdir)
for command_name in "${required_commands[@]}"; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        printf 'ERROR: Required command not found: %s\n' "$command_name" >&2
        exit 1
    fi
done

mkdir -p -- "$LOG_DIR" "$REPORT_DIR"
log "INFO" "Maintenance run started."
log "INFO" "Report retention is set to ${RETENTION_DAYS} day(s)."

# Prevent overlapping runs from modifying the same files.
if ! mkdir -- "$LOCK_DIR" 2>/dev/null; then
    log "ERROR" "Another maintenance run may already be active; lock exists at ${LOCK_DIR}."
    exit 1
fi
LOCK_ACQUIRED=1

REPORT_DATE="$(date '+%Y-%m-%d')"
REPORT_FILE="${REPORT_DIR}/system-report-${REPORT_DATE}.txt"
TEMP_FILE="$(mktemp "${REPORT_DIR}/.system-report.XXXXXX")"

{
    printf '%s\n' "LINUX SYSTEM MAINTENANCE REPORT"
    printf '%s\n' "================================"
    printf 'Generated: %s\n' "$(timestamp)"
    printf 'Hostname: %s\n' "$(hostname)"
    printf 'Kernel: %s\n' "$(uname -sr)"
    printf '\n%s\n' "--- SYSTEM UPTIME ---"
    uptime
    printf '\n%s\n' "--- DISK USAGE ---"
    df -hP
    printf '\n%s\n' "--- MEMORY USAGE ---"
    free -h
} > "$TEMP_FILE"

# Atomic rename prevents readers from seeing a partially written report.
mv -f -- "$TEMP_FILE" "$REPORT_FILE"
TEMP_FILE=""
log "INFO" "System report generated: ${REPORT_FILE}"

# Only date-named reports in this dedicated directory are eligible for deletion.
find "$REPORT_DIR" -maxdepth 1 -type f \
    -name 'system-report-????-??-??.txt' \
    -mtime "+${RETENTION_DAYS}" -delete

log "INFO" "Old report cleanup completed."
log "INFO" "Maintenance run completed successfully."
