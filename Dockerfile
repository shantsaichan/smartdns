FROM debian:latest as smartdns-builder
LABEL previous-stage=smartdns-builder

# prepare builder
ARG OPENSSL_VER=3.0.10
RUN apt update && \
    apt install -y perl curl make musl-tools musl-dev && \
    ln -s /usr/include/linux /usr/include/$(uname -m)-linux-musl && \
    ln -s /usr/include/asm-generic /usr/include/$(uname -m)-linux-musl && \
    ln -s /usr/include/$(uname -m)-linux-gnu/asm /usr/include/$(uname -m)-linux-musl && \
    \
    mkdir -p /build/openssl && \
    cd /build/openssl && \
    curl -sSL https://www.openssl.org/source/openssl-${OPENSSL_VER}.tar.gz | tar --strip-components=1 -zxv && \
    \
    export CC="musl-gcc -static -idirafter /usr/include/ -idirafter /usr/include/$(uname -m)-linux-gnu" && \
    export OPENSSL_OPTIONS="no-tests no-ssl3 no-weak-ssl-ciphers no-shared no-idea -DOPENSSL_NO_SECURE_MEMORY" && \
    if [ "$(uname -m)" = "aarch64" ]; then \
        ./config --prefix=/opt/build $OPENSSL_OPTIONS -mno-outline-atomics; \
    else \ 
        ./config --prefix=/opt/build $OPENSSL_OPTIONS; \
    fi && \
    make all -j8 && make install_sw && \
    cd / && rm -rf /build

# do make
COPY . /build/smartdns/
RUN cd /build/smartdns && \
    export CC=musl-gcc && \
    export EXTRA_CFLAGS="-I /opt/build/include" && \
    export LDFLAGS="-L /opt/build/lib -L /opt/build/lib64" && \
    export NOUNWIND=1 && \
    sh ./package/build-pkg.sh --platform linux --arch `dpkg --print-architecture` --static && \
    \
    ( cd package && tar -xvf *.tar.gz && chmod a+x smartdns/etc/init.d/smartdns ) && \
    \
    mkdir -p /release/var/log /release/run && \
    cp package/smartdns/etc /release/ -a && \
    cp package/smartdns/usr /release/ -a && \
    cd / && rm -rf /build

FROM busybox:stable-musl
COPY --from=smartdns-builder /release/ /
EXPOSE 53/udp
VOLUME ["/etc/smartdns/"]

CMD ["/usr/sbin/smartdns", "-f", "-x"]
