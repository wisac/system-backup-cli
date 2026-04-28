#!/usr/bin/env bash

# File: restore.sh
# Production-grade Restic restore script

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ENV_FILE="${SCRIPT_DIR}/.env"

# Setup environment
if [[ ! -f "${ENV_FILE}" ]]; then
    echo "ERROR: Configuration file not found at ${ENV_FILE}. Cannot proceed."
    exit 1
fi
set -a
source "${ENV_FILE}"
set +a
export RESTIC_PASSWORD_FILE
export GOOGLE_APPLICATION_CREDENTIALS
export GOOGLE_PROJECT_ID

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Restic restore wrapper tool."
    echo ""
    echo "Options:"
    echo "  --latest [target_dir]        Restore the latest snapshot to the target directory"
    echo "  --id [snap_id] [target_dir]  Restore a specific snapshot by ID to the target directory"
    echo "  --file [file_path]           Restore a single file/directory from the latest snapshot"
    echo "  --dry-run                    Preview restore without modifying anything (does not apply to --file yet)"
    echo "  --list                       List all snapshots"
    echo "  --help                       Show this help menu"
}

if [[ $# -eq 0 ]]; then
    show_usage
    exit 1
fi

DRY_RUN=0

# Parse arguments roughly
for arg in "$@"; do
    if [[ "$arg" == "--dry-run" ]]; then
        DRY_RUN=1
        break
    fi
done

case "$1" in
    --latest)
        TARGET_DIR="${2:-/tmp/restic-restore-latest}"
        echo "Restoring latest snapshot to ${TARGET_DIR}..."
        if [ "$DRY_RUN" -eq 1 ]; then
            restic restore latest --target "${TARGET_DIR}" --dry-run
        else
            mkdir -p "${TARGET_DIR}"
            restic restore latest --target "${TARGET_DIR}"
        fi
        ;;
    --id)
        if [[ -z "${2:-}" ]]; then
            echo "ERROR: Missing snapshot ID"
            show_usage
            exit 1
        fi
        SNAP_ID="$2"
        TARGET_DIR="${3:-/tmp/restic-restore-${SNAP_ID}}"
        echo "Restoring snapshot ${SNAP_ID} to ${TARGET_DIR}..."
        if [ "$DRY_RUN" -eq 1 ]; then
            restic restore "${SNAP_ID}" --target "${TARGET_DIR}" --dry-run
        else
            mkdir -p "${TARGET_DIR}"
            restic restore "${SNAP_ID}" --target "${TARGET_DIR}"
        fi
        ;;
    --file)
        if [[ -z "${2:-}" ]]; then
            echo "ERROR: Missing file path"
            show_usage
            exit 1
        fi
        TARGET_FILE="$2"
        RESTORE_PATH="/tmp/restic-file-restore"
        echo "Restoring ${TARGET_FILE} to ${RESTORE_PATH}..."
        mkdir -p "${RESTORE_PATH}"
        restic restore latest --target "${RESTORE_PATH}" --include "${TARGET_FILE}"
        echo "File restored under ${RESTORE_PATH}"
        ;;
    --list)
        restic snapshots
        ;;
    --help)
        show_usage
        ;;
    *)
        echo "ERROR: Unknown option $1"
        show_usage
        exit 1
        ;;
esac
