# Restic + Backblaze B2 Personal PC Backup

Automated, encrypted backup of critical development files from a Linux workstation to Backblaze B2 using [Restic](https://restic.net/).

The primary goal of this project is **disaster recovery**: if the workstation is lost, formatted, or files are accidentally deleted, critical development credentials and configuration can be restored without manually rebuilding the backup system.

---

## What This Protects

By default, the backup system protects:

* `~/.ssh/`

  * SSH private keys
  * SSH public keys
  * SSH configuration
  * `known_hosts`
  * deployment keys
  * other SSH-related files
* `.env*` files inside configured workspaces
* Any additional files or directories explicitly added to the backup configuration

The backup repository is encrypted using Restic before data is uploaded to Backblaze B2.

---

## Architecture

```text
                         Linux Workstation
                                │
                                │
                    ┌───────────┴───────────┐
                    │                       │
                  ~/.ssh                 Workspaces
                    │                       │
                    │                  .env* files
                    │                       │
                    └───────────┬───────────┘
                                │
                                ▼
                       backup-secrets
                                │
                                ▼
                             Restic
                                │
                         AES-256 encryption
                                │
                                ▼
                         Backblaze B2
                                │
                                ▼
                      Encrypted Repository
```

The system is intentionally designed so that **Backblaze does not receive your files in plaintext**.

---

# Features

* 🔐 Encrypted backups using Restic
* ☁️ Backblaze B2 object storage
* 🔑 Automatic backup of `~/.ssh/`
* 🔎 Automatic discovery of `.env*` files
* 📁 User-configurable additional backup paths
* ⏰ Automatic nightly backups
* ♻️ Snapshot retention
* 🛡️ Old snapshots are preserved when a backup fails
* 🔄 Idempotent installation
* 🧰 Easy setup on a freshly installed PC
* 📋 Systemd service and timer
* 🔍 Repository integrity checking
* 🚫 No secrets stored in Git

---

# Requirements

The installer currently targets Linux systems using:

* Bash 4+
* systemd
* `apt`
* sudo access
* An internet connection
* A Backblaze B2 bucket
* A Backblaze B2 application key

The system is designed primarily for Debian/Ubuntu-based Linux distributions.

---

# Backblaze B2 Setup

Before running the installer, create a bucket in Backblaze B2.

You will need:

```text
B2 Key ID
B2 Application Key
B2 Bucket Name
B2 S3 Endpoint
```

The recommended application key should be restricted to the backup bucket rather than using an account-wide master credential.

For example:

```text
Bucket:
personal-pc-backup

Endpoint:
https://s3.eu-central-003.backblazeb2.com
```

The exact endpoint depends on the B2 bucket's region.

---

# Installation

Clone this repository:

```bash
git clone <YOUR_REPOSITORY_URL>
cd restic-backup
```

Make the installer executable:

```bash
chmod +x install.sh
```

Run:

```bash
./install.sh
```

Alternatively:

```bash
bash install.sh
```

---

# Installation Process

The installer performs the following steps.

## 1. Install Restic

If Restic is not already installed, the installer installs it using `apt`.

If Restic is already installed, the existing installation is preserved.

---

## 2. Ask for Backblaze Credentials

The installer interactively asks for:

```text
B2 Key ID:
B2 Application Key:
B2 Bucket Name:
B2 S3 Endpoint:
```

The application key is entered without being displayed on screen.

---

## 3. Create Restic Encryption Password

The installer asks for a separate Restic repository password.

This password is extremely important.

It is different from the Backblaze credentials.

Restic uses this password to encrypt the repository.

### IMPORTANT

If you lose the Restic repository password:

**the encrypted backup cannot be restored.**

Keep a secure copy of the password somewhere outside the computer being backed up.

---

# Local Configuration

The installer creates:

```text
~/.config/restic/
├── env
├── password
└── include
```

Permissions are restricted:

```text
~/.config/restic/          700
~/.config/restic/env       600
~/.config/restic/password  600
~/.config/restic/include   600
```

---

# `env`

The `env` file contains the Backblaze credentials and Restic repository configuration.

Example:

```bash
export AWS_ACCESS_KEY_ID='...'
export AWS_SECRET_ACCESS_KEY='...'
export RESTIC_REPOSITORY='s3:https://s3.eu-central-003.backblazeb2.com/personal-pc-backup'
export RESTIC_PASSWORD_FILE='/home/user/.config/restic/password'
```

This file contains secrets.

**Never commit it to Git.**

---

# `password`

The Restic encryption password is stored separately:

```text
~/.config/restic/password
```

It is protected with:

```text
chmod 600
```

This file must also never be committed to Git.

---

# Adding More Files and Folders

The most important configuration file is:

```text
~/.config/restic/include
```

This file is intentionally persistent and user-editable.

You can add additional files or directories whenever you want.

Edit it with:

```bash
nano ~/.config/restic/include
```

---

## Example

```text
# Important documents
~/Documents/important

# Application configuration
~/.config/my-application/

# AWS configuration
~/.aws/

# Important project configuration
~/Projects/my-project/docker-compose.yml
```

Use one path per line.

Comments beginning with `#` are ignored.

Empty lines are ignored.

---

## Adding an Entire Directory

For example:

```text
~/Documents/important
```

will back up everything under that directory.

Likewise:

```text
~/.config/my-application/
```

backs up the entire directory.

---

# Automatic `.env` Discovery

The backup script automatically searches configured workspaces for `.env*` files.

Currently configured workspaces are:

```python
WORKSPACES = [
    HOME / "Projects",
    HOME / "AI-Workspace",
]
```

This means files such as:

```text
.env
.env.local
.env.production
.env.development
.env.test
```

will automatically be discovered.

You do not need to manually add every `.env` file to `include`.

---

# Adding Another Workspace

There are two ways to do this.

## Option 1 — Back Up the Entire Workspace

Add it to:

```text
~/.config/restic/include
```

Example:

```text
~/Work
```

This backs up the entire directory.

---

## Option 2 — Automatically Discover `.env*` Files

Edit:

```text
backup-secrets.py
```

and add another workspace:

```python
WORKSPACES = [
    HOME / "Projects",
    HOME / "AI-Workspace",
    HOME / "Work",
]
```

The nightly backup will then automatically discover `.env*` files inside that workspace.

---

# SSH Backup

The entire directory:

```text
~/.ssh/
```

is automatically included.

This includes files such as:

```text
~/.ssh/id_ed25519
~/.ssh/id_rsa
~/.ssh/config
~/.ssh/known_hosts
```

as well as deployment-specific keys.

You do not need to add `~/.ssh` to `include`.

---

# Backup Schedule

Backups run automatically every night.

The systemd timer is configured for:

```text
02:00
```

with a randomized delay of up to:

```text
15 minutes
```

This means the backup normally runs somewhere around:

```text
02:00 - 02:15
```

The random delay prevents every machine using the same configuration from hitting the storage service at exactly the same time.

---

# Missed Backups

The timer uses:

```ini
Persistent=true
```

If the computer is powered off when the scheduled backup occurs, systemd can run the missed job when the timer becomes active again.

---

# Backup Flow

Every backup follows this process:

```text
Nightly timer
      │
      ▼
backup-secrets
      │
      ▼
Restic backup
      │
      ├───────────────┐
      │               │
    FAILED          SUCCESS
      │               │
      ▼               ▼
    STOP        Retention cleanup
      │               │
      │               ▼
      │          Remove old snapshots
      │
      ▼
Old backups preserved
```

This is intentional.

## Failed backups do NOT trigger cleanup.

If the new backup fails, existing snapshots remain untouched.

This protects against a situation where:

1. The backup fails.
2. Cleanup runs anyway.
3. Old snapshots are deleted.
4. There is no valid backup left.

---

# Snapshot Retention

The system keeps:

```text
7 daily snapshots
4 weekly snapshots
6 monthly snapshots
```

The equivalent Restic policy is:

```bash
restic forget \
    --keep-daily 7 \
    --keep-weekly 4 \
    --keep-monthly 6 \
    --prune
```

Restic uses deduplication, so keeping multiple snapshots does not mean storing complete copies of all files every time.

---

# Checking the Timer

Check the timer:

```bash
systemctl --user status restic-backup.timer
```

View the next scheduled execution:

```bash
systemctl --user list-timers restic-backup.timer
```

You should see something similar to:

```text
NEXT                         LEFT
Tue 2026-09-08 02:xx         ...
```

---

# Manually Run a Backup

You can trigger a backup immediately:

```bash
systemctl --user start restic-backup.service
```

Or run the backup script directly:

```bash
~/.local/bin/backup-secrets
```

The systemd method is preferred because it runs the same service used by the nightly timer.

---

# Check Backup Logs

View the latest backup logs:

```bash
journalctl --user -u restic-backup.service --no-pager
```

Follow the logs live:

```bash
journalctl --user -u restic-backup.service -f
```

---

# View Restic Snapshots

Load the Restic configuration:

```bash
source ~/.config/restic/env
```

Then:

```bash
restic snapshots
```

Example:

```text
ID        Time                 Host        Tags
-----------------------------------------------------
a1b2c3    2026-09-07 02:08     workstation
d4e5f6    2026-09-06 02:11     workstation
```

Each snapshot represents a recoverable state of the backed-up files.

---

# Verify the Repository

Run:

```bash
source ~/.config/restic/env
restic check
```

This checks the repository for structural and integrity problems.

For a deeper verification, Restic also supports:

```bash
restic check --read-data
```

The latter reads repository data and can take considerably longer.

---

# Listing Files in a Backup

To inspect the latest snapshot:

```bash
source ~/.config/restic/env
restic ls latest
```

For example:

```bash
restic ls latest | less
```

You should see paths such as:

```text
home/user/.ssh/
home/user/.ssh/config
home/user/.ssh/github
home/user/.ssh/gitlab
```

---

# Restoring Files

If a file is accidentally deleted, first find the appropriate snapshot:

```bash
source ~/.config/restic/env
restic snapshots
```

Then restore the snapshot to a temporary directory:

```bash
mkdir -p ~/restic-restore

restic restore <SNAPSHOT_ID> \
    --target ~/restic-restore
```

For example:

```bash
restic restore latest \
    --target ~/restic-restore
```

The restored filesystem will appear underneath:

```text
~/restic-restore/
```

Do not immediately overwrite your existing files.

Inspect the restored files first.

---

# Restoring SSH Keys

After restoring:

```bash
~/restic-restore/home/<username>/.ssh/
```

inspect the contents.

Once confirmed, SSH permissions should be restored appropriately.

For example:

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/<private-key>
chmod 644 ~/.ssh/<public-key>
```

Be careful when restoring private keys.

---

# Disaster Recovery — New PC

This is the primary purpose of this project.

If the original PC is lost, formatted, or otherwise unusable:

```text
New Linux installation
        │
        ▼
Install Git
        │
        ▼
Clone this repository
        │
        ▼
Run install.sh
        │
        ▼
Enter B2 credentials
        │
        ▼
Enter Restic password
        │
        ▼
Connect to existing repository
        │
        ▼
List snapshots
        │
        ▼
Restore critical files
```

---

# Important: Existing Repository

When setting up a replacement machine, the installer should detect the existing Restic repository.

It must **not initialize a new repository over the existing backup**.

The existing repository contains the historical snapshots needed for recovery.

After connecting:

```bash
source ~/.config/restic/env
restic snapshots
```

You should see the previous backups.

---

# Recovering Your Development Environment

A typical recovery might look like:

```bash
restic snapshots
```

Then:

```bash
mkdir -p ~/restic-restore
```

Then:

```bash
restic restore latest \
    --target ~/restic-restore
```

After verifying the restored data, copy the required files back into place.

For example:

```text
~/.ssh/
.env files
~/.aws/
application configuration
important documents
```

---

# Security Model

There are three separate security components.

## 1. Backblaze Credentials

Used to access the B2 bucket.

```text
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
```

---

## 2. Restic Repository Password

Used to decrypt the Restic repository.

```text
~/.config/restic/password
```

---

## 3. Restic Encryption

Files are encrypted by Restic before being uploaded to B2.

Therefore:

```text
Your files
    ↓
Restic encryption
    ↓
Encrypted repository
    ↓
Backblaze B2
```

Backblaze does not need to understand the contents of the files.

---

# Git Security

This repository contains the installation code only.

It must never contain:

```text
B2 credentials
Restic passwords
.env files
SSH private keys
private certificates
API keys
tokens
```

The following files should remain local:

```text
~/.config/restic/env
~/.config/restic/password
~/.config/restic/include
```

The repository's `.gitignore` protects against accidentally committing common secret files.

---

# Never Do This

Do not commit:

```bash
git add ~/.config/restic/env
```

Do not commit:

```bash
git add ~/.config/restic/password
```

Do not put credentials directly into:

```text
install.sh
backup-secrets.py
README.md
```

Do not paste private SSH keys into GitHub.

---

# Configuration Reference

## Backup Script

Installed to:

```text
~/.local/bin/backup-secrets
```

## Restic Configuration

```text
~/.config/restic/env
```

## Restic Password

```text
~/.config/restic/password
```

## Additional Backup Paths

```text
~/.config/restic/include
```

## Systemd Service

```text
~/.config/systemd/user/restic-backup.service
```

## Systemd Timer

```text
~/.config/systemd/user/restic-backup.timer
```

---

# Useful Commands

## Check timer

```bash
systemctl --user status restic-backup.timer
```

## See next backup

```bash
systemctl --user list-timers restic-backup.timer
```

## Run backup manually

```bash
systemctl --user start restic-backup.service
```

## Check service status

```bash
systemctl --user status restic-backup.service
```

## View logs

```bash
journalctl --user -u restic-backup.service --no-pager
```

## View snapshots

```bash
source ~/.config/restic/env
restic snapshots
```

## Check repository

```bash
source ~/.config/restic/env
restic check
```

## List latest backup

```bash
source ~/.config/restic/env
restic ls latest
```

---

# Adding More Backup Locations

Edit:

```bash
nano ~/.config/restic/include
```

Add:

```text
~/Documents
~/Important
~/.aws/
~/.config/my-app/
```

Save the file.

That's it.

The next nightly backup will automatically include the new paths.

No reinstall is required.

No systemd configuration change is required.

No script modification is required.

---

# Removing a Backup Location

Remove the corresponding line from:

```bash
~/.config/restic/include
```

This prevents future snapshots from backing up that location.

**Important:** removing a path does not immediately delete it from existing snapshots.

Previous snapshots can still contain the data until Restic's retention policy eventually removes those snapshots.

---

# Troubleshooting

## Timer is not running

Check:

```bash
systemctl --user status restic-backup.timer
```

Then:

```bash
systemctl --user daemon-reload
systemctl --user restart restic-backup.timer
```

---

## Backup failed

Check:

```bash
journalctl --user -u restic-backup.service --no-pager
```

Then manually test:

```bash
~/.local/bin/backup-secrets
```

---

## Restic cannot access the repository

Check that the environment exists:

```bash
ls -l ~/.config/restic/
```

Expected:

```text
env
password
include
```

Then:

```bash
source ~/.config/restic/env
restic snapshots
```

---

## `.env` files are not being backed up

Check that the project is inside one of the configured workspaces:

```python
WORKSPACES = [
    HOME / "Projects",
    HOME / "AI-Workspace",
]
```

Alternatively, add the project directory directly to:

```text
~/.config/restic/include
```

---

# Recommended Operational Practice

The backup system protects against accidental deletion, but a backup is only useful if it can actually be restored.

Periodically perform a restore test.

For example:

```bash
mkdir -p ~/restic-test

source ~/.config/restic/env

restic restore latest \
    --target ~/restic-test
```

Verify that important files exist:

```bash
find ~/restic-test -type f | head
```

Then remove the test directory:

```bash
rm -rf ~/restic-test
```

A restore test confirms that:

```text
Backup exists
      +
Repository is accessible
      +
Password works
      +
Files can actually be restored
```

---

# Backup Philosophy

This system intentionally follows a few principles.

### 1. Back up critical files automatically

Important credentials should not depend on remembering to run a command.

### 2. Keep historical snapshots

A backup should protect against accidental deletion, not just hardware failure.

### 3. Never prune after a failed backup

Old snapshots are more valuable than aggressive storage cleanup.

### 4. Keep configuration separate from code

The GitHub repository contains installation logic.

The machine contains credentials and backup configuration.

### 5. Make recovery reproducible

A replacement computer should be able to rebuild the backup system from this repository.

---

# Repository Structure

Recommended repository structure:

```text
restic-backup/
├── install.sh
├── backup-secrets.py
├── README.md
└── .gitignore
```

The repository itself contains no personal backup data.

---

# License

Choose an appropriate license for your repository.

For a personal/private backup installer, you may also choose to keep the repository private.

---

# Final Recovery Checklist

If your PC suddenly becomes unusable:

* [ ] Install Linux
* [ ] Install Git
* [ ] Clone this repository
* [ ] Run `install.sh`
* [ ] Enter Backblaze B2 credentials
* [ ] Enter Restic repository password
* [ ] Confirm the existing repository is detected
* [ ] Run `restic snapshots`
* [ ] Select the appropriate snapshot
* [ ] Restore to a temporary directory
* [ ] Verify restored files
* [ ] Restore `~/.ssh/`
* [ ] Restore `.env` files
* [ ] Restore other important configuration
* [ ] Test SSH connections
* [ ] Test critical applications
* [ ] Verify the nightly timer is active

---

## The Goal

The entire backup system should ultimately be recoverable with:

```bash
git clone <YOUR_REPOSITORY_URL>
cd restic-backup
bash install.sh
```

After that, the machine should automatically protect your critical development files every night.

**Your code can live in Git. Your secrets and critical configuration can live in encrypted Restic snapshots. Your GitHub repository contains the machinery required to rebuild the system.**
