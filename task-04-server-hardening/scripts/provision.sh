#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
CONFIG_FILE="${CONFIG_FILE:-/etc/server-hardening.conf}"
DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1
[[ $# -le 1 ]] || { echo "Usage: $0 [--dry-run]" >&2; exit 2; }
log(){ printf '[%s] %s\n' "$(date -Is)" "$*"; }
die(){ log "ERROR: $*"; exit 1; }
run(){ if ((DRY_RUN)); then printf '[DRY-RUN]'; printf ' %q' "$@"; printf '\n'; else "$@"; fi; }
((DRY_RUN)) || [[ $EUID -eq 0 ]] || die "Run as root (dry-run may be run without root)."
[[ -r "$CONFIG_FILE" ]] || die "Config not readable: $CONFIG_FILE"
# shellcheck disable=SC1090
source "$CONFIG_FILE"
: "${ADMIN_USER:?ADMIN_USER required}"
: "${SSH_PORT:?SSH_PORT required}"
: "${SSH_PUBLIC_KEY:?SSH_PUBLIC_KEY required}"
: "${BACKUP_DIR:=/var/backups/server-hardening}"
: "${RETENTION_DAYS:=14}"
[[ "$ADMIN_USER" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || die "Invalid admin username."
[[ "$SSH_PORT" =~ ^[0-9]+$ ]] && ((SSH_PORT>0 && SSH_PORT<=65535)) || die "Invalid SSH port."
[[ "$SSH_PUBLIC_KEY" != "REPLACE_WITH_YOUR_SSH_PUBLIC_KEY" ]] || die "Replace SSH_PUBLIC_KEY placeholder."
[[ "$SSH_PUBLIC_KEY" =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256)[[:space:]]+[A-Za-z0-9+/=]+ ]] || die "Invalid SSH public key format."
[[ "$RETENTION_DAYS" =~ ^[0-9]+$ ]] && ((RETENTION_DAYS>=1 && RETENTION_DAYS<=365)) || die "RETENTION_DAYS must be 1..365."
command -v apt-get >/dev/null || die "This script supports Debian/Ubuntu with apt-get."
log "Provisioning started; dry_run=$DRY_RUN"
run apt-get update
run apt-get install -y openssh-server ufw logrotate cron openssl
if ! getent passwd "$ADMIN_USER" >/dev/null; then
  run useradd --create-home --shell /bin/bash "$ADMIN_USER"
  if ((DRY_RUN)); then
    log "Would initialize a random temporary password hash; set the administrator's own password from the recovery console after provisioning."
  else
    INITIAL_PASSWORD="$(openssl rand -base64 48)"
    printf '%s:%s\n' "$ADMIN_USER" "$INITIAL_PASSWORD" | chpasswd
    unset INITIAL_PASSWORD
  fi
fi
run usermod -aG sudo "$ADMIN_USER"
if ((DRY_RUN)); then
  log "Would install the configured public key for $ADMIN_USER."
else
  HOME_DIR="$(getent passwd "$ADMIN_USER" | cut -d: -f6)"
  [[ -n "$HOME_DIR" && -d "$HOME_DIR" ]] || die "Cannot resolve admin home."
  install -d -m 700 -o "$ADMIN_USER" -g "$ADMIN_USER" "$HOME_DIR/.ssh"
  touch "$HOME_DIR/.ssh/authorized_keys"
  chown "$ADMIN_USER:$ADMIN_USER" "$HOME_DIR/.ssh/authorized_keys"
  chmod 600 "$HOME_DIR/.ssh/authorized_keys"
  grep -Fqx -- "$SSH_PUBLIC_KEY" "$HOME_DIR/.ssh/authorized_keys" || printf '%s\n' "$SSH_PUBLIC_KEY" >> "$HOME_DIR/.ssh/authorized_keys"
fi
run install -d -m 755 /etc/ssh/sshd_config.d
DROPIN=/etc/ssh/sshd_config.d/00-server-hardening.conf
if ((DRY_RUN)); then log "Would write SSH hardening drop-in $DROPIN"; else
  TMP="$(mktemp)"
  cat >"$TMP" <<EOF
# Managed by server-hardening provision.sh
Port $SSH_PORT
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
X11Forwarding no
AllowAgentForwarding no
EOF
  PREVIOUS_DROPIN=""
  if [[ -e "$DROPIN" ]]; then
    PREVIOUS_DROPIN="$DROPIN.bak.$(date +%Y%m%d%H%M%S)"
    cp -a "$DROPIN" "$PREVIOUS_DROPIN"
  fi
  install -m 644 "$TMP" "$DROPIN"; rm -f "$TMP"
  if ! sshd -t; then
    if [[ -n "$PREVIOUS_DROPIN" ]]; then cp -a "$PREVIOUS_DROPIN" "$DROPIN"; else rm -f "$DROPIN"; fi
    die "sshd config invalid; previous drop-in restored (if one existed). No SSH reload was attempted."
  fi
fi
# Open SSH first; then set restrictive defaults and enable UFW.
run ufw allow "$SSH_PORT/tcp"
run ufw default deny incoming
run ufw default allow outgoing
run ufw --force enable
run install -d -m 750 -o root -g adm /var/log/server-hardening
run install -d -m 700 "$BACKUP_DIR"
if ((DRY_RUN)); then log "Would install backup script, daily job and logrotate policy."; else
  HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  install -m 750 "$HERE/backup.sh" /usr/local/sbin/server-hardening-backup.sh
  printf '#!/bin/sh\nexec /usr/local/sbin/server-hardening-backup.sh\n' >/etc/cron.daily/server-hardening-backup
  chmod 750 /etc/cron.daily/server-hardening-backup
  install -m 644 "$HERE/../config/logrotate-server-hardening" /etc/logrotate.d/server-hardening
  logrotate -d /etc/logrotate.d/server-hardening >/dev/null
fi
if ((DRY_RUN)); then
  log "Would enable and reload the installed SSH service and cron scheduler."
elif systemctl list-unit-files | grep -q '^ssh\\.service'; then
  systemctl enable --now ssh
  systemctl reload-or-restart ssh
  systemctl enable --now cron
elif systemctl list-unit-files | grep -q '^sshd\\.service'; then
  systemctl enable --now sshd
  systemctl reload-or-restart sshd
  systemctl enable --now cron
else
  die "No ssh.service or sshd.service unit found."
fi
log "Provisioning complete. Test key login in a second session before closing this one."
