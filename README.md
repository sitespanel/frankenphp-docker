# Production-Ready FrankenPHP Docker Images with Custom Caddy Builds

> **SitesPanel image source.** SitesPanel builds this image with Google Cloud Build and serves it from Artifact Registry (`europe-docker.pkg.dev/PROJECT/sitespanel-images/frankenphp`); see [CLOUDBUILD.md](CLOUDBUILD.md). Replace `PROJECT` with SitesPanel's Google Cloud project.


This repository contains the build instructions for a set of customized, production-ready **FrankenPHP** Docker images. They are built on the official `dunglas/frankenphp` base and include a powerful, custom-compiled Caddy web server, a comprehensive set of pre-installed PHP extensions, and common utilities to support modern PHP applications including **Laravel**, **Symfony**, and **WordPress**.

The images are built by Google Cloud Build and published to SitesPanel's Artifact Registry for multiple PHP versions (see [CLOUDBUILD.md](CLOUDBUILD.md)).

## ✨ Why This Image?

| Feature | Official `dunglas/frankenphp` | This Image |
|---------|-------------------------------|------------|
| **Caddy modules** | Minimal | 16 plugins (Coraza WAF, rate limiting, Brotli, Souin cache, 6 DNS providers) |
| **Web application firewall** | ❌ | ✅ OWASP Coraza + Core Rule Set (compiled in) |
| **PHP extensions** | Few built-in | 50+ pre-installed (Redis, MongoDB, Imagick, PostgreSQL, OpenTelemetry, etc.) |
| **Composer** | ❌ | ✅ Latest |
| **WP-CLI** | ❌ | ✅ Latest |
| **Node.js** | ❌ | ✅ v24 (configurable) |
| **MariaDB client** | ❌ | ✅ `mariadb` tools, also as `mysql`, `mysqldump` |
| **Ready to deploy** | Needs setup | `docker compose up` and you're running |

## Quick Start

FrankenPHP is a self-contained application server, so you don't need a separate web server like Nginx. The easiest way to get started is with a `docker-compose.yml` file.

Here is an example serving a simple application:

```yaml
# docker-compose.yml
version: '3.8'

services:
  frankenphp:
    # Replace with your desired PHP version tag
    image: europe-docker.pkg.dev/PROJECT/sitespanel-images/frankenphp:8.4
    ports:
      - "80:80"      # HTTP
      - "443:443"    # HTTPS
      - "443:443/udp"# HTTP/3
    volumes:
      # Mount your application code
      - ./public:/app
      # Mount your custom Caddyfile
      - ./Caddyfile:/etc/caddy/Caddyfile
```

You must provide a `Caddyfile` to tell FrankenPHP how to serve your application. Create a `Caddyfile` in your project root:

```caddy
# Caddyfile
:80 {
    # Set the root to your app's public directory
    root * /app
    # Enable compression
    encode zstd gzip
    # Route all requests to the PHP server
    php_server
    # Serve static files if they exist
    file_server
}
```

Finally, create a `public/index.php` file and run `docker-compose up` to start the services.

## Available Versions

This project builds and maintains images for the following PHP versions:

*   **8.5** (Also tagged as `latest`)
*   **8.4**
*   **8.3**
*   **8.2**

### Tagging Strategy

Each image is tagged with multiple schemes for flexibility:

*   `europe-docker.pkg.dev/PROJECT/sitespanel-images/frankenphp:latest`: Always points to the most recent build of the PHP 8.5 image.
*   `europe-docker.pkg.dev/PROJECT/sitespanel-images/frankenphp:<version>` (e.g., `europe-docker.pkg.dev/PROJECT/sitespanel-images/frankenphp:8.4`): A convenient tag for a specific major version.
*   `europe-docker.pkg.dev/PROJECT/sitespanel-images/frankenphp:<version>-trixie` (e.g., `europe-docker.pkg.dev/PROJECT/sitespanel-images/frankenphp:8.4-trixie`): The same image with the base OS in the tag (Debian 13).

Every PHP version is built on Debian 13 (trixie) only. bookworm is built again only for a PHP version whose base image has no trixie variant. The old `-bookworm` tags stay in Artifact Registry but are no longer updated.

It is recommended to use a specific version tag (like `8.4-trixie`) in production environments for stability.

## Included Extensions & Utilities

These images come with a wide range of pre-installed components to minimize setup time.

### Custom Caddy Modules

The `frankenphp` binary is custom-compiled with the following additional Caddy modules:

*   **coraza** (v2.6.2): OWASP Coraza WAF — ModSecurity/SecLang compatible, with the OWASP Core
    Rule Set compiled into the binary. Use `load_owasp_crs` and the `@`-prefixed include
    paths; there are no rule files to download or mount. Requires `order coraza_waf first`
    in the global options.
*   **defender** (v0.10.1): IP-range blocking for AI crawlers, cloud provider ranges and custom
    CIDRs. Module path is the vanity import `pkg.jsn.cam/caddy-defender`.
*   **rate_limit** (v0.1.0): Sliding-window rate limiting, multiple zones, keyed on any request
    placeholder. Ordered before `basic_auth` by default.
*   **cbrotli** (v1.0.1): Brotli compression support.
*   **souin** (v1.7.9): HTTP Cache.
*   **DNS Challenge Providers**: `vultr`, `azure`, `googleclouddns`, `digitalocean`, `cloudflare`, `route53`.
*   **Souin Storage Providers** (v0.0.20): `go-redis`, `otter`, `simplefs`.

FrankenPHP is 1.13.0 on Caddy 2.11.7. Every module is pinned to an explicit version in the `Dockerfile`; the exact versions are listed in [EXTENSIONS.md](EXTENSIONS.md).

### PHP Extensions

**Every extension, Caddy module and tool, with its version and what it does, is listed in [EXTENSIONS.md](EXTENSIONS.md)**, including known issues (for example, `timezonedb` and `http` crash a configuration reload).

| Category         | Extensions                                                                    |
|------------------|-------------------------------------------------------------------------------|
| **Performance**  | `apcu`, `igbinary`, `memcached`, `opcache`, `redis`                             |
| **Asynchronous** | `pcntl`, `sockets`                                                |
| **Databases**    | `mongodb`, `mysqli`, `pdo_mysql`, `pdo_pgsql`, `pgsql`                                   |
| **Utilities**    | `bcmath`, `brotli`, `bz2`, `calendar`, `csv`, `ds`, `enchant`, `exif`, `ffi`, `ftp`, `gd`, `gettext`, `gmp`, `gnupg`, `http`, `imagick`, `inotify`, `intl`, `ldap`, `mailparse`, `mcrypt`, `oauth`, `pspell`, `shmop`, `soap`, `ssh2`, `tidy`, `timezonedb`, `uuid`, `xmlrpc`, `xsl`, `yaml`, `zip`, `zstd` |
| **Observability**| `opentelemetry`                                                                |

### Command-Line Utilities

*   **Composer**: The standard PHP dependency manager.
*   **WP-CLI**: The official command-line tool for WordPress.
*   **Node.js**: v24.x, for frontend asset compilation and other tasks.
*   **MariaDB client**: `mariadb`, `mariadb-dump` and the rest, also linked as `mysql` and `mysqldump`.
*   **Not included**: `supervisor` and `cron`; run workers and schedulers as separate containers.
*   **Other Tools**: `curl`, `gosu`, `unzip`, `zip`, `ffmpeg`.

## Configuration

*   The images use PHP's `php.ini-production`. The repository also carries a stricter example, [`php.ini.example`](php.ini.example), with `open_basedir` restrictions, disabled dangerous functions and tighter limits. It is not applied by default: copy it to `php.ini` and mount it (see the FAQ).
*   The server is configured by mounting a custom `Caddyfile` to `/etc/caddy/Caddyfile` inside the container.

## ❓ FAQ

**Q: Can I run custom php.ini configurations?**
A: Absolutely. You can mount your own `php.ini` file into the container (start from [`php.ini.example`](php.ini.example)):
```yaml
    volumes:
      - ./php.ini:/usr/local/etc/php/php.ini:ro
```

**Q: How do I add extensions not in your list?**
A: Since we use the `mlocati/php-extension-installer` utility, you can easily install any other extension via a custom `Dockerfile` layer:
```dockerfile
FROM europe-docker.pkg.dev/PROJECT/sitespanel-images/frankenphp:8.4
RUN install-php-extensions my-custom-extension
```

**Q: Why Node.js v24?**
A: We prioritize stability and long-term support. Node.js 24 is excellent for modern build tooling like Vite, Webpack, or TailwindCSS. You can customize the Node.js version at build time with the `NODE_VERSION` build arg.

**Q: How do I manage queues or background processes?**
A: Run them as separate containers from the same image with their own command; the images no longer include `supervisor` or `cron`.

**Q: How do I configure HTTPS with a custom domain?**
A: FrankenPHP's built-in Caddy server obtains TLS certificates automatically via Let's Encrypt. Specify your domain in the `Caddyfile` and ensure ports 80 and 443 are exposed.

---

---

## Related Images & Tools

<!-- BEGIN GENERATED: related (from images.yaml in the org .github repository; do not edit by hand) -->
Every image is built by Google Cloud Build and published to SitesPanel's Artifact Registry (`europe-docker.pkg.dev/PROJECT/sitespanel-images`), with SLSA provenance and an SBOM per image.

| Repository | Images | Description |
|---|---|---|
| [caddy-docker](https://github.com/sitespanel/caddy-docker) | `sitespanel-images/caddy` | Standalone Caddy with WAF, rate limiting & caching |
| [php-docker](https://github.com/sitespanel/php-docker) | `sitespanel-images/php` | Traditional PHP-FPM & CLI images |
| [nginx-docker](https://github.com/sitespanel/nginx-docker) | `sitespanel-images/nginx` | nginx with ModSecurity 3, Brotli, zstd & GeoIP2 |
| [apache-docker](https://github.com/sitespanel/apache-docker) | `sitespanel-images/apache` | Apache as a static server or php-fpm application server, no PHP inside |
<!-- END GENERATED: related -->

---

## Feedback and Issues

If you have suggestions, find a bug, or want to request a new extension, please [open an issue](https://github.com/sitespanel/frankenphp-docker/issues) on the GitHub repository.

---

⭐ **If this project helps you, consider giving it a star!**
