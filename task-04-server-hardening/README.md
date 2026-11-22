# Task 04 — Server Hardening Runbook

A small Debian/Ubuntu server bring-up project for the UpStartInterns Linux Administration capstone.

## Included

- Provisioning script for an administrator account, SSH public-key access, OpenSSH hardening, and UFW firewall.
- Daily compressed backup job for /etc, /home, and /var/www (when present), with configurable retention.
- Logrotate policy for the backup log.
- Operational runbook for verification, backup inspection, restore, SSH lockout, firewall recovery, and rollback.

## Platform

Debian 12/13 or Ubuntu 22.04/24.04 with systemd, Bash 4+, apt, OpenSSH, UFW, tar, gzip, logrotate, and cron. Root access is required.

## Safety warning

Use a disposable VM or a server with provider-console access. The provisioning script changes user membership, SSH settings, firewall policy, cron, and logrotate. Keep your current session open. Verify key-based login in a second session before closing it. Review the scripts before running them on any important host.

## Setup

Copy the example configuration to the system configuration path and edit it:

~~~bash
sudo install -m 600 config/server-hardening.conf.example /etc/server-hardening.conf
sudoedit /etc/server-hardening.conf
~~~

Set a valid administrator username, SSH port, and complete SSH public key. Never place private keys or production secrets in this repository.

Review the dry run:

~~~bash
sudo bash scripts/provision.sh --dry-run
~~~

Apply on a console-accessible test server:

~~~bash
sudo bash scripts/provision.sh
~~~

The script installs packages, creates the administrator if missing, adds it to sudo, installs the public key idempotently, writes an SSH drop-in, validates it with sshd -t, allows the configured SSH port before enabling UFW, and installs the backup job and logrotate policy.

## Verify

~~~bash
sudo sshd -t
sudo sshd -T | grep -E '^(port|permitrootlogin|passwordauthentication|pubkeyauthentication) '
sudo ufw status verbose
sudo systemctl status ssh --no-pager
sudo /usr/local/sbin/server-hardening-backup.sh
sudo ls -lh /var/backups/server-hardening/
sudo logrotate -d /etc/logrotate.d/server-hardening
~~~

Some distributions call the service sshd rather than ssh. Consult RUNBOOK.md for checks and recovery steps.

## Tests

Run static smoke tests on Linux:

~~~bash
bash tests/smoke-test.sh
~~~

These tests check shell syntax and expected input validation. They do not apply firewall or SSH changes. The full provisioning workflow must be tested on an isolated Linux VM before production use.

## Design choices

- UFW provides a straightforward host firewall on Debian/Ubuntu.
- Root SSH login, password authentication, keyboard-interactive authentication, X11 forwarding, and agent forwarding are disabled.
- The configured SSH port is allowed before UFW is enabled.
- SSH settings are placed in a separate early-loading drop-in; the main sshd_config is not overwritten.
- Backups are created to a temporary file, integrity-checked, then renamed into place.
- Backup retention defaults to 14 days; backup log rotation is weekly with 8 archives.

## Known limitations

This is a learning baseline, not a complete production security standard. It does not configure provider firewalls, MFA, intrusion detection, automatic security updates, monitoring, or off-host replication. The backup includes sensitive files under /etc and /home; protect and encrypt off-host copies. A same-disk backup is not disaster recovery. Perform a restore drill on an isolated host.

## Internship task

Task 04 — Capstone: Server Hardening Runbook.
