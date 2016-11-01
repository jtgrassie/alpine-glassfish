FROM alpine:latest
MAINTAINER jethro.grassie@edelman.com

# Based on https://github.com/pagespeed/ngx_pagespeed/issues/1181#issuecomment-250776751
# Secret Google tarball releases of mod_pagespeed from here https://github.com/pagespeed/mod_pagespeed/issues/968
# Extended to add Glassfish 4.1 & MySQL Connector/J

# Set versions as environment variables so that they can be inspected later
ENV LIBPNG_VERSION=1.2.56 \
    # mod_pagespeed requires an old version of http://www.libpng.org/pub/png/libpng.html
    PAGESPEED_VERSION=1.11.33.4 \
    # Check https://github.com/pagespeed/ngx_pagespeed/releases for the latest version
    NGINX_VERSION=1.11.5 \
    # Check http://nginx.org/en/download.html for the latest version
    JAVA_HOME=/usr/lib/jvm/default-jvm \
    PATH=$PATH:$JAVA_HOME/bin \
    MYSQL_CONNECTOR_URL=https://dev.mysql.com/get/Downloads/Connector-J/mysql-connector-java-5.1.40.tar.gz \
    MYSQL_CONNECTOR_PKG=mysql-connector-java-5.1.40.tar.gz \
    MARIADB_CONNECTOR_URL=http://central.maven.org/maven2/org/mariadb/jdbc/mariadb-java-client/1.5.4/mariadb-java-client-1.5.4.jar \
    MARIADB_CONNECTOR_PKG=mariadb-java-client-1.5.4.jar \
    GLASSFISH_PKG=glassfish-4.1.1.zip \
    GLASSFISH_URL=http://download.oracle.com/glassfish/4.1.1/release/glassfish-4.1.1.zip \
    GLASSFISH_HOME=/glassfish4 \
    PATH=$PATH:/glassfish4/bin \
    PASSWORD=glassfish

# Add dependencies
RUN apk --no-cache add \
        ca-certificates \
        libuuid \
        apr \
        apr-util \
        libjpeg-turbo \
        icu \
        icu-libs \
        openssl \
        pcre \
        zlib \
        nfs-utils

# Install required packages such as OpenJDK 8 and the CA Certificates for SSL support in the JVM
# Configure certificates in JDK trust store
RUN apk add --update ca-certificates && \
    apk add --update --repository http://dl-4.alpinelinux.org/alpine/edge/community/ openjdk8 && \
    find /usr/share/ca-certificates/mozilla/ -name *.crt -exec keytool -import -trustcacerts -keystore $JAVA_HOME/jre/lib/security/cacerts -storepass changeit -noprompt -file {} -alias {} \; && \
    keytool -list -keystore $JAVA_HOME/jre/lib/security/cacerts --storepass changeit

# Install packages, download and extract GlassFish
# Setup password file
# Enable DAS
# Add MySQL Connector to domain1
RUN apk add --update wget unzip tar && \
    wget --no-check-certificate $GLASSFISH_URL && \
    unzip -o $GLASSFISH_PKG && \
    rm -f $GLASSFISH_PKG && \
    wget --no-check-certificate $MYSQL_CONNECTOR_URL && \
    wget --no-check-certificate $MARIADB_CONNECTOR_URL && \
    apk del wget unzip && \
    echo "--- Setup the password file ---" && \
    echo "AS_ADMIN_PASSWORD=" > /tmp/glassfishpwd && \
    echo "AS_ADMIN_NEWPASSWORD=${PASSWORD}" >> /tmp/glassfishpwd  && \
    echo "--- Enable DAS, change admin password, and secure admin access ---" && \
    asadmin --user=admin --passwordfile=/tmp/glassfishpwd change-admin-password --domain_name domain1 && \
    asadmin start-domain && \
    echo "AS_ADMIN_PASSWORD=${PASSWORD}" > /tmp/glassfishpwd && \
    asadmin --user=admin --passwordfile=/tmp/glassfishpwd enable-secure-admin && \
    asadmin --user=admin --passwordfile=/tmp/glassfishpwd set server.admin-service.das-config.autodeploy-enabled=false && \
    asadmin --user=admin --passwordfile=/tmp/glassfishpwd set server.admin-service.das-config.dynamic-reload-enabled=false && \
    asadmin --user=admin stop-domain && \
    rm /tmp/glassfishpwd && \
    tar --strip-components 1 -C $GLASSFISH_HOME/glassfish/domains/domain1/lib -xzf $MYSQL_CONNECTOR_PKG mysql-connector-java-5.1.40/mysql-connector-java-5.1.40-bin.jar && \
    cp $MARIADB_CONNECTOR_PKG $GLASSFISH_HOME/glassfish/domains/domain1/lib/ && \
    rm $MYSQL_CONNECTOR_PKG && \
    rm $MARIADB_CONNECTOR_PKG


RUN mkdir /app \
    && /usr/sbin/addgroup -g 1000 app \
    && /usr/sbin/adduser -D -H -h /app -u 1000 -G app app \
    && /bin/chown -R app:app /app

# Add build dependencies
# and build mod_pagespeed from source for Alpine for Nginx with ngx_pagespeed
RUN set -x && \
    apk --no-cache add -t .build-deps \
        apache2-dev \
        apr-dev \
        apr-util-dev \
        build-base \
        curl \
        icu-dev \
        libjpeg-turbo-dev \
        linux-headers \
        gperf \
        openssl-dev \
        pcre-dev \
        python \
        zlib-dev && \
    # Build libpng
    cd /tmp && \
    curl -L http://prdownloads.sourceforge.net/libpng/libpng-${LIBPNG_VERSION}.tar.gz | tar -zx && \
    cd /tmp/libpng-${LIBPNG_VERSION} && \
    ./configure --build=$CBUILD --host=$CHOST --prefix=/usr --enable-shared --with-libpng-compat && \
    make install V=0 && \
    # Build PageSpeed
    cd /tmp && \
    curl -L https://dl.google.com/dl/linux/mod-pagespeed/tar/beta/mod-pagespeed-beta-${PAGESPEED_VERSION}-r0.tar.bz2 | tar -jx && \
    curl -L https://github.com/pagespeed/ngx_pagespeed/archive/v${PAGESPEED_VERSION}-beta.tar.gz | tar -zx && \
    cd /tmp/modpagespeed-${PAGESPEED_VERSION} && \
    curl -L https://raw.githubusercontent.com/wunderkraut/alpine-nginx-pagespeed/master/patches/automatic_makefile.patch | patch -p1 && \
    curl -L https://raw.githubusercontent.com/wunderkraut/alpine-nginx-pagespeed/master/patches/libpng_cflags.patch | patch -p1 && \
    curl -L https://raw.githubusercontent.com/wunderkraut/alpine-nginx-pagespeed/master/patches/pthread_nonrecursive_np.patch | patch -p1 && \
    curl -L https://raw.githubusercontent.com/wunderkraut/alpine-nginx-pagespeed/master/patches/rename_c_symbols.patch | patch -p1 && \
    curl -L https://raw.githubusercontent.com/wunderkraut/alpine-nginx-pagespeed/master/patches/stack_trace_posix.patch | patch -p1 && \
    ./generate.sh -D use_system_libs=1 -D _GLIBCXX_USE_CXX11_ABI=0 -D use_system_icu=1 && \
    cd /tmp/modpagespeed-${PAGESPEED_VERSION}/src && \
    make BUILDTYPE=Release CXXFLAGS=" -I/usr/include/apr-1 -I/tmp/libpng-${LIBPNG_VERSION} -fPIC -D_GLIBCXX_USE_CXX11_ABI=0" CFLAGS=" -I/usr/include/apr-1 -I/tmp/libpng-${LIBPNG_VERSION} -fPIC -D_GLIBCXX_USE_CXX11_ABI=0" && \
    cd /tmp/modpagespeed-${PAGESPEED_VERSION}/src/pagespeed/automatic/ && \
    make psol BUILDTYPE=Release CXXFLAGS=" -I/usr/include/apr-1 -I/tmp/libpng-${LIBPNG_VERSION} -fPIC -D_GLIBCXX_USE_CXX11_ABI=0" CFLAGS=" -I/usr/include/apr-1 -I/tmp/libpng-${LIBPNG_VERSION} -fPIC -D_GLIBCXX_USE_CXX11_ABI=0" && \
    mkdir -p /tmp/ngx_pagespeed-${PAGESPEED_VERSION}-beta/psol && \
    mkdir -p /tmp/ngx_pagespeed-${PAGESPEED_VERSION}-beta/psol/lib/Release/linux/x64 && \
    mkdir -p /tmp/ngx_pagespeed-${PAGESPEED_VERSION}-beta/psol/include/out/Release && \
    cp -r /tmp/modpagespeed-${PAGESPEED_VERSION}/src/out/Release/obj /tmp/ngx_pagespeed-${PAGESPEED_VERSION}-beta/psol/include/out/Release/ && \
    cp -r /tmp/modpagespeed-${PAGESPEED_VERSION}/src/net /tmp/ngx_pagespeed-${PAGESPEED_VERSION}-beta/psol/include/ && \
    cp -r /tmp/modpagespeed-${PAGESPEED_VERSION}/src/testing /tmp/ngx_pagespeed-${PAGESPEED_VERSION}-beta/psol/include/ && \
    cp -r /tmp/modpagespeed-${PAGESPEED_VERSION}/src/pagespeed /tmp/ngx_pagespeed-${PAGESPEED_VERSION}-beta/psol/include/ && \
    cp -r /tmp/modpagespeed-${PAGESPEED_VERSION}/src/third_party /tmp/ngx_pagespeed-${PAGESPEED_VERSION}-beta/psol/include/ && \
    cp -r /tmp/modpagespeed-${PAGESPEED_VERSION}/src/tools /tmp/ngx_pagespeed-${PAGESPEED_VERSION}-beta/psol/include/ && \
    cp -r /tmp/modpagespeed-${PAGESPEED_VERSION}/src/url /tmp/ngx_pagespeed-${PAGESPEED_VERSION}-beta/psol/include/ && \
    cp -r /tmp/modpagespeed-${PAGESPEED_VERSION}/src/pagespeed/automatic/pagespeed_automatic.a /tmp/ngx_pagespeed-${PAGESPEED_VERSION}-beta/psol/lib/Release/linux/x64 && \
    # Build Nginx with support for PageSpeed
    cd /tmp && \
    curl -L http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz | tar -zx && \
    cd /tmp/nginx-${NGINX_VERSION} && \
    LD_LIBRARY_PATH=/tmp/modpagespeed-${PAGESPEED_VERSION}/usr/lib ./configure \
        --sbin-path=/usr/sbin \
        --modules-path=/usr/lib/nginx \
        --with-http_ssl_module \
        --with-http_gzip_static_module \
        --with-file-aio \
        --with-http_v2_module \
        --with-http_stub_status_module \
        --without-http_autoindex_module \
        --without-http_browser_module \
        --without-http_geo_module \
        --without-http_map_module \
        --without-http_memcached_module \
        --without-http_userid_module \
        --without-mail_pop3_module \
        --without-mail_imap_module \
        --without-mail_smtp_module \
        --without-http_split_clients_module \
        --without-http_scgi_module \
        --without-http_referer_module \
        --without-http_upstream_ip_hash_module \
        --prefix=/etc/nginx \
        --conf-path=/etc/nginx/nginx.conf \
        --http-log-path=/var/log/nginx/access.log \
        --error-log-path=/var/log/nginx/error.log \
        --pid-path=/var/run/nginx.pid \
        --add-module=/tmp/ngx_pagespeed-${PAGESPEED_VERSION}-beta \
        --with-cc-opt="-fPIC -I /usr/include/apr-1" \
        --with-ld-opt="-luuid -lapr-1 -laprutil-1 -licudata -licuuc -L/tmp/modpagespeed-${PAGESPEED_VERSION}/usr/lib -lpng12 -lturbojpeg -ljpeg" && \
    make install --silent && \
    # Clean-up
    cd && \
    apk del .build-deps && \
    rm -rf /tmp/* && \
    # Forward request and error logs to docker log collector
    ln -sf /dev/stdout /var/log/nginx/access.log && \
    ln -sf /dev/stderr /var/log/nginx/error.log && \
    # Make PageSpeed cache writable
    mkdir -p /var/cache/ngx_pagespeed && \
    chmod -R o+wr /var/cache/ngx_pagespeed

# Make our nginx.conf available on the container
ADD conf/nginx.conf /etc/nginx/nginx.conf

# Add script to use to start nginx & glassfish
ADD conf/startup.sh /usr/bin/startup.sh
RUN chmod +x /usr/bin/startup.sh

VOLUME ["/var/log/nginx"]

# Little impact in this image
WORKDIR /app

EXPOSE 80 443 4848

## Start glassfish and nginx
ENTRYPOINT ["/usr/bin/startup.sh"]

