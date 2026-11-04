# Use a build-time argument to specify the PHP version. Defaulting to 8.4
ARG PHP_VERSION=8.4
# Use a build-time argument to specify the Node.js version. Defaulting to 24.
ARG NODE_VERSION=24
# Debian release of the base image. Only trixie is built; use bookworm here only
# for a PHP version whose base image has no trixie variant.
ARG DEBIAN_RELEASE=trixie
# FrankenPHP release line of the base images (dunglas/frankenphp 1.13 and later
# reload a changed config that contains php_server without crashing).
ARG FRANKENPHP_VERSION=1.13
# Caddy release of the xcaddy builder; it matches the Caddy inside that FrankenPHP line.
ARG CADDY_BUILDER_VERSION=2.11.7
# Souin release built into the binary; each build otherwise takes the latest.
ARG SOUIN_VERSION=v1.7.9
# MariaDB release series of the client tools, installed from MariaDB's own apt
# repository (the Debian client is older and conflicts with the official one).
ARG MARIADB_SERIES=12.3
# Fingerprint of the MariaDB release signing key (mariadb.org/mariadb_release_signing_key.asc).
ARG MARIADB_KEY_FPR=177F4010FE56CA3336300305F1656F24C74CD1D8
# WP-CLI release and the SHA-256 of its phar (github.com/wp-cli/wp-cli/releases).
ARG WP_CLI_VERSION=2.12.0
ARG WP_CLI_SHA256=ce34ddd838f7351d6759068d09793f26755463b4a4610a5a5c0a97b68220d85c

# xcaddy, taken from the official Caddy builder image (a COPY --from cannot expand an ARG,
# so it is a stage of its own).
FROM caddy:${CADDY_BUILDER_VERSION}-builder AS xcaddy

# ==> 1. Builder Stage <==
# This stage compiles a custom FrankenPHP binary with specific Caddy modules.
FROM dunglas/frankenphp:builder-php${PHP_VERSION}-${DEBIAN_RELEASE} AS builder
ARG SOUIN_VERSION

# Copy xcaddy from the official Caddy builder image
COPY --from=xcaddy /usr/bin/xcaddy /usr/bin/xcaddy

# CGO must be enabled to build FrankenPHP with custom modules
# We use xcaddy to build a new binary including the specified plugins.
#
# The nomercure build tag drops the Mercure hub, which is AGPL-3.0. It is
# required rather than optional: github.com/dunglas/frankenphp/caddy carries a
# hard require on github.com/dunglas/mercure/caddy and imports it from
# caddy/mercure.go, so there is no --with line to remove — without this tag the
# hub is compiled in whatever the plugin list says. Vulcain, also AGPL-3.0,
# needs no tag: nothing imports its caddy package once the --with line is gone,
# so it never registers.
RUN CGO_ENABLED=1 \
    XCADDY_SETCAP=1 \
    XCADDY_GO_BUILD_FLAGS="-ldflags='-w -s' -tags=nobadger,nomysql,nopgx,nomercure" \
    CGO_CFLAGS=$(php-config --includes) \
    CGO_LDFLAGS="$(php-config --ldflags) $(php-config --libs)" \
    xcaddy build \
        --output /usr/local/bin/frankenphp \
        --with github.com/dunglas/frankenphp=./ \
        --with github.com/dunglas/frankenphp/caddy=./caddy/ \
        --with github.com/corazawaf/coraza-caddy/v2@v2.6.2 \
        --with pkg.jsn.cam/caddy-defender@v0.10.1 \
        --with github.com/mholt/caddy-ratelimit@v0.1.0 \
        --with github.com/dunglas/caddy-cbrotli@v1.0.1 \
        --with github.com/caddy-dns/vultr@v0.0.0-20250723121531-55bf3e9768be \
        --with github.com/caddy-dns/azure@v0.6.0 \
        --with github.com/caddy-dns/googleclouddns@v1.1.0 \
        --with github.com/caddy-dns/digitalocean@v0.0.0-20250606074528-04bde2867106 \
        --with github.com/caddy-dns/cloudflare@v0.2.4 \
        --with github.com/caddy-dns/route53@v1.6.2 \
        --with github.com/darkweak/souin/plugins/caddy@${SOUIN_VERSION} \
        --with github.com/darkweak/storages/go-redis/caddy@v0.0.20 \
        --with github.com/darkweak/storages/otter/caddy@v0.0.20 \
        --with github.com/darkweak/storages/simplefs/caddy@v0.0.20
# ==> 2. Runner Stage <==
# This is the final image. It uses the custom binary from the builder stage.
FROM dunglas/frankenphp:${FRANKENPHP_VERSION}-php${PHP_VERSION}-${DEBIAN_RELEASE} AS runner

LABEL org.opencontainers.image.title="frankenphp" \
      org.opencontainers.image.description="FrankenPHP with a custom Caddy build, 51 PHP extensions, Composer, WP-CLI, the MariaDB client and Node.js" \
      org.opencontainers.image.source="https://github.com/sitespanel/frankenphp-docker" \
      org.opencontainers.image.licenses="MIT"

# Copy the custom-built FrankenPHP binary from the builder stage
COPY --from=builder /usr/local/bin/frankenphp /usr/local/bin/frankenphp

# Re-declare ARGs to be available in subsequent build stages
ARG PHP_VERSION
ARG NODE_VERSION
ARG DEBIAN_RELEASE
ARG MARIADB_SERIES
ARG MARIADB_KEY_FPR
ARG WP_CLI_VERSION
ARG WP_CLI_SHA256

# ==> 0. Refuse a PHP below the fixed releases <==
# CVE-2026-109618 and CVE-2026-109619 (GHSA-w8hw-w9fx-j79w, GHSA-6wmf-4rv5-p3rp) are fixed in 8.2.35, 8.3.36,
# 8.4.27 and 8.5.12. A base image older than that fails the build instead of shipping. Raise the floor when
# a later advisory needs it.
RUN set -eu; \
    case "${PHP_VERSION}" in \
      8.2) min=8.2.35 ;; \
      8.3) min=8.3.36 ;; \
      8.4) min=8.4.27 ;; \
      8.5) min=8.5.12 ;; \
      *) echo "no security floor is set for PHP ${PHP_VERSION}"; exit 1 ;; \
    esac; \
    php -r 'exit(version_compare(PHP_VERSION, $argv[1], ">=") ? 0 : 1);' "$min" \
      || { echo "PHP $(php -r 'echo PHP_VERSION;') is below the fixed release ${min}"; exit 1; }

# ==> 3. Install System Dependencies & Node.js <==
# The MariaDB client comes from MariaDB's own repository, whose key is checked
# against a pinned fingerprint. MariaDB 11.8 and later ship no mysql-named
# commands, so small wrappers run the mariadb tools under their own names (a
# bare symlink makes every call print a "Deprecated program name" notice).
RUN set -eux; \
    export DEBIAN_FRONTEND=noninteractive; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl gnupg; \
    install -d -m 0755 /etc/apt/keyrings; \
    curl -fsSL https://mariadb.org/mariadb_release_signing_key.asc -o /etc/apt/keyrings/mariadb.asc; \
    gpg --show-keys --with-colons /etc/apt/keyrings/mariadb.asc | grep -q "^fpr:::::::::${MARIADB_KEY_FPR}:"; \
    . /etc/os-release; \
    echo "deb [signed-by=/etc/apt/keyrings/mariadb.asc] https://mirror.mariadb.org/repo/${MARIADB_SERIES}/debian ${VERSION_CODENAME} main" > /etc/apt/sources.list.d/mariadb.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        acl \
        mariadb-client \
        dnsutils \
        git \
        gosu \
        jq \
        less \
        libcap2-bin \
        libnss3-tools \
        msmtp \
        msmtp-mta \
        netcat-openbsd \
        procps \
        unzip \
        wget \
        zip \
        ffmpeg; \
    for t in mysql:mariadb mysqldump:mariadb-dump mysqlcheck:mariadb-check mysqladmin:mariadb-admin mysqlimport:mariadb-import mysqlshow:mariadb-show; do \
        printf '#!/bin/bash\nexec -a %s /usr/bin/%s "$@"\n' "${t#*:}" "${t#*:}" > "/usr/bin/${t%%:*}"; \
        chmod 0755 "/usr/bin/${t%%:*}"; \
    done; \
    curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash -; \
    apt-get install -y --no-install-recommends nodejs; \
    rm -rf /var/lib/apt/lists/*

# ==> 4. Install PHP Extensions <==
COPY --from=ghcr.io/mlocati/php-extension-installer /usr/bin/install-php-extensions /usr/local/bin/
COPY scripts/install-extensions.sh /usr/local/bin/
COPY data/installable-extensions /tmp/
COPY data/supported-extensions /tmp/
RUN chmod +x /usr/local/bin/install-extensions.sh && \
    IPE_ICU_EN_ONLY=1 install-extensions.sh ${PHP_VERSION} && \
    rm /tmp/installable-extensions /tmp/supported-extensions

# ==> 5. Install Global PHP Tools <==
COPY --from=composer:2.10.3 /usr/bin/composer /usr/local/bin/composer
# (a pinned release, verified against its published SHA-256)
RUN set -eux; \
    curl -fsSL -o /usr/local/bin/wp "https://github.com/wp-cli/wp-cli/releases/download/v${WP_CLI_VERSION}/wp-cli-${WP_CLI_VERSION}.phar"; \
    echo "${WP_CLI_SHA256}  /usr/local/bin/wp" | sha256sum -c -; \
    chmod 0755 /usr/local/bin/wp

# ==> 6. Configure PHP <==
# Use the production php.ini configuration file
RUN cp /usr/local/etc/php/php.ini-production /usr/local/etc/php/php.ini
# msmtp (and msmtp-mta) are installed above but deliberately NOT enabled here:
# no sendmail_path is baked in, so mail() is off by default. Whatever deploys
# this image turns mail on when it wants to, by setting sendmail_path (for
# example "/usr/bin/msmtp -t") and writing /etc/msmtprc once an SMTP relay is known.

# ==> 7. Final Setup <==
WORKDIR /app
EXPOSE 80 443 443/udp

# Default command to run FrankenPHP, expecting a user-provided Caddyfile
CMD ["frankenphp", "run", "--config", "/etc/caddy/Caddyfile"]
