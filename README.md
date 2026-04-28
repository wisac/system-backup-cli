# Production Restic Backup Automation

A robust, production-grade automated backup solution for Linux laptops using [Restic](https://restic.net/) and Google Cloud Storage (GCS) as the backend.

## Features

- **Reliability:** File locking (`flock`) prevents concurrent execution. Pre-flight network and battery checks prevent running at bad times.
- **Fail-Fast Methodology:** Built with `set -Eeuo pipefail` and custom error trapping.
- **Incremental & Encrypted:** Data is locally encrypted before ever reaching Google Cloud Storage.
- **Cost optimization:** Compatible with GCS Nearline/Coldline lifecycles.
- **Easy Restores:** A dedicated CLI wrapper script (`restore.sh`) makes retrieving entire snapshots or individual files frictionless.

## Prerequisites

- `bash` (Ubuntu compatible)
- `restic`
- A Google Cloud Project with a Service Account explicitly allowed to manage buckets/objects.

## Initial Setup

1. **Clone/Move** this code to a permanent location (e.g. `/home/wilson/DEVELOPMENTS/PROJECTS/backup`).
2. **Create Secrets:**
   ```bash
   sudo mkdir -p /opt/restic-backup
   # Create a secure password file
   sudo touch /opt/restic-backup/.restic_password
   # Add your password inside this file
   sudo chmod 600 /opt/restic-backup/.restic_password
   ```
3. **Configure Environment:**
   ```bash
   cp .env.example .env
   # Edit .env with your specific paths, bucket name, and GCP project
   nano .env
   ```
4. **Customise Inclusions and Exclusions:**
   - **`exclude.txt`**: Review the contents. The defaults cover `node_modules`, standard build artifacts, caches, and temp directories. Modify to suit your development environment.
   - **`include.txt`**: If you have files outside your main `.env` `BACKUP_SOURCE` (e.g. `/etc/nginx` or `/opt`), add them line-by-line here.
5. **Install & Schedule:**
   ```bash
   sudo ./install.sh
   ```
   _We strongly recommend selecting the `Systemd` option. Because laptops sleep, cron jobs scheduled for midnight will be missed. Systemd's `Persistent=true` feature ensures the job runs as soon as you open the laptop the next morning._

## Google Cloud Setup & Cost Optimisation

### IAM Permissions

Create a dedicated Service Account via the GCP Console. Attach a Custom Role with _only_ the following least-privilege permissions:

- `storage.objects.create`
- `storage.objects.delete`
- `storage.objects.get`
- `storage.objects.list`
- `storage.buckets.get`

Download the JSON key and place it at the path defined in your `.env`. Verify its permissions are restricted (`chmod 600`).

### Storage Classes (Nearline vs. Coldline vs. Standard)

- **Standard:** Use if you restore frequently or want the fastest access. Most expensive storage cost, no retrieval penalties.
- **Nearline:** Best for 30-day minimum retention. Slightly cheaper. Good balance for daily backups.
- **Coldline:** **WARNING:** Restic frequently runs metadata checks during `backup` and `prune`. Because Coldline penalizes rapid access and has a 90-day minimum retention charge, _using Coldline as your backend can actually cost MORE than Standard due to Restic metadata operations._
- **Our Recommendation:** Use a **Standard** or **Nearline** bucket. If you wish to archive, use GCS Lifecycle Policies to transition objects to **Archive** storage natively on GCP, rather than having Restic manage it.

## Testing & Verifying

### Manual Run

You can run the script manually, bypassing the schedule:

```bash
./backup.sh
```

### Viewing Logs

If you used **systemd**:

```bash
journalctl -u restic-backup.service -n 50 --no-pager
```

If you used **cron**, check `logs/backup.log` and `logs/cron.log`.

## Restoration Guide

Use the provided `restore.sh` script to recover data safely.

```bash
# Preview what would be restored from the latest snapshot (Dry Run)
./restore.sh --latest /home/wilson/restore_test --dry-run

# Restore the most recent backup entirely
./restore.sh --latest /tmp/full-restore

# List all snapshots
./restore.sh --list

# Restore a specific snapshot directly
./restore.sh --id 88abcdef /tmp/old-restore

# Restore one specific file from the latest snapshot
./restore.sh --file /home/wilson/.bashrc
```

## Security Posture

- Secrets are sourced securely, not leaked into process lists.
- Strict `chmod` usage applies ensuring user isolation.
- Lockfiles prevent destructive concurrency if multiple triggers overlap.
