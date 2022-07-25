FROM php:8.1.8-fpm-bullseye@sha256:7f08aecb123611eeebe2035189cf84fb910f676e35f9adf4e21d063f2ce62c65 as fpm

# Set timezone to America/New_York
ENV TZ=America/New_York
ARG DD_TRACER_VERSION=0.70.0
ENV php_vars $PHP_INI_DIR/conf.d/docker-vars.ini

# renovate: datasource=github-releases depName=microsoft/msphpsql
ENV PHP_SQLSRV_VERSION 5.10.0

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime \
  && echo $TZ > /etc/timezone \
  && echo "date.timezone=\"$TZ\"" >> /usr/local/etc/php/conf.d/docker-vars.ini

RUN apt-get update && \
  apt-get install -y --no-install-recommends \
  libyaml-dev \
  libxml2-dev \
  gnupg \
  apt-transport-https \
  cron \
  gettext \
  libicu-dev \
  uuid-dev \
  wget \
  git \
  lsb-release \
  unzip && \
  curl -sL https://deb.nodesource.com/setup_12.x | bash - && \
  apt-get update && \
  apt-get install -y nodejs && \
  wget -O - https://packages.microsoft.com/keys/microsoft.asc | apt-key add -  && \
  wget -O /etc/apt/sources.list.d/mssql-release.list https://packages.microsoft.com/config/debian/$(lsb_release -rs)/prod.list  && \
  apt-get update && \
  ACCEPT_EULA=Y apt-get install -y --no-install-recommends \
  msodbcsql18=18.0.1.1-1 \
  mssql-tools18=18.0.1.1-1 \
  locales && \
  echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && \
  locale-gen && \
  rm -r /var/lib/apt/lists/*

COPY --from=composer:2.3.9@sha256:bce5a9b833a8b9cc21ecc66a39641cd6b7812b6d56eeef92108c470041d1ac79 /usr/bin/composer /usr/local/bin/composer

COPY deps/unixODBC-2.3.10.tar.gz .

RUN rm -f /usr/lib/x86_64-linux-gnu/libodbcinst.so* && \
  rm -f /usr/lib/x86_64-linux-gnu/libodbc.so* && \
  echo "3e8297d89e58fd236bcb5b95d1b8e51c unixODBC-2.3.10.tar.gz" | md5sum -c - && \
  tar -xzf unixODBC-2.3.10.tar.gz && \
  cd unixODBC-2.3.10 && \
  ./configure --prefix=/usr/local --libdir=/usr/local/lib --sysconfdir=/etc --disable-gui --disable-drivers --enable-iconv --with-iconv-char-enc=UTF8 --with-iconv-ucode-enc=UTF16LE && \
  make && \
  make install && \
  ldconfig

RUN cd /opt/microsoft/msodbcsql18/lib64/ && ln -sf libmsodbcsql-18.*.so.* libmsodbcsql-18.so

RUN docker-php-ext-install -j$(nproc) intl opcache soap

RUN pecl install sqlsrv-${PHP_SQLSRV_VERSION} pdo_sqlsrv-${PHP_SQLSRV_VERSION} apcu ds uuid yaml && \
  docker-php-ext-enable sqlsrv pdo_sqlsrv apcu ds uuid yaml 

RUN wget https://github.com/DataDog/dd-trace-php/releases/download/${DD_TRACER_VERSION}/datadog-php-tracer_${DD_TRACER_VERSION}_amd64.deb && \
    dpkg -i datadog-php-tracer_${DD_TRACER_VERSION}_amd64.deb && \
    rm datadog-php-tracer_${DD_TRACER_VERSION}_amd64.deb

COPY conf/odbcinst.ini /etc/odbcinst.ini

COPY src /usr/share/nginx/html
COPY conf/simplesamlphp /etc/simplesamlphp
COPY conf/fpm/zzz-docker.conf /usr/local/etc/php-fpm.d/zzz-docker.conf
RUN mv $PHP_INI_DIR/php.ini-production $PHP_INI_DIR/php.ini && \
  echo "opcache.enable=1" >> ${php_vars} && \
  echo "opcache.jit_buffer_size=100M" >> ${php_vars} && \
  echo "opcache.jit=disable" >> ${php_vars}

COPY scripts ./scripts
COPY ./wait-for-db.sh .
COPY ./entrypoint-fpm.sh .

ENTRYPOINT [ "./entrypoint-fpm.sh" ]
CMD ["php-fpm"]

# FROM fpm as debug

# # xdebug configuration
# RUN pecl install xdebug && docker-php-ext-enable xdebug \
#   && echo "xdebug.remote_port=9009" >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini \
#   && echo "xdebug.remote_enable=1" >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini \
#   && echo "xdebug.remote_connect_back=0" >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini \
#   && echo "xdebug.remote_host=host.docker.internal" >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini \
#   && echo "xdebug.idekey=VSCODE" >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini \
#   && echo "xdebug.remote_autostart=1" >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini \
#   && echo "xdebug.remote_log=/tmp/xdebug.log" >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini
