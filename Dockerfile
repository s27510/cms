FROM php:8.3-apache
RUN apt-get update && apt-get install -y libpng-dev libjpeg-dev libwebp-dev libfreetype6-dev libzip-dev \
 && docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp \
 && docker-php-ext-install gd mysqli zip \
 && a2enmod rewrite
