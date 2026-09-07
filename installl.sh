#!/usr/bin/env bash

# Restic + Backblaze B2 Backup Installer
#
# This installer sets up an encrypted Restic backup system using
# Backblaze B2 as the remote storage provider.
#
# The backup system protects:
#
#   - ~/.ssh/
#   - .env* files inside configured workspaces
#   - Any files/directories listed in:
#       ~/.config/restic/include
#
# The include file is intentionally persistent and user-editable.
# Add new files or directories there whenever you want them included
# in future backups.
#
# Credentials are NEVER stored in this repository.
#
# Local configuration:
#
#   ~/.config/restic/
#   ├── env
#   ├── password
#   └── include
#
# Automation:
#
#   systemd user timer
#       ↓
#   nightly backup
#       ↓
#   successful backup
#       ↓
#   retention cleanup
#
# Retention:
#
#   7 daily
#   4 weekly
#   6 monthly

set -Eeuo pipefail

readonly RESTIC_CONFIG_DIR="${HOME}/.config/restic"
readonly RESTIC_ENV_FILE="${RESTIC_CONFIG_DIR}/env"
readonly RESTIC_PASSWORD_FILE="${RESTIC_CONFIG_DIR}/password"
readonly RESTIC_INCLUDE_FILE="${RESTIC_CONFIG_DIR}/include"

readonly BIN_DIR="${HOME}/.local/bin"
readonly SYSTEMD_USER_DIR="${HOME}/.config/systemd/user"

readonly BACKUP_SCRIPT="${BIN_DIR}/backup-secrets"
readonly SERVICE_FILE="${SYSTEMD_USER_DIR}/restic-backup.service"
readonly TIMER_FILE="${SYSTEMD_USER_DIR}/restic-backup.timer"

readonly RETENTION_DAILY=7
readonly RETENTION_WEEKLY=4
readonly RETENTION_MONTHLY=6

readonly DEFAULT_B2_ENDPOINT="https://s3.eu-central-003.backblazeb2.com"


# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

log() {
    printf '\n[+] %s\n' "$1"
}

warn() {
    printf '\n[!] %s\n' "$1" >&2
}

error() {
    printf '\n[ERROR] %s\n' "$1" >&2
    exit 1
}


# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

cleanup() {
    unset B2_KEY_ID || true
    unset B2_APPLICATION_KEY || true
    unset RESTIC_PASSWORD || true
    unset RESTIC_PASSWORD_CONFIRM || true
}

trap cleanup EXIT


# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

require_linux() {
    if [[ "$(uname -s)" != "Linux" ]]; then
        error "This installer currently supports Linux only."
    fi
}


require_bash() {
    if ((BASH_VERSINFO[0] < 4)); then
        error "Bash 4 or newer is required."
    fi
}


# ---------------------------------------------------------------------------
# Dependencies
# ---------------------------------------------------------------------------

install_restic() {
    if command -v restic >/dev/null 2>&1; then
        log "Restic is already installed."
        restic version
        return
    fi

    log "Installing Restic..."

    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update
        sudo apt-get install -y restic
    else
        error "apt-get was not found. Install Restic manually and run this installer again."
    fi

    command -v restic >/dev/null 2>&1 || \
        error "Restic installation failed."

    restic version
}


# ---------------------------------------------------------------------------
# Directory setup
# ---------------------------------------------------------------------------

create_directories() {
    log "Creating configuration directories..."

    mkdir -p \
        "$RESTIC_CONFIG_DIR" \
        "$BIN_DIR" \
        "$SYSTEMD_USER_DIR"

    chmod 700 "$RESTIC_CONFIG_DIR"

    # IMPORTANT:
    # Do not overwrite the include file if it already exists.
    if [[ ! -f "$RESTIC_INCLUDE_FILE" ]]; then
        cat > "$RESTIC_INCLUDE_FILE" <<'EOF'
# Restic additional backup paths
#
# Add one file or directory per line.
#
# Examples:
#
# ~/Documents/important
# ~/Projects/project-a/config.json
# ~/.config/my-application/
#
# Paths beginning with "~" are supported.
#
# These paths are added to the backup in addition to:
#
#   ~/.ssh/
#   .env* files discovered in configured workspaces

EOF

        chmod 600 "$RESTIC_INCLUDE_FILE"

        log "Created backup include configuration."
    else
        chmod 600 "$RESTIC_INCLUDE_FILE"
        log "Existing backup include configuration preserved."
    fi
}


# ---------------------------------------------------------------------------
# Credentials
# ---------------------------------------------------------------------------

collect_credentials() {
    printf '\n'
    printf '%s\n' "=========================================="
    printf '%s\n' " Backblaze B2 Configuration"
    printf '%s\n' "=========================================="
    printf '\n'

    read -r -p "B2 Key ID: " B2_KEY_ID

    [[ -n "$B2_KEY_ID" ]] || \
        error "B2 Key ID cannot be empty."

    printf "B2 Application Key: "
    read -r -s B2_APPLICATION_KEY
    printf '\n'

    [[ -n "$B2_APPLICATION_KEY" ]] || \
        error "B2 Application Key cannot be empty."

    read -r -p "B2 Bucket Name: " B2_BUCKET

    [[ -n "$B2_BUCKET" ]] || \
        error "B2 bucket name cannot be empty."

    read -r \
        -p "B2 S3 Endpoint [${DEFAULT_B2_ENDPOINT}]: " \
        B2_ENDPOINT

    B2_ENDPOINT="${B2_ENDPOINT:-$DEFAULT_B2_ENDPOINT}"

    printf '\n'
    printf '%s\n' "=========================================="
    printf '%s\n' " Restic Encryption Password"
    printf '%s\n' "=========================================="
    printf '\n'

    printf '%s\n' \
        "This password encrypts your Restic repository."

    printf '%s\n' \
        "It is NOT your Backblaze password."

    printf '%s\n' \
        "If you lose this password, your encrypted backup cannot be restored."

    printf '\n'

    while true; do
        printf "Restic Password: "
        read -r -s RESTIC_PASSWORD
        printf '\n'

        [[ -n "$RESTIC_PASSWORD" ]] || {
            warn "Restic password cannot be empty."
            continue
        }

        printf "Confirm Restic Password: "
        read -r -s RESTIC_PASSWORD_CONFIRM
        printf '\n'

        if [[ "$RESTIC_PASSWORD" != "$RESTIC_PASSWORD_CONFIRM" ]]; then
            warn "Passwords do not match. Try again."
            continue
        fi

        break
    done

    export B2_KEY_ID
    export B2_APPLICATION_KEY
    export B2_BUCKET
    export B2_ENDPOINT
    export RESTIC_PASSWORD
}


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

write_environment() {
    log "Writing Restic configuration..."

    cat > "$RESTIC_ENV_FILE" <<EOF
# Restic + Backblaze B2 configuration.
#
# WARNING:
# This file contains credentials.
# Never commit this file to Git.

export AWS_ACCESS_KEY_ID='${B2_KEY_ID}'
export AWS_SECRET_ACCESS_KEY='${B2_APPLICATION_KEY}'
export RESTIC_REPOSITORY='s3:${B2_ENDPOINT}/${B2_BUCKET}'
export RESTIC_PASSWORD_FILE='${RESTIC_PASSWORD_FILE}'
EOF

    chmod 600 "$RESTIC_ENV_FILE"

    printf '%s\n' "$RESTIC_PASSWORD" > "$RESTIC_PASSWORD_FILE"

    chmod 600 "$RESTIC_PASSWORD_FILE"
}


# ---------------------------------------------------------------------------
# Backup script
# ---------------------------------------------------------------------------

write_backup_script() {
    log "Installing backup script..."

    cat > "$BACKUP_SCRIPT" <<'PYTHON'
#!/usr/bin/python3
"""
Critical-file backup using Restic.

Automatically backs up:

    1. ~/.ssh/
    2. .env* files found in configured workspaces
    3. Additional paths from:
       ~/.config/restic/include

The include file is persistent and user-editable.

Add paths like:

    ~/Documents/important
    ~/Projects/project-a/config.json
    ~/.config/my-application/

The Restic repository configuration is loaded from:

    ~/.config/restic/env

The repository password is stored in:

    ~/.config/restic/password

No credentials are hard-coded into this script.
"""

from pathlib import Path
import os
import subprocess
import sys


HOME = Path.home()

RESTIC_ENV = HOME / ".config/restic/env"
INCLUDE_FILE = HOME / ".config/restic/include"
SSH_DIRECTORY = HOME / ".ssh"

# Add or remove workspace locations here if needed.
#
# These are used only to discover .env* files.
WORKSPACES = [
    HOME / "Projects",
    HOME / "AI-Workspace",
]


def load_restic_environment() -> dict[str, str]:
    """Load Restic environment variables from the protected env file."""
    if not RESTIC_ENV.exists():
        raise FileNotFoundError(
            f"Missing Restic configuration: {RESTIC_ENV}"
        )

    command = [
        "bash",
        "-c",
        f"source '{RESTIC_ENV}' && env",
    ]

    result = subprocess.run(
        command,
        capture_output=True,
        text=True,
        check=True,
    )

    environment = os.environ.copy()

    allowed = {
        "AWS_ACCESS_KEY_ID",
        "AWS_SECRET_ACCESS_KEY",
        "RESTIC_REPOSITORY",
        "RESTIC_PASSWORD_FILE",
    }

    for line in result.stdout.splitlines():
        if "=" not in line:
            continue

        key, value = line.split("=", 1)

        if key in allowed:
            environment[key] = value

    return environment


def discover_env_files() -> list[Path]:
    """Discover .env* files inside configured workspaces."""
    files: set[Path] = set()

    for workspace in WORKSPACES:
        if not workspace.exists():
            continue

        for path in workspace.rglob(".env*"):
            if path.is_file() and not path.is_symlink():
                files.add(path)

    return sorted(files)


def load_additional_paths() -> list[Path]:
    """
    Load additional backup paths from the persistent include file.

    One path is accepted per line. Empty lines and comments are ignored.
    """
    if not INCLUDE_FILE.exists():
        return []

    paths = []

    for line in INCLUDE_FILE.read_text().splitlines():
        line = line.strip()

        if not line or line.startswith("#"):
            continue

        path = Path(line).expanduser()

        if path.exists():
            paths.append(path)
        else:
            print(
                f"Warning: backup path does not exist: {path}",
                file=sys.stderr,
            )

    return paths


def main() -> int:
    """Discover critical files and execute the Restic backup."""
    try:
        environment = load_restic_environment()

        paths: list[Path] = []

        # Always protect SSH.
        if SSH_DIRECTORY.exists():
            paths.append(SSH_DIRECTORY)

        # Automatically discover .env* files.
        paths.extend(discover_env_files())

        # Add user-selected files/directories.
        paths.extend(load_additional_paths())

        # Remove duplicate paths.
        unique_paths = list(dict.fromkeys(paths))

        if not unique_paths:
            print("Nothing to back up.")
            return 0

        print("Files/directories selected for backup:")

        for path in unique_paths:
            print(f"  {path}")

        command = [
            "restic",
            "backup",
            *[str(path) for path in unique_paths],
            "--verbose",
        ]

        result = subprocess.run(
            command,
            env=environment,
        )

        if result.returncode == 0:
            print("Backup completed successfully.")
        else:
            print(
                f"Backup failed with exit code {result.returncode}.",
                file=sys.stderr,
            )

        return result.returncode

    except Exception as exc:
        print(f"Backup failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
PYTHON

    chmod 700 "$BACKUP_SCRIPT"
}


# ---------------------------------------------------------------------------
# Repository initialization
# ---------------------------------------------------------------------------

initialize_repository() {
    log "Checking Restic repository..."

    # shellcheck disable=SC1090
    source "$RESTIC_ENV_FILE"

    if restic snapshots >/dev/null 2>&1; then
        log "Existing Restic repository detected."
        log "Existing repository will be preserved."
        return
    fi

    log "Initializing encrypted Restic repository..."

    restic init

    log "Restic repository initialized successfully."
}


# ---------------------------------------------------------------------------
# Systemd service
# ---------------------------------------------------------------------------

write_systemd_service() {
    log "Creating systemd backup service..."

    cat > "$SERVICE_FILE" <<'EOF'
[Unit]
Description=Backup critical files to Backblaze B2 using Restic
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot

# The backup script returns a non-zero status if the backup fails.
ExecStart=%h/.local/bin/backup-secrets

# This command only runs when ExecStart succeeds.
# If the backup fails, old snapshots are preserved.
ExecStartPost=/bin/bash -c 'source %h/.config/restic/env && /usr/bin/restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune'
EOF
}


# ---------------------------------------------------------------------------
# Systemd timer
# ---------------------------------------------------------------------------

write_systemd_timer() {
    log "Creating nightly systemd timer..."

    cat > "$TIMER_FILE" <<'EOF'
[Unit]
Description=Run Restic backup every night

[Timer]
OnCalendar=*-*-* 02:00:00
Persistent=true
RandomizedDelaySec=15m
Unit=restic-backup.service

[Install]
WantedBy=timers.target
EOF
}


# ---------------------------------------------------------------------------
# Enable systemd
# ---------------------------------------------------------------------------

enable_systemd() {
    log "Enabling systemd timer..."

    systemctl --user daemon-reload

    systemctl --user enable --now restic-backup.timer

    # Allows the user timer to operate across login sessions/reboots.
    if command -v loginctl >/dev/null 2>&1; then
        loginctl enable-linger "$USER" >/dev/null 2>&1 || \
            warn "Could not enable systemd user lingering."
    fi

    log "Timer status:"
    systemctl --user status restic-backup.timer --no-pager
}


# ---------------------------------------------------------------------------
# Initial backup
# ---------------------------------------------------------------------------

run_initial_backup() {
    log "Running initial backup..."

    if ! "$BACKUP_SCRIPT"; then
        error "Initial backup failed."
    fi

    log "Initial backup completed successfully."
}


# ---------------------------------------------------------------------------
# Verification
# ---------------------------------------------------------------------------

verify_backup() {
    log "Verifying Restic snapshots..."

    # shellcheck disable=SC1090
    source "$RESTIC_ENV_FILE"

    restic snapshots

    log "Checking repository integrity..."

    restic check

    log "Repository verification completed."
}


# ---------------------------------------------------------------------------
# Final output
# ---------------------------------------------------------------------------

print_summary() {
    printf '\n'
    printf '%s\n' "=========================================="
    printf '%s\n' " Backup Setup Complete"
    printf '%s\n' "=========================================="
    printf '\n'

    printf '%s\n' "Backup schedule:"
    printf '  Every night around 02:00\n'

    printf '\n'

    printf '%s\n' "Retention:"
    printf '  %s daily snapshots\n' "$RETENTION_DAILY"
    printf '  %s weekly snapshots\n' "$RETENTION_WEEKLY"
    printf '  %s monthly snapshots\n' "$RETENTION_MONTHLY"

    printf '\n'

    printf '%s\n' "Automatically protected:"
    printf '  ~/.ssh/\n'
    printf '  .env* files in configured workspaces\n'

    printf '\n'

    printf '%s\n' "Additional files/folders:"
    printf '  Edit: %s\n' "$RESTIC_INCLUDE_FILE"

    printf '\n'

    printf '%s\n' "Examples:"
    printf '  ~/Documents/important\n'
    printf '  ~/Projects/project-a/config.json\n'
    printf '  ~/.config/my-application/\n'

    printf '\n'

    printf '%s\n' "Useful commands:"
    printf '  systemctl --user status restic-backup.timer\n'
    printf '  systemctl --user start restic-backup.service\n'
    printf '  journalctl --user -u restic-backup.service --no-pager\n'
    printf '  source ~/.config/restic/env && restic snapshots\n'

    printf '\n'

    printf '%s\n' "Configuration:"
    printf '  %s\n' "$RESTIC_CONFIG_DIR"

    printf '\n'

    printf '%s\n' "IMPORTANT:"
    printf '%s\n' \
        "Keep your Restic repository password somewhere safe."
    printf '%s\n' \
        "Without it, your encrypted backup cannot be restored."

    printf '\n'
}


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    require_linux
    require_bash

    log "Starting Restic + Backblaze B2 backup setup."

    install_restic
    create_directories
    collect_credentials
    write_environment
    write_backup_script
    initialize_repository
    write_systemd_service
    write_systemd_timer
    enable_systemd
    run_initial_backup
    verify_backup
    print_summary
}


main "$@"

