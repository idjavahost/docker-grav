FROM    php:7.2-fpm-alpine

LABEL	maintainer="Rizal Fauzie Ridwan <rizal@fauzie.my.id>"

ENV     VIRTUAL_HOST=$DOCKER_HOST \
        HOME=/var/www \
        TZ=Asia/Jakarta \
        PHP_MEMORY_LIMIT=128M \
        REAL_IP_FROM=172.17.0.0/16 \
        SSH_PORT=2222 \
        HTTPS=off \
        USERNAME=grav \
        USERGROUP=grav \
        DOCKERIZE_VERSION=0.6.1 \
        COMPOSER_VERSION=1.8.0 \
        ALPINE_MIRROR=mirrors.ustc.edu.cn

RUN     echo "http://${ALPINE_MIRROR}/alpine/v3.8/main" > /etc/apk/repositories && \
        echo "http://${ALPINE_MIRROR}/alpine/v3.8/community" >> /etc/apk/repositories && \
        apk add --update --no-cache openssh bash nano htop nginx supervisor nodejs \
        nginx-mod-http-fancyindex nginx-mod-http-headers-more wget git \
        curl libmcrypt libpng libjpeg-turbo icu-libs gettext libintl && \
        rm /etc/nginx/conf.d/*

RUN     apk add --virtual .build-deps freetype libxml2-dev libpng-dev libjpeg-turbo-dev libwebp-dev zlib-dev \
        gettext-dev icu-dev libxpm-dev libmcrypt-dev make gcc g++ autoconf && \
        docker-php-source extract && \
        echo no | pecl install redis && \
        docker-php-ext-enable redis && \
        docker-php-source delete && \
        docker-php-ext-configure opcache --enable-opcache && \
        docker-php-ext-configure gd --with-png-dir=/usr --with-jpeg-dir=/usr && \
        docker-php-ext-install -j$(nproc) gd intl gettext soap opcache zip

COPY    /files /

RUN     chmod +x /entrypoint.sh && \
        apk del .build-deps && \
        rm -rf /tmp/*

ENTRYPOINT /entrypoint.sh
