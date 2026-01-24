#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Function to download MyBB
download_mybb() {
    local version=$1
    local download_url="https://github.com/mybb/mybb/releases/download/mybb_${version}/mybb_${version}.zip"
    
    log_info "Downloading MyBB version ${version}..."
    
    # Download MyBB
    if ! wget -q --show-progress -O /tmp/mybb.zip "$download_url"; then
        log_error "Failed to download MyBB version ${version}"
        log_info "Trying alternative URL format..."
        
        # Try alternative URL format (some versions use different naming)
        download_url="https://resources.mybb.com/downloads/mybb_${version}.zip"
        if ! wget -q --show-progress -O /tmp/mybb.zip "$download_url"; then
            log_error "Failed to download MyBB. Please check if version ${version} exists."
            log_info "Available versions: https://github.com/mybb/mybb/releases"
            return 1
        fi
    fi
    
    return 0
}

# Function to extract MyBB to a target directory
extract_mybb() {
    local target_dir=$1
    
    log_info "Extracting MyBB..."
    
    # Extract to temporary directory
    rm -rf /tmp/mybb_extract
    unzip -q /tmp/mybb.zip -d /tmp/mybb_extract
    
    # Find the Upload directory (MyBB packages contain Upload folder)
    if [ -d "/tmp/mybb_extract/Upload" ]; then
        cp -r /tmp/mybb_extract/Upload/* "$target_dir/"
    elif [ -d "/tmp/mybb_extract/upload" ]; then
        cp -r /tmp/mybb_extract/upload/* "$target_dir/"
    else
        # Some versions might extract directly
        cp -r /tmp/mybb_extract/*/* "$target_dir/" 2>/dev/null || cp -r /tmp/mybb_extract/* "$target_dir/"
    fi
    
    # Cleanup
    rm -rf /tmp/mybb.zip /tmp/mybb_extract
    
    log_info "MyBB extracted successfully"
}

# Function to install MyBB (fresh install)
install_mybb() {
    extract_mybb "/var/www/html"
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

# Function to perform safe upgrade
upgrade_mybb() {
    local target_version=$1
    
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
    log_info "Step 1/5: Creating backup..."
    create_backup
    
    # Step 2: Save files that must be preserved
    log_info ""
    log_info "Step 2/5: Preserving critical files..."
    
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
    
    # Step 3: Download new version
    log_info ""
    log_info "Step 3/5: Downloading MyBB ${target_version}..."
    if ! download_mybb "${target_version}"; then
        log_error "Download failed! Aborting upgrade."
        log_info "Your current installation is unchanged."
        rm -rf /tmp/mybb_preserve
        return 1
    fi
    
    # Step 4: Extract new version (overwrite core files)
    log_info ""
    log_info "Step 4/5: Installing new version..."
    extract_mybb "/var/www/html"
    
    # Step 5: Restore preserved files
    log_info ""
    log_info "Step 5/5: Restoring preserved files..."
    
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
    log_info "Starting MyBB Docker container..."
    log_info "MyBB Version: ${MYBB_VERSION}"
    
    # Check for upgrade mode FIRST
    if [ "${UPGRADE_MODE:-false}" = "true" ]; then
        log_warn "UPGRADE MODE ENABLED"
        
        if upgrade_mybb "${MYBB_VERSION}"; then
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
        
        # Download and install MyBB
        if download_mybb "${MYBB_VERSION}"; then
            install_mybb
            set_permissions
            log_info "MyBB installation complete!"
            log_info "Please visit http://your-server/install/ to complete the setup."
        else
            log_error "MyBB installation failed!"
            exit 1
        fi
    else
        log_info "MyBB already installed. Skipping download."
        
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
