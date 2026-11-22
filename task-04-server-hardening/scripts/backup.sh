#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
BACKUP_DIR="${BACKUP_DIR:-/var/backups/server-hardening}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"
LOG_DIR=/var/log/server-hardening
LOG_FILE=$LOG_DIR/backup.log
LOCK=/run/lock/server-hardening-backup.lock
TMP=
log(){ local s="[$(date -Is)] $*"; printf '%s\n' "$s"; [[ ! -d "$LOG_DIR" ]] || printf '%s\n' "$s" >>"$LOG_FILE"; }
fail(){ log "ERROR: $*"; exit 1; }
cleanup(){ [[ -z "$TMP" ]] || rm -f -- "$TMP"; rmdir "$LOCK" 2>/dev/null || true; }
trap cleanup EXIT
trap 'fail "Command failed near line $LINENO."' ERR
[[ $EUID -eq 0 ]] || fail "Run as root."
[[ "$RETENTION_DAYS" =~ ^[0-9]+$ ]] && ((RETENTION_DAYS>=1 && RETENTION_DAYS<=365)) || fail "RETENTION_DAYS must be 1..365."
install -d -m 750 "$LOG_DIR"
install -d -m 700 "$BACKUP_DIR"
mkdir "$LOCK" 2>/dev/null || fail "Backup lock exists; check for another or stale run."
HOST="$(hostname -s)"; STAMP="$(date +%Y%m%d-%H%M%S)"
FINAL="$BACKUP_DIR/$HOST-config-$STAMP.tar.gz"
TMP="$(mktemp "$BACKUP_DIR/.backup.XXXXXX")"
SOURCES=()
for p in /etc /home /var/www; do [[ ! -e "$p" ]] || SOURCES+=("$p"); done
(("${#SOURCES[@]}" > 0)) || fail "No backup source paths exist."
log "Starting backup of: ${SOURCES[*]}"
tar --acls --xattrs --numeric-owner -czf "$TMP" "${SOURCES[@]}"
gzip -t "$TMP"
chmod 600 "$TMP"
mv -- "$TMP" "$FINAL"; TMP=
find "$BACKUP_DIR" -maxdepth 1 -type f -name '*-config-*.tar.gz' -mtime +"$RETENTION_DAYS" -print -delete
log "Backup completed: $FINAL"
