# Server Hardening Runbook

## 1. Purpose and assumptions

Use this procedure to bring a new Debian/Ubuntu server into service. It assumes console/provider recovery access, an approved administrator account, and a trusted SSH public key. Never remove the only working access path during a remote change.

## 2. Pre-deployment checklist

- [ ] Confirm OS: cat /etc/os-release.
- [ ] Confirm console or provider recovery access.
- [ ] Record hostname, addresses, owner, purpose, and maintenance window.
- [ ] Confirm the intended SSH port is allowed by any cloud/network firewall.
- [ ] Generate an SSH key pair on the administrator workstation; transfer only the public key.
- [ ] Verify the key belongs to the intended administrator.
- [ ] Take an initial provider snapshot if available.
- [ ] Review /etc/server-hardening.conf; replace every example value.

## 3. Provision

1. Copy and edit the example configuration as described in README.md.
2. Review planned operations:

   ~~~bash
   sudo bash scripts/provision.sh --dry-run
   ~~~

3. Run from a console-accessible session:

   ~~~bash
   sudo bash scripts/provision.sh
   ~~~

4. Keep the original session and provider console open.
5. From the provider console, set a password for the administrator so sudo can authenticate:

   ~~~bash
   sudo passwd opsadmin
   ~~~

   Replace the sample username. The provisioning script creates a random, undisclosed initial password hash for a new account; this step sets the password known to the administrator. SSH password authentication remains disabled.
6. From a second terminal, test the configured administrator and port:

   ~~~bash
   ssh -p 22 opsadmin@SERVER_ADDRESS
   sudo -v
   ~~~

   Replace sample values with the configured username, port, and server address. Confirm key-based authentication and sudo access before ending the original session.

## 4. Post-provisioning verification

Run and record:

~~~bash
id opsadmin
sudo sshd -t
sudo sshd -T | grep -E '^(port|permitrootlogin|passwordauthentication|pubkeyauthentication) '
sudo ufw status verbose
sudo systemctl is-enabled ssh || sudo systemctl is-enabled sshd
sudo systemctl is-active ssh || sudo systemctl is-active sshd
sudo systemctl is-enabled cron
sudo systemctl is-active cron
sudo logrotate -d /etc/logrotate.d/server-hardening
sudo /usr/local/sbin/server-hardening-backup.sh
sudo ls -lh /var/backups/server-hardening/
sudo tail -n 20 /var/log/server-hardening/backup.log
~~~

Expected posture:
- Admin account exists and belongs to sudo.
- sshd syntax test passes.
- PermitRootLogin is no.
- PubkeyAuthentication is yes.
- PasswordAuthentication and KbdInteractiveAuthentication are no.
- UFW is active and allows the configured SSH TCP port.
- SSH is enabled and active.
- Logrotate accepts the policy.
- A compressed backup exists and completion is logged.

Check the cloud firewall separately; UFW cannot override provider network ACLs.

## 5. Backup operations

### Run a backup

~~~bash
sudo /usr/local/sbin/server-hardening-backup.sh
~~~

### Check archive integrity and contents

~~~bash
sudo gzip -t /path/to/backup.tar.gz
sudo tar -tzf /path/to/backup.tar.gz | head
~~~

### Restore on an isolated recovery host

Do not extract a full system archive over a live production system as the first response.

1. Build an isolated recovery VM with a compatible OS release.
2. Copy the selected archive to that VM.
3. Inspect the archive using tar -tzf.
4. Extract only the required paths to a staging directory:

   ~~~bash
   sudo mkdir -p /mnt/restore-staging
   sudo tar -xzf backup.tar.gz -C /mnt/restore-staging etc/ssh home
   ~~~

5. Compare staged files and ownership with the recovery host.
6. Restore only the required files, preserving ownership and permissions.
7. Validate restored SSH configuration with sshd -t before reloading SSH.
8. Record the restore actions and verification results.

The archive may contain secrets. Restrict access and encrypt off-host copies.

## 6. Recovery procedures

### SSH lockout or invalid SSH configuration

- Use provider console or out-of-band access. Keep any still-working SSH session open.
- Inspect /etc/ssh/sshd_config.d/00-server-hardening.conf and timestamped .bak files.
- Restore the most recent known-good backup, or temporarily move the managed drop-in out of the include directory.
- Run sshd -t. Reload SSH only if validation passes.
- Confirm both UFW and provider firewall allow the configured port.
- Test a new connection before closing console access.

### Firewall blocks SSH

From console access:

~~~bash
sudo ufw status numbered
sudo ufw allow 22/tcp
sudo ufw reload
~~~

Use the configured SSH port instead of 22. If firewall state is unknown and console recovery is available, sudo ufw disable may temporarily restore access. Reapply reviewed rules before returning the host to service.

### Backup failure

- Inspect /var/log/server-hardening/backup.log.
- Check free space with df -h.
- Check destination permissions and mount availability.
- Check /run/lock/server-hardening-backup.lock. Confirm no backup process is active before removing a stale lock.
- Run the backup manually and verify the archive with gzip -t.

### Accidental configuration change

Restore only the required file to a staging location first. Compare it with the live file, then copy it into place with correct owner and permissions. Validate syntax before reloading the related service.

## 7. Rollback checklist

- [ ] Keep console access until SSH and firewall checks pass.
- [ ] Restore the previous SSH drop-in if the new one is invalid.
- [ ] Validate with sshd -t before reload.
- [ ] Re-open the previous SSH port in UFW and provider firewall if required.
- [ ] Disable UFW only as a temporary console-assisted recovery step.
- [ ] Remove the scheduled job only if necessary: sudo rm -f /etc/cron.daily/server-hardening-backup.
- [ ] Restore previous logrotate policy if required.
- [ ] Record incident time, commands, impact, and final state.

## 8. Operational schedule

| Frequency | Action |
|---|---|
| Daily | Confirm backup job completed and latest archive exists. |
| Weekly | Review SSH authentication logs, firewall status, and log rotation. |
| Monthly | Test archive integrity and perform an isolated restore drill. |
| After changes | Re-run SSH syntax, firewall, and backup checks. |

## 9. Change record

Record date, operator, server identity, configuration revision, test results, backup archive name, and deviations from this runbook.
