ARG PHP_VERSION=8.1

FROM 4xxi/united-php:${PHP_VERSION} as symfony_base

###> recipes ###
###> doctrine/doctrine-bundle ###
# RUN apk add --no-cache --virtual .pgsql-deps postgresql-dev; \
# 	docker-php-ext-install -j$(nproc) pdo_pgsql; \
# 	apk add --no-cache --virtual .pgsql-rundeps so:libpq.so.5; \
# 	apk del .pgsql-deps
###< doctrine/doctrine-bundle ###
###< recipes ###

# build for production
ARG APP_ENV=prod
ENV APP_ENV $APP_ENV

FROM symfony_base as symfony_app_deps
# build for production
ARG APP_ENV=prod
ENV APP_ENV $APP_ENV
# prevent the reinstallation of vendors at every changes in the source code
COPY --chown=nobody:nobody composer.json composer.lock symfony.lock ./
RUN  set -eux; \
	su-exec nobody composer install --prefer-dist --no-dev --no-scripts --no-progress; \
	su-exec nobody composer clear-cache

FROM symfony_base as symfony_app

ARG APP_ENV=prod
ENV APP_ENV $APP_ENV

COPY --chown=nobody:nobody --from=symfony_app_deps /srv/app/vendor ./vendor

# copy only specifically what we need
COPY --chown=nobody:nobody composer.json composer.lock symfony.lock ./
COPY --chown=nobody:nobody .env ./
COPY --chown=nobody:nobody bin bin/
COPY --chown=nobody:nobody config config/
COPY --chown=nobody:nobody migrations migrations/
COPY --chown=nobody:nobody public public/
COPY --chown=nobody:nobody src src/
COPY --chown=nobody:nobody templates templates/
COPY --chown=nobody:nobody data data/

RUN set -eux; \
	su-exec nobody mkdir -p var/cache var/log; \
	su-exec nobody composer dump-autoload --classmap-authoritative --no-dev; \
	su-exec nobody composer run-script --no-dev post-install-cmd; \
	su-exec nobody chmod +x bin/console; sync
