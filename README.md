# MyBB Docker Image

![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/visualcookie/mybb/docker-publish.yml?style=for-the-badge&label=Docker%20Image)
![GitHub Stars](https://img.shields.io/github/stars/visualcookie/mybb?style=for-the-badge)
![GitHub License](https://img.shields.io/github/license/visualcookie/mybb?style=for-the-badge)
![GHCR](https://img.shields.io/badge/ghcr.io-visualcookie%2Fmybb-blue?style=for-the-badge&logo=docker) ![Assisted Using Claude](https://img.shields.io/badge/Claude-D97757?style=for-the-badge&logo=claude&logoColor=white)

A Docker image for [MyBB](https://mybb.com/) forum software with MyBB baked into the image at build time.

## Features

- 🐳 Easy deployment with Docker or Docker Compose
- 📦 MyBB pre-installed in the image (no runtime downloads)
- 💾 Persistent data storage with Docker volumes
- 🔒 Secure default configuration
- 🚀 Optimized PHP configuration for MyBB
- ⬆️ Safe upgrade mode preserving configs, uploads, themes, and plugins
- ❤️ Health checks for container orchestration
- 📂 Optional SFTP server for file management (themes, plugins, updates)
- 📦 Optional phpMyAdmin for database management

## Quick Start

### Using Docker Compose (Recommended)

There's an example [Docker compose file](./docker-compose.ghcr.yml) in this repo, which pulls this image.

### Using Docker CLI

1. **Build the image:**
   ```bash
   docker build --build-arg MYBB_VERSION=1839 -t mybb .
   ```

2. **Create a network:**
   ```bash
   docker network create mybb-network
   ```

3. **Start MariaDB:**
   ```bash
   docker run -d \
     --name mybb-db \
     --network mybb-network \
     -e MYSQL_ROOT_PASSWORD=root_password \
     -e MYSQL_DATABASE=mybb \
     -e MYSQL_USER=mybb \
     -e MYSQL_PASSWORD=mybb_password \
     -v mybb_db_data:/var/lib/mysql \
     mariadb:10.11
   ```

4. **Start MyBB:**
   ```bash
   docker run -d \
     --name mybb-forum \
     --network mybb-network \
     -p 8080:80 \
     -e DB_HOST=mybb-db \
     -e DB_USER=mybb \
     -e DB_PASSWORD=mybb_password \
     -e DB_NAME=mybb \
     -v mybb_data:/var/www/html \
     mybb
   ```

5. **Access MyBB at http://localhost:8080**

6. **(Optional) Start SFTP server:**
   ```bash
   docker run -d \
     --name mybb-sftp \
     --network mybb-network \
     -p 2222:22 \
     -v mybb_data:/home/mybb/mybb \
     atmoz/sftp \
     mybb:your_password:33:33:mybb
   ```

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `MYBB_VERSION` | MyBB version (build argument) | `1839` |
| `MYBB_PORT` | Web server port | `8080` |
| `DB_HOST` | Database hostname | - |
| `DB_PORT` | Database port | `3306` |
| `DB_USER` | Database username | `root` |
| `DB_PASSWORD` | Database password | - |
| `DB_NAME` | Database name | `mybb` |
| `FORCE_REINSTALL` | Force reinstall MyBB | `false` |
| `SFTP_PORT` | SFTP server port | `2222` |
| `SFTP_USER` | SFTP username | `mybb` |
| `SFTP_PASSWORD` | SFTP password | `mybb_sftp_pass` |
| `PMA_PORT` | phpMyAdmin port | `8081` |
| `TZ` | Timezone | `UTC` |
| `UPGRADE_MODE` | Enable safe upgrade mode | `false` |
| `PRESERVE_PLUGINS` | Keep plugins during upgrade | `true` |
| `PRESERVE_THEMES` | Keep themes during upgrade | `true` |

### MyBB Versions

MyBB is baked into the image at build time. Pre-built images are available for the 2 latest versions:

```bash
docker pull ghcr.io/visualcookie/mybb:latest  # 1839
docker pull ghcr.io/visualcookie/mybb:1839
docker pull ghcr.io/visualcookie/mybb:1838
```

To build a different version locally:

```bash
docker build --build-arg MYBB_VERSION=1837 -t mybb:1837 .
```

## Volumes

The following volumes are created for data persistence:

| Volume | Path | Description |
|--------|------|-------------|
| `mybb_data` | `/var/www/html` | Complete MyBB installation (shared with SFTP) |
| `mybb_db_data` | `/var/lib/mysql` | Database files |
| `mybb_sftp_keys` | `/etc/ssh/keys` | SFTP server host keys (persistent identity) |

## Using SFTP

SFTP allows you to manage MyBB files directly - upload themes, install plugins, edit templates, or perform manual updates.

### Enable SFTP

```bash
# Start with SFTP only
docker compose --profile sftp up -d

# Or start with all tools (SFTP + phpMyAdmin)
docker compose --profile tools up -d
```

### Connect via SFTP

Use any SFTP client (FileZilla, WinSCP, Cyberduck, or command line):

```bash
# Command line
sftp -P 2222 mybb@localhost

# Connection details
Host: localhost (or your server IP)
Port: 2222 (or your SFTP_PORT)
Username: mybb (or your SFTP_USER)
Password: (your SFTP_PASSWORD from .env)
```

### SFTP Directory Structure

After connecting, your files are located at:
```
/home/mybb/mybb/
├── admin/          # Admin control panel
├── cache/          # Cache files
├── images/         # Forum images
├── inc/            # Core includes & config
├── install/        # Installation files (delete after setup!)
├── jscripts/       # JavaScript files
├── uploads/        # User uploads (avatars, attachments)
└── index.php       # Main entry point
```

### Common SFTP Tasks

**Upload a theme:**
```
put -r mytheme/* /home/mybb/mybb/images/mytheme/
```

**Install a plugin:**
```
put myplugin.php /home/mybb/mybb/inc/plugins/
```

**Backup configuration:**
```
get /home/mybb/mybb/inc/config.php ./config.php.backup
```

### SFTP Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `SFTP_PORT` | SFTP server port | `2222` |
| `SFTP_USER` | SFTP username | `mybb` |
| `SFTP_PASSWORD` | SFTP password | `mybb_sftp_pass` |

## Using phpMyAdmin

To enable phpMyAdmin for database management:

```bash
docker compose --profile tools up -d
```

Access phpMyAdmin at http://localhost:8081

## MyBB Installation Wizard

After starting the containers, complete the MyBB setup:

1. Navigate to http://localhost:8080/install/
2. Follow the installation wizard
3. Database settings for Docker Compose:
   - **Database Engine:** MySQL Improved
   - **Database Server Hostname:** `mybb-db`
   - **Database Username:** `mybb` (or your `MYSQL_USER`)
   - **Database Password:** Your `MYSQL_PASSWORD`
   - **Database Name:** `mybb` (or your `MYSQL_DATABASE`)
   - **Table Prefix:** `mybb_` (default)

4. After installation, **delete the install folder**:
   ```bash
   docker exec mybb-forum rm -rf /var/www/html/install
   ```

## Upgrading MyBB (Safe Upgrade Mode)

This image includes a **safe upgrade mode** that preserves your configuration, uploads, themes, and plugins while updating MyBB core files.

### Quick Upgrade Steps

1. **Update to a new image** with the desired MyBB version (change image tag or rebuild)

2. **Enable upgrade mode** in `.env`:
   ```bash
   UPGRADE_MODE=true
   ```

3. **Restart the container:**
   ```bash
   docker compose down && docker compose up -d
   ```

4. **Complete the upgrade:**
   - Visit `http://localhost:8080/install/upgrade.php`
   - Follow the upgrade wizard

5. **Cleanup:**
   ```bash
   docker exec mybb-forum rm -rf /var/www/html/install
   docker exec mybb-forum rm -f /var/www/html/UPGRADE_IN_PROGRESS.txt
   # Set UPGRADE_MODE=false in .env
   ```

### What Gets Preserved

| Item | Preserved | Notes |
|------|-----------|-------|
| `inc/config.php` | ✅ Always | Database configuration |
| `inc/settings.php` | ✅ Always | Forum settings |
| `uploads/` | ✅ Always | User avatars, attachments |
| `inc/plugins/` | ✅ Default | Set `PRESERVE_PLUGINS=false` to reset |
| `images/` | ✅ Default | Set `PRESERVE_THEMES=false` to reset |
| `inc/languages/` | ✅ Always | Language customizations |

### What Gets Updated

- All core PHP files
- JavaScript files
- Default images/icons
- Install/upgrade scripts

### Upgrade Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `UPGRADE_MODE` | Enable safe upgrade mode | `false` |
| `PRESERVE_PLUGINS` | Keep existing plugins | `true` |
| `PRESERVE_THEMES` | Keep existing themes | `true` |

### Automatic Backups

Before upgrading, the script automatically backs up critical files to `/var/www/html/admin/backups/`:
- `pre_upgrade_TIMESTAMP_config.php`
- `pre_upgrade_TIMESTAMP_settings.php`
- `pre_upgrade_TIMESTAMP_plugins_list.txt`
- `pre_upgrade_TIMESTAMP_themes_list.txt`

### Manual Backup (Recommended)

For extra safety, create a full backup before upgrading:

```bash
# Backup files
docker exec mybb-forum tar -czvf /tmp/mybb-backup.tar.gz /var/www/html
docker cp mybb-forum:/tmp/mybb-backup.tar.gz ./mybb-backup.tar.gz

# Backup database
docker exec mybb-database mysqldump -u mybb -p mybb > mybb-database-backup.sql
```

### Alternative: Manual Upgrade via SFTP

If you prefer manual control, use SFTP:

1. Download new MyBB from [mybb.com](https://mybb.com/download/)
2. Connect via SFTP (see SFTP section above)
3. Upload new files, but **skip** `inc/config.php`
4. Visit `/install/upgrade.php`
5. Delete the install folder

## Troubleshooting

### Container won't start
```bash
# Check logs
docker logs mybb-forum

# Check database logs
docker logs mybb-db
```

### Permission issues
```bash
# Fix permissions manually
docker exec mybb-forum chown -R www-data:www-data /var/www/html
docker exec mybb-forum chmod -R 755 /var/www/html
docker exec mybb-forum chmod -R 777 /var/www/html/uploads /var/www/html/cache
```

### Database connection issues
- Ensure the database container is healthy: `docker ps`
- Verify credentials in `.env` match the installation wizard inputs
- Check if the network is properly configured

### Force reinstall MyBB
```bash
docker run -d \
  --name mybb-forum \
  -e FORCE_REINSTALL=true \
  ...
```

## Security Recommendations

1. **Change default passwords** in `.env` (database, SFTP)
2. **Use HTTPS** with a reverse proxy (nginx, Traefik, Caddy)
3. **Remove install folder** after setup
4. **Regular backups** of volumes
5. **Keep MyBB updated** with security patches
6. **Restrict SFTP access** - only expose port 2222 when needed, or use firewall rules
7. **Use SSH keys** for SFTP instead of passwords (mount keys to `/home/user/.ssh/keys/`)

## License

This Docker configuration is provided as-is. MyBB itself is licensed under the LGPL v3.

## Disclaimer about use of AI

I used AI on parts of this project e.g. for the README.md file and the Dockerfile as well as the docker-entrypoint.sh file to help me write it faster. I oriented myself on the existing Docker image for MyBB: https://github.com/mybb/docker

## Contributing

Contributions are welcome! Please submit issues and pull requests.
