#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Source directory where MyBB is pre-installed at build time
MYBB_SOURCE_DIR="${MYBB_SOURCE_DIR:-/opt/mybb-source}"

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_important() {
    echo -e "${BLUE}[IMPORTANT]${NC} $1"
}

# Function to get the pre-installed MyBB version from the image
get_image_version() {
    if [ -f "${MYBB_SOURCE_DIR}/.mybb_version" ]; then
        cat "${MYBB_SOURCE_DIR}/.mybb_version"
    else
        echo "unknown"
    fi
}

# Function to get the installed MyBB version from the volume
get_installed_version() {
    if [ -f "/var/www/html/.mybb_version" ]; then
        cat "/var/www/html/.mybb_version"
    elif [ -f "/var/www/html/inc/class_core.php" ]; then
        grep -oP "public \\\$version = '\K[^']+" /var/www/html/inc/class_core.php 2>/dev/null || echo "unknown"
    else
        echo "none"
    fi
}

# Function to install MyBB from the pre-built image
install_mybb() {
    local image_version=$(get_image_version)

    log_info "Installing MyBB ${image_version} from image..."

    if [ ! -d "${MYBB_SOURCE_DIR}" ] || [ ! -f "${MYBB_SOURCE_DIR}/index.php" ]; then
        log_error "MyBB source not found in image at ${MYBB_SOURCE_DIR}"
        return 1
    fi

    cp -r "${MYBB_SOURCE_DIR}"/* /var/www/html/
    echo "${image_version}" > /var/www/html/.mybb_version

    log_info "MyBB ${image_version} installed successfully"
}

# Function to create backup before upgrade
create_backup() {
    local backup_dir="/var/www/html/admin/backups"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_name="pre_upgrade_${timestamp}"
    
    log_info "Creating backup before upgrade..."
    
    mkdir -p "$backup_dir"
    
    # Backup critical configuration files
    if [ -f /var/www/html/inc/config.php ]; then
        cp /var/www/html/inc/config.php "$backup_dir/${backup_name}_config.php"
        log_info "Backed up: config.php"
    fi
    
    if [ -f /var/www/html/inc/settings.php ]; then
        cp /var/www/html/inc/settings.php "$backup_dir/${backup_name}_settings.php"
        log_info "Backed up: settings.php"
    fi
    
    # Create a list of installed plugins
    if [ -d /var/www/html/inc/plugins ]; then
        ls -1 /var/www/html/inc/plugins/ > "$backup_dir/${backup_name}_plugins_list.txt" 2>/dev/null || true
        log_info "Backed up: plugins list"
    fi
    
    # Backup custom themes list
    if [ -d /var/www/html/images ]; then
        ls -1 /var/www/html/images/ > "$backup_dir/${backup_name}_themes_list.txt" 2>/dev/null || true
        log_info "Backed up: themes list"
    fi
    
    # Store current version info if available
    if [ -f /var/www/html/inc/class_core.php ]; then
        grep -o "public \$version = '[^']*'" /var/www/html/inc/class_core.php > "$backup_dir/${backup_name}_version.txt" 2>/dev/null || true
    fi
    
    log_info "Backup created in: $backup_dir"
    echo "$backup_dir/${backup_name}" > /tmp/last_backup_path
}

# Function to perform safe upgrade using the version baked into the image
upgrade_mybb() {
    local target_version=$(get_image_version)

    log_info "=========================================="
    log_info "  MyBB SAFE UPGRADE MODE"
    log_info "=========================================="
    log_info "Target version: ${target_version}"
    
    # Check if MyBB is actually installed
    if [ ! -f /var/www/html/inc/config.php ]; then
        log_error "No existing MyBB installation found!"
        log_error "Cannot upgrade - config.php is missing."
        log_error "Use normal install mode instead (remove UPGRADE_MODE)."
        return 1
    fi
    
    # Check if config.php has database settings (not empty template)
    if ! grep -q "database" /var/www/html/inc/config.php 2>/dev/null; then
        log_error "config.php appears to be empty or unconfigured."
        log_error "Cannot upgrade an unconfigured installation."
        return 1
    fi
    
    # Step 1: Create backup
    log_info ""
    log_info "Step 1/4: Creating backup..."
    create_backup

    # Step 2: Save files that must be preserved
    log_info ""
    log_info "Step 2/4: Preserving critical files..."
    
    mkdir -p /tmp/mybb_preserve
    
    # Preserve config.php (CRITICAL - contains database settings)
    cp /var/www/html/inc/config.php /tmp/mybb_preserve/config.php
    log_info "Preserved: inc/config.php"
    
    # Preserve settings.php if it exists
    if [ -f /var/www/html/inc/settings.php ]; then
        cp /var/www/html/inc/settings.php /tmp/mybb_preserve/settings.php
        log_info "Preserved: inc/settings.php"
    fi
    
    # Preserve uploads directory (user avatars, attachments)
    if [ -d /var/www/html/uploads ]; then
        cp -r /var/www/html/uploads /tmp/mybb_preserve/uploads
        log_info "Preserved: uploads/ directory"
    fi
    
    # Preserve custom plugins (optional - admin may want fresh plugins)
    if [ "${PRESERVE_PLUGINS:-true}" = "true" ] && [ -d /var/www/html/inc/plugins ]; then
        cp -r /var/www/html/inc/plugins /tmp/mybb_preserve/plugins
        log_info "Preserved: inc/plugins/ directory"
    fi
    
    # Preserve custom themes/images
    if [ "${PRESERVE_THEMES:-true}" = "true" ] && [ -d /var/www/html/images ]; then
        cp -r /var/www/html/images /tmp/mybb_preserve/images
        log_info "Preserved: images/ directory"
    fi
    
    # Preserve language customizations
    if [ -d /var/www/html/inc/languages ]; then
        cp -r /var/www/html/inc/languages /tmp/mybb_preserve/languages
        log_info "Preserved: inc/languages/ directory"
    fi
    
    # Step 3: Install new version from image
    log_info ""
    log_info "Step 3/4: Installing MyBB ${target_version} from image..."

    if [ ! -d "${MYBB_SOURCE_DIR}" ] || [ ! -f "${MYBB_SOURCE_DIR}/index.php" ]; then
        log_error "MyBB source not found in image. Aborting upgrade."
        rm -rf /tmp/mybb_preserve
        return 1
    fi

    cp -r "${MYBB_SOURCE_DIR}"/* /var/www/html/
    
    # Step 4: Restore preserved files
    log_info ""
    log_info "Step 4/4: Restoring preserved files..."
    
    # Restore config.php (CRITICAL)
    cp /tmp/mybb_preserve/config.php /var/www/html/inc/config.php
    log_info "Restored: inc/config.php"
    
    # Restore settings.php
    if [ -f /tmp/mybb_preserve/settings.php ]; then
        cp /tmp/mybb_preserve/settings.php /var/www/html/inc/settings.php
        log_info "Restored: inc/settings.php"
    fi
    
    # Restore uploads
    if [ -d /tmp/mybb_preserve/uploads ]; then
        rm -rf /var/www/html/uploads
        cp -r /tmp/mybb_preserve/uploads /var/www/html/uploads
        log_info "Restored: uploads/ directory"
    fi
    
    # Restore plugins if preserved
    if [ -d /tmp/mybb_preserve/plugins ]; then
        # Merge plugins - keep new core plugins, restore custom ones
        cp -rn /tmp/mybb_preserve/plugins/* /var/www/html/inc/plugins/ 2>/dev/null || true
        log_info "Restored: custom plugins"
    fi
    
    # Restore themes/images if preserved
    if [ -d /tmp/mybb_preserve/images ]; then
        # Merge - keep new default images, restore custom themes
        cp -rn /tmp/mybb_preserve/images/* /var/www/html/images/ 2>/dev/null || true
        log_info "Restored: custom themes/images"
    fi
    
    # Restore languages
    if [ -d /tmp/mybb_preserve/languages ]; then
        cp -rn /tmp/mybb_preserve/languages/* /var/www/html/inc/languages/ 2>/dev/null || true
        log_info "Restored: language files"
    fi
    
    # Cleanup
    rm -rf /tmp/mybb_preserve

    # Track the upgraded version
    echo "${target_version}" > /var/www/html/.mybb_version

    # Set permissions
    set_permissions

    # Success message
    log_info ""
    log_info "=========================================="
    log_info "  UPGRADE FILES INSTALLED SUCCESSFULLY"
    log_info "=========================================="
    log_important ""
    log_important "╔════════════════════════════════════════════════════════════╗"
    log_important "║  ACTION REQUIRED: Complete the upgrade!                    ║"
    log_important "╠════════════════════════════════════════════════════════════╣"
    log_important "║                                                            ║"
    log_important "║  1. Visit: http://your-server/install/upgrade.php          ║"
    log_important "║  2. Follow the upgrade wizard                              ║"
    log_important "║  3. Delete install folder when complete:                   ║"
    log_important "║     docker exec mybb-forum rm -rf /var/www/html/install    ║"
    log_important "║                                                            ║"
    log_important "╚════════════════════════════════════════════════════════════╝"
    log_important ""
    
    # Remove the installer lock file so upgrade wizard can run
    if [ -f /var/www/html/install/lock ]; then
        rm -f /var/www/html/install/lock
        log_info "Removed install/lock file for upgrade wizard"
    fi
    
    # Create a flag file to remind about upgrade
    echo "Upgrade to version ${target_version} started at $(date)" > /var/www/html/UPGRADE_IN_PROGRESS.txt
    echo "Visit /install/upgrade.php to complete the upgrade" >> /var/www/html/UPGRADE_IN_PROGRESS.txt
    echo "Delete this file after completing the upgrade" >> /var/www/html/UPGRADE_IN_PROGRESS.txt
    
    return 0
}

# Function to set permissions
set_permissions() {
    log_info "Setting file permissions..."
    
    # Set ownership
    chown -R www-data:www-data /var/www/html
    
    # Set directory permissions
    find /var/www/html -type d -exec chmod 755 {} \;
    
    # Set file permissions
    find /var/www/html -type f -exec chmod 644 {} \;
    
    # Make specific directories writable (required by MyBB)
    chmod -R 777 /var/www/html/cache 2>/dev/null || true
    chmod -R 777 /var/www/html/uploads 2>/dev/null || true
    chmod -R 777 /var/www/html/inc/settings.php 2>/dev/null || true
    chmod -R 777 /var/www/html/inc/config.php 2>/dev/null || true
    chmod -R 777 /var/www/html/admin/backups 2>/dev/null || true
    
    # Create config.php if it doesn't exist (for installer)
    if [ ! -f /var/www/html/inc/config.php ]; then
        touch /var/www/html/inc/config.php
        chmod 666 /var/www/html/inc/config.php
        chown www-data:www-data /var/www/html/inc/config.php
    fi
    
    log_info "Permissions set successfully"
}

# Main execution
main() {
    local image_version=$(get_image_version)
    local installed_version=$(get_installed_version)

    log_info "Starting MyBB Docker container..."
    log_info "MyBB version in image: ${image_version}"

    if [ "${installed_version}" != "none" ]; then
        log_info "MyBB version installed: ${installed_version}"
    fi

    # Check for upgrade mode FIRST
    if [ "${UPGRADE_MODE:-false}" = "true" ]; then
        log_warn "UPGRADE MODE ENABLED"

        if upgrade_mybb; then
            log_info "Upgrade preparation complete."
        else
            log_error "Upgrade failed!"
            exit 1
        fi
    # Check for fresh install or forced reinstall
    elif [ ! -f /var/www/html/index.php ] || [ "${FORCE_REINSTALL:-false}" = "true" ]; then
        if [ "${FORCE_REINSTALL:-false}" = "true" ]; then
            log_warn "FORCE REINSTALL enabled - this will overwrite existing files!"
        fi
        log_info "Installing MyBB..."

        # Install MyBB from the pre-built image (no download needed)
        if install_mybb; then
            set_permissions
            log_info "MyBB installation complete!"
            log_info "Please visit http://your-server/install/ to complete the setup."
        else
            log_error "MyBB installation failed!"
            exit 1
        fi
    else
        log_info "MyBB already installed. Skipping installation."

        # Check if image has a newer version than installed
        if [ "${image_version}" != "${installed_version}" ] && [ "${installed_version}" != "unknown" ]; then
            log_warn "=========================================="
            log_warn "  VERSION MISMATCH DETECTED"
            log_warn "=========================================="
            log_warn "Installed version: ${installed_version}"
            log_warn "Image version: ${image_version}"
            log_warn ""
            log_warn "To upgrade, set UPGRADE_MODE=true and restart the container."
            log_warn "=========================================="
        fi

        # Check for upgrade reminder
        if [ -f /var/www/html/UPGRADE_IN_PROGRESS.txt ]; then
            log_warn "=========================================="
            log_warn "  UPGRADE IN PROGRESS - ACTION REQUIRED"
            log_warn "=========================================="
            cat /var/www/html/UPGRADE_IN_PROGRESS.txt
            log_warn "=========================================="
        fi

        # Still set permissions in case of volume mount issues
        set_permissions
    fi
    
    # Wait for database if DB_HOST is set
    if [ -n "${DB_HOST}" ]; then
        log_info "Waiting for database at ${DB_HOST}:${DB_PORT:-3306}..."
        
        max_tries=30
        counter=0
        
        while ! php -r "new mysqli('${DB_HOST}', '${DB_USER:-root}', '${DB_PASSWORD:-}', '', ${DB_PORT:-3306});" 2>/dev/null; do
            counter=$((counter + 1))
            if [ $counter -ge $max_tries ]; then
                log_warn "Could not connect to database after ${max_tries} attempts. Continuing anyway..."
                break
            fi
            log_info "Database not ready. Waiting... (${counter}/${max_tries})"
            sleep 2
        done
        
        if [ $counter -lt $max_tries ]; then
            log_info "Database is ready!"
        fi
    fi
    
    log_info "Starting Apache..."
    
    # Execute the main command
    exec "$@"
}

main "$@"
