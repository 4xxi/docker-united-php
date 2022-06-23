# the different stages of this Dockerfile are meant to be built into separate images
# https://docs.docker.com/develop/develop-images/multistage-build/#stop-at-a-specific-build-stage
# https://docs.docker.com/compose/compose-file/#target


# https://docs.docker.com/engine/reference/builder/#understand-how-arg-and-from-interact
ARG PHP_VERSION=8.1.7
ARG FULL_PHP_VERSION=8.1.7-alpine3.15
ARG OS_VERSION=alpine3.15
ARG CADDY_VERSION=2

# "php" stage
FROM php:${FULL_PHP_VERSION} AS united_php

# persistent / runtime deps
RUN apk add --no-cache \
		acl \
		fcgi \
		file \
		gettext \
    supervisor \
    caddy \
    su-exec \
		git \
		gnu-libiconv \
	;

# install gnu-libiconv and set LD_PRELOAD env to make iconv work fully on Alpine image.
# see https://github.com/docker-library/php/issues/240#issuecomment-763112749
ENV LD_PRELOAD /usr/lib/preloadable_libiconv.so

ARG APCU_VERSION=5.1.21
RUN set -eux; \
	apk add --no-cache --virtual .build-deps \
		$PHPIZE_DEPS \
		icu-dev \
		libzip-dev \
		zlib-dev \
	; \
	\
	docker-php-ext-configure zip; \
	docker-php-ext-install -j$(nproc) \
		intl \
		zip \
	; \
	pecl install \
		apcu-${APCU_VERSION} \
	; \
	pecl clear-cache; \
	docker-php-ext-enable \
		apcu \
		opcache \
	; \
	\
	runDeps="$( \
		scanelf --needed --nobanner --format '%n#p' --recursive /usr/local/lib/php/extensions \
			| tr ',' '\n' \
			| sort -u \
			| awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
	)"; \
	apk add --no-cache --virtual .api-phpexts-rundeps $runDeps; \
	\
	apk del .build-deps

###> recipes ###
###> doctrine/doctrine-bundle ###
# RUN apk add --no-cache --virtual .pgsql-deps postgresql-dev; \
# 	docker-php-ext-install -j$(nproc) pdo_pgsql; \
# 	apk add --no-cache --virtual .pgsql-rundeps so:libpq.so.5; \
# 	apk del .pgsql-deps
###< doctrine/doctrine-bundle ###
###< recipes ###

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

RUN ln -s $PHP_INI_DIR/php.ini-production $PHP_INI_DIR/php.ini
COPY config/php/conf.d/app.prod.ini $PHP_INI_DIR/conf.d/app.ini

COPY config/php/php-fpm.d/zz-docker.conf /usr/local/etc/php-fpm.d/zz-docker.conf
COPY script/docker-healthcheck.sh /usr/local/bin/docker-healthcheck

# "caddy" stage
ENV XDG_CONFIG_HOME=/usr/local/etc/caddy
RUN mkdir /usr/local/etc/caddy
COPY config/caddy/Caddyfile /usr/local/etc/caddy
RUN chown -R nobody:nobody /usr/local/etc/caddy

# "supervisor" stage
ENV SUPERVISOR_HOME=/usr/local/etc/supervisor
COPY --chown=nobody:nobody config/supervisor/supervisord.conf /usr/local/etc/supervisor/supervisord.conf

# "php" stage
RUN mkdir -p /var/run/php/
RUN chown -R nobody:nobody /var/run/php/

RUN chmod +x /usr/local/bin/docker-healthcheck
RUN adduser nobody tty

VOLUME /var/run/php

RUN  set -eux; \
  mkdir -p  /srv/app; \
  chown -R nobody:nobody /srv/app; \
  chown -R nobody:nobody $PHP_INI_DIR;

WORKDIR /srv/app

# https://getcomposer.org/doc/03-cli.md#composer-allow-superuser
ENV COMPOSER_ALLOW_SUPERUSER=0
ENV COMPOSER_HOME=/srv/app

FROM united_php as united_app

VOLUME /srv/app/var

HEALTHCHECK --interval=10s --timeout=3s --retries=3 CMD ["docker-healthcheck"]

CMD ["/usr/bin/supervisord", "-c", "/usr/local/etc/supervisor/supervisord.conf"]

FROM united_app as united_app_dev
RUN [ -e $PHP_INI_DIR/php.ini ] && unlink $PHP_INI_DIR/php.ini
RUN ln -s $PHP_INI_DIR/php.ini-development $PHP_INI_DIR/php.ini
COPY config/php/conf.d/app.dev.ini $PHP_INI_DIR/conf.d/app.ini

RUN set -eux; \
	apk add --no-cache --update \
		make\
		nano \
		bash \
	;
# Set the development environment as what you want
#COPY --chown=nobody:nobody fixtures fixtures
#COPY --chown=nobody:nobody Makefile Makefile
#ENV APP_ENV=dev
# RUN su-exec nobody composer install --prefer-dist --no-progress --no-interaction --
