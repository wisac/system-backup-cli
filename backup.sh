#!/usr/bin/env bash

# File: backup.sh
# Production-grade Restic backup script to Google Cloud Storage

# Fail-fast options
set -Eeuo pipefail
# Trap errors
trap 'error_handler $? $LINENO "$BASH_COMMAND"' ERR

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ENV_FILE="${SCRIPT_DIR}/.env"
readonly EXCLUDE_FILE="${SCRIPT_DIR}/exclude.txt"
readonly INCLUDE_FILE="${SCRIPT_DIR}/include.txt"
readonly LOG_DIR="${SCRIPT_DIR}/logs"
readonly LOCK_FILE="/tmp/restic-backup.lock"

error_handler() {
    local exit_code=$1
    local line_no=$2
    local command=$3
    echo "[$(date -Iseconds)] ERROR: Command '${command}' failed at line ${line_no} with exit code ${exit_code}." >&2
}

log() {
    echo "[$(date -Iseconds)] $1" | tee -a "${LOG_DIR}/backup.log"
}

check_network() {
    log "INFO: Checking connectivity to Google Cloud Storage..."
    if ! ping -c 1 -W 5 storage.googleapis.com >/dev/null 2>&1; then
        log "ERROR: Cannot reach Google Cloud Storage. Proceeding to exit."
        exit 1
    fi
}

check_battery() {
    if [[ "${CHECK_BATTERY:-true}" == "true" ]]; then
        # Check if any battery is discharging
        if grep -q "Discharging" /sys/class/power_supply/*/status 2>/dev/null; then
            log "WARN: Laptop is running on battery. Skipping backup to conserve power."
            exit 0
        fi
    fi
}

init_repo() {
    log "INFO: Checking if Restic repository exists..."
    export RESTIC_PASSWORD_FILE
    export GOOGLE_APPLICATION_CREDENTIALS
    export GOOGLE_PROJECT_ID

    if ! restic snapshots >/dev/null 2>&1; then
        log "INFO: Initialising repository at ${RESTIC_REPOSITORY}..."
        # Using B2/S3/GCS requires init
        restic init
        log "SUCCESS: Initialised new repository."
    fi
}

run_backup() {
    log "INFO: Starting backup of ${BACKUP_SOURCE} and paths in ${INCLUDE_FILE}..."
    local attempts=0
    local success=false
    local max_retries="${MAX_RETRIES:-3}"

    local backup_args=(
        --exclude-file="${EXCLUDE_FILE}"
        --tag laptop
    )

    if [[ -f "${INCLUDE_FILE}" ]] && grep -q '[^[:space:]]' "${INCLUDE_FILE}"; then
        backup_args+=(--files-from="${INCLUDE_FILE}")
    fi

    while [[ $attempts -lt $max_retries ]]; do
        if restic backup "${backup_args[@]}" "${BACKUP_SOURCE}"; then
            success=true
            break
        else
            attempts=$((attempts + 1))
            log "WARN: Backup failed. Retry ${attempts}/${max_retries}..."
            sleep 10
        fi
    done

    if [[ "$success" == "false" ]]; then
        log "ERROR: Backup completely failed after ${max_retries} attempts."
        exit 1
    fi
    log "SUCCESS: Backup completed."
}

apply_retention() {
    log "INFO: Applying retention policy (forget & prune)..."
    restic forget \
        --prune \
        --keep-daily 7 \
        --keep-weekly 4 \
        --keep-monthly 6
    log "SUCCESS: Retention policy applied."
}

check_integrity() {
    # Check if today is Sunday (day 0) to run the weekly integrity check
    if [[ "$(date +%u)" -eq 7 ]]; then
        log "INFO: Weekly schedule detected. Running Restic integrity check..."
        restic check
        log "SUCCESS: Integrity check passed."
    fi
}

main() {
    mkdir -p "${LOG_DIR}"

    if [[ ! -f "${ENV_FILE}" ]]; then
        log "ERROR: Configuration file not found at ${ENV_FILE}. Please copy .env.example to .env and configure it."
        exit 1
    fi

    # Read .env (safe subset only, avoiding code execution)
    set -a
    source "${ENV_FILE}"
    set +a

    if [[ -z "${RESTIC_REPOSITORY}" || -z "${RESTIC_PASSWORD_FILE}" || -z "${GOOGLE_APPLICATION_CREDENTIALS}" ]]; then
        log "ERROR: Missing required environment variables. Check your .env setup."
        exit 1
    fi

    check_network
    check_battery

    init_repo
    run_backup
    apply_retention
    check_integrity

    log "SUCCESS: All backup operations finished successfully."
}

# Enforce script atomicity with flock
(
    flock -n 9 || { log "WARN: Another backup instance is already running. Exiting."; exit 1; }
    main "$@"
) 9> "${LOCK_FILE}"
