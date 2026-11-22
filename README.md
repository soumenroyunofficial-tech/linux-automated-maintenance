# Linux Automated Maintenance

A Bash automation project for routine Linux maintenance. It creates a daily system health report, records timestamped activity, handles command failures, and removes old reports according to a configurable retention period.

## Project goals

- Run unattended from cron.
- Record actions and errors with timestamps.
- Generate a report containing uptime, disk usage, memory usage, hostname, and kernel information.
- Keep generated data outside the Git repository.
- Be safe to run repeatedly: the report for the current date is replaced atomically, logs are appended, and old reports are cleaned up.
- Avoid changing system configuration or requiring root privileges.

## Requirements

- Linux with Bash 4 or newer.
- Standard utilities: `date`, `hostname`, `uname`, `uptime`, `df`, `free`, `find`, `mktemp`, and common file utilities.
- `cron` for optional scheduled execution.

The script is designed for common Debian/Ubuntu-style Linux environments. It does not install packages or make system-wide changes.

## Repository layout

```text
linux-automated-maintenance/
├── maintenance.sh
├── README.md
└── .gitignore
```

## Installation

```bash
git clone https://github.com/soumenroyunofficial-tech/linux-automated-maintenance.git
cd linux-automated-maintenance
```

Run the script with Bash:

```bash
bash maintenance.sh
```

You do not need `sudo`. The script uses the current user's state directory by default.

## Output locations

By default, generated files are stored under:

```text
~/.local/state/linux-maintenance/
├── logs/
│   └── maintenance.log
├── reports/
│   └── system-report-YYYY-MM-DD.txt
└── maintenance.lock  (temporary while a run is active)
```

- `logs/maintenance.log`: timestamped INFO and ERROR messages. Each run appends to this file.
- `reports/system-report-YYYY-MM-DD.txt`: one report per calendar day. Running the script again on the same day safely replaces that day's report.
- `maintenance.lock`: a temporary lock directory used to prevent overlapping runs. It is removed when the script exits normally.

Generated files are created with restrictive permissions for the current user.

## Configuration

### Change report retention

The default retention setting is 7 days. Set `RETENTION_DAYS` to an integer from 1 to 365:

```bash
RETENTION_DAYS=14 bash maintenance.sh
```

Cleanup uses GNU `find`'s `-mtime` age test, which is based on completed 24-hour periods.

### Change the data directory

```bash
MAINTENANCE_DIR="$HOME/maintenance-data" bash maintenance.sh
```

This is useful for testing without using the default data directory.

## Schedule with cron

1. Find the absolute path to the script:

   ```bash
   realpath maintenance.sh
   ```

2. Open your user's crontab:

   ```bash
   crontab -e
   ```

3. Add a schedule such as this to run every day at 9:00 AM:

   ```cron
   0 9 * * * /usr/bin/env bash /absolute/path/to/linux-automated-maintenance/maintenance.sh
   ```

   Replace the example path with the exact path returned by `realpath`.

4. Save and exit, then verify the entry:

   ```bash
   crontab -l
   ```

Cron uses the machine's configured local time zone. The job runs with the permissions and environment of the user whose crontab contains the entry.

## Verification and repeat-run test

Run these commands from the repository directory:

```bash
bash -n maintenance.sh
bash maintenance.sh
bash maintenance.sh
```

Inspect the results:

```bash
cat "$HOME/.local/state/linux-maintenance/logs/maintenance.log"
ls -l "$HOME/.local/state/linux-maintenance/reports/"
cat "$HOME/.local/state/linux-maintenance/reports/system-report-$(date +%Y-%m-%d).txt"
```

To test with a separate temporary data directory:

```bash
TEST_DIR="$(mktemp -d)"
MAINTENANCE_DIR="$TEST_DIR" bash maintenance.sh
MAINTENANCE_DIR="$TEST_DIR" bash maintenance.sh
find "$TEST_DIR" -maxdepth 3 -type f -print
cat "$TEST_DIR/logs/maintenance.log"
```

Remove the temporary test directory after testing:

```bash
rm -rf -- "$TEST_DIR"
```

### What to check

- Both runs should complete successfully.
- The log should contain timestamps and a successful completion entry for each run.
- Two same-day runs should leave one report for that date, not duplicate reports.
- The report should contain uptime, disk, and memory sections.
- The temporary lock directory should not remain after a completed run.

Test input validation:

```bash
RETENTION_DAYS=0 bash maintenance.sh
```

The script should stop with an error rather than proceeding with maintenance.

## Safety notes

- The script does not delete user documents, application data, package caches, or system logs.
- Cleanup is restricted to date-named report files inside the dedicated reports directory.
- It does not require root access.
- A lock directory prevents simultaneous runs from operating on the same report and log locations.
- Review the script before scheduling it on a production machine.

## Internship task

**Task 03 – Automation Script**

This repository demonstrates an unattended Linux maintenance job with error handling, timestamped logging, repeat-run safety, and scheduling documentation.
