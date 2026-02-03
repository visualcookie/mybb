#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

MYBB_SOURCE="/opt/mybb-source"

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

get_image_version() {
    cat "${MYBB_SOURCE}/.mybb_version" 2>/dev/null || echo "unknown"
}

# Sync MyBB files from image to volume
# By default, skip files that already exist (preserves user configs)
sync_mybb() {
    local skip_existing="$1"
    local version=$(get_image_version)

    if [ ! -d "${MYBB_SOURCE}" ]; then
        log_error "MyBB source not found in image"
        return 1
    fi

    log_info "Syncing MyBB ${version} to volume..."

    if [ "$skip_existing" = "true" ]; then
        # Copy only new files, don't overwrite existing (upgrade-safe)
        rsync -a --ignore-existing "${MYBB_SOURCE}/" /var/www/html/
        log_info "Synced new files (preserved existing)"
    else
        # Fresh install - copy everything
        rsync -a "${MYBB_SOURCE}/" /var/www/html/
        log_info "Synced all files"
    fi

    echo "${version}" > /var/www/html/.mybb_version
}

set_permissions() {
    chown -R www-data:www-data /var/www/html
    find /var/www/html -type d -exec chmod 755 {} \;
    find /var/www/html -type f -exec chmod 644 {} \;

    # MyBB requires these to be writable
    chmod -R 777 /var/www/html/cache 2>/dev/null || true
    chmod -R 777 /var/www/html/uploads 2>/dev/null || true
    chmod 666 /var/www/html/inc/settings.php 2>/dev/null || true
    chmod 666 /var/www/html/inc/config.php 2>/dev/null || true
    chmod -R 777 /var/www/html/admin/backups 2>/dev/null || true

    # Create config.php if missing (for installer)
    if [ ! -f /var/www/html/inc/config.php ]; then
        touch /var/www/html/inc/config.php
        chmod 666 /var/www/html/inc/config.php
        chown www-data:www-data /var/www/html/inc/config.php
    fi
}

wait_for_db() {
    if [ -z "${DB_HOST}" ]; then
        return
    fi

    log_info "Waiting for database..."
    local max_tries=30
    local counter=0

    while ! php -r "new mysqli('${DB_HOST}', '${DB_USER:-root}', '${DB_PASSWORD:-}', '', ${DB_PORT:-3306});" 2>/dev/null; do
        counter=$((counter + 1))
        if [ $counter -ge $max_tries ]; then
            log_warn "Database not ready after ${max_tries} attempts, continuing..."
            return
        fi
        sleep 2
    done
    log_info "Database ready"
}

main() {
    local version=$(get_image_version)
    log_info "Starting MyBB Docker (image version: ${version})"

    # Check if MyBB is already installed
    if [ -f /var/www/html/inc/config.php ] && grep -q "database" /var/www/html/inc/config.php 2>/dev/null; then
        # Existing installation - sync new files but preserve existing
        sync_mybb "true"
    else
        # Fresh install - copy everything
        sync_mybb "false"
        log_info "Visit http://your-server/install/ to complete setup"
    fi

    set_permissions
    wait_for_db

    log_info "Starting Apache..."
    exec "$@"
}

main "$@"
