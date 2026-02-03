FROM php:8.2-apache

# OCI Labels for GitHub Container Registry
LABEL org.opencontainers.image.source="https://github.com/visualcookie/mybb"
LABEL org.opencontainers.image.description="MyBB Forum Software - Pre-built Docker image with MyBB included"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.title="MyBB Docker"
LABEL org.opencontainers.image.vendor="visualcookie"

# Build argument for MyBB version (REQUIRED at build time)
ARG MYBB_VERSION

# Environment variables
ENV MYBB_VERSION=${MYBB_VERSION}
ENV APACHE_DOCUMENT_ROOT=/var/www/html
# Directory where MyBB is pre-installed at build time
ENV MYBB_SOURCE_DIR=/opt/mybb-source

# Install system dependencies
RUN apt-get update && apt-get install -y \
    libpng-dev \
    libjpeg-dev \
    libfreetype6-dev \
    libzip-dev \
    libicu-dev \
    libxml2-dev \
    unzip \
    curl \
    wget \
    rsync \
    && rm -rf /var/lib/apt/lists/*

# Configure and install PHP extensions required by MyBB
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) \
    gd \
    mysqli \
    pdo \
    pdo_mysql \
    zip \
    intl \
    xml \
    opcache

# Enable Apache modules
RUN a2enmod rewrite headers expires

# Configure PHP for MyBB
RUN { \
    echo 'upload_max_filesize = 64M'; \
    echo 'post_max_size = 64M'; \
    echo 'memory_limit = 256M'; \
    echo 'max_execution_time = 300'; \
    echo 'max_input_vars = 5000'; \
    } > /usr/local/etc/php/conf.d/mybb.ini

# Configure OPcache for better performance
RUN { \
    echo 'opcache.enable=1'; \
    echo 'opcache.memory_consumption=128'; \
    echo 'opcache.interned_strings_buffer=8'; \
    echo 'opcache.max_accelerated_files=4000'; \
    echo 'opcache.revalidate_freq=2'; \
    echo 'opcache.fast_shutdown=1'; \
    } > /usr/local/etc/php/conf.d/opcache-recommended.ini

# Download and install MyBB at build time (not runtime)
# This ensures the image contains a specific MyBB version and eliminates runtime download risks
RUN set -eux; \
    if [ -z "${MYBB_VERSION}" ]; then \
        echo "ERROR: MYBB_VERSION build argument is required"; \
        exit 1; \
    fi; \
    mkdir -p ${MYBB_SOURCE_DIR}; \
    echo "Downloading MyBB version ${MYBB_VERSION}..."; \
    wget -q -O /tmp/mybb.zip "https://github.com/mybb/mybb/releases/download/mybb_${MYBB_VERSION}/mybb_${MYBB_VERSION}.zip" \
    || wget -q -O /tmp/mybb.zip "https://resources.mybb.com/downloads/mybb_${MYBB_VERSION}.zip"; \
    unzip -q /tmp/mybb.zip -d /tmp/mybb_extract; \
    if [ -d "/tmp/mybb_extract/Upload" ]; then \
        cp -r /tmp/mybb_extract/Upload/* ${MYBB_SOURCE_DIR}/; \
    elif [ -d "/tmp/mybb_extract/upload" ]; then \
        cp -r /tmp/mybb_extract/upload/* ${MYBB_SOURCE_DIR}/; \
    else \
        cp -r /tmp/mybb_extract/*/* ${MYBB_SOURCE_DIR}/ 2>/dev/null || cp -r /tmp/mybb_extract/* ${MYBB_SOURCE_DIR}/; \
    fi; \
    rm -rf /tmp/mybb.zip /tmp/mybb_extract; \
    echo "MyBB ${MYBB_VERSION} installed to ${MYBB_SOURCE_DIR}"; \
    echo "${MYBB_VERSION}" > ${MYBB_SOURCE_DIR}/.mybb_version

# Set working directory
WORKDIR /var/www/html

# Copy entrypoint script
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Create directories for persistence
RUN mkdir -p /var/www/html/uploads \
    /var/www/html/cache \
    /var/www/html/inc/settings \
    /var/www/html/admin/backups

# Set proper permissions
RUN chown -R www-data:www-data /var/www/html \
    && chown -R www-data:www-data ${MYBB_SOURCE_DIR}

# Expose port 80
EXPOSE 80

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost/ || exit 1

# Set entrypoint
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["apache2-foreground"]
