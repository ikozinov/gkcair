FROM ubuntu:xenial

ARG TRUST_CERT=

RUN if [ ! -z "$TRUST_CERT" ]; then \
        echo "$TRUST_CERT" > /usr/local/share/ca-certificates/build-trust.crt ; \
        update-ca-certificates ; \
    fi

# Normalize apt sources
RUN cat /etc/apt/sources.list | grep -v '^#' | sed /^$/d | sort | uniq > sources.tmp.1 && \
    cat /etc/apt/sources.list | sed s/deb\ /deb-src\ /g | grep -v '^#' | sed /^$/d | sort | uniq > sources.tmp.2 && \
    cat sources.tmp.1 sources.tmp.2 > /etc/apt/sources.list && \
    rm -f sources.tmp.1 sources.tmp.2

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get build-dep -y squid && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y wget tar xz-utils libssl-dev

ARG SQUID_VERSION=4.0.21

# TODO: verify the squid download with the signing key
RUN mkdir /src \
    && cd /src \
    && wget http://www.squid-cache.org/Versions/v4/squid-$SQUID_VERSION.tar.xz \
    && mkdir squid \
    && tar -C squid --strip-components=1 -xvf squid-$SQUID_VERSION.tar.xz
    
RUN cd /src/squid && \
    ./configure \
        --prefix=/usr \
        --datadir=/usr/share/squid4 \
		--sysconfdir=/etc/squid4 \
		--localstatedir=/var \
		--mandir=/usr/share/man \
		--enable-inline \
		--enable-async-io=8 \
		--enable-storeio="ufs,aufs,diskd,rock" \
		--enable-removal-policies="lru,heap" \
		--enable-delay-pools \
		--enable-cache-digests \
		--enable-underscores \
		--enable-icap-client \
		--enable-follow-x-forwarded-for \
		--enable-auth-basic="DB,fake,getpwnam,LDAP,NCSA,NIS,PAM,POP3,RADIUS,SASL,SMB" \
		--enable-auth-digest="file,LDAP" \
		--enable-auth-negotiate="kerberos,wrapper" \
		--enable-auth-ntlm="fake" \
		--enable-external-acl-helpers="file_userip,kerberos_ldap_group,LDAP_group,session,SQL_session,unix_group,wbinfo_group" \
		--enable-url-rewrite-helpers="fake" \
		--enable-eui \
		--enable-esi \
		--enable-icmp \
		--enable-zph-qos \
		--with-openssl \
		--enable-ssl \
		--enable-ssl-crtd \ 
		--disable-translation \
		--with-swapdir=/var/spool/squid4 \
		--with-logdir=/var/log/squid4 \
		--with-pidfile=/var/run/squid4.pid \
		--with-filedescriptors=65536 \
		--with-large-files \
		--with-default-user=proxy \
        	--disable-arch-native
		
ARG CONCURRENCY=1

RUN cd /src/squid && \
    make -j$CONCURRENCY && \
    make install

# Download p2cli dependency
RUN wget -O /usr/local/bin/p2 \
    https://github.com/wrouesnel/p2cli/releases/download/r1/p2 && \
    chmod +x /usr/local/bin/p2

COPY squid.conf.p2 /squid.conf.p2
COPY entrypoint.sh /entrypoint.sh

# Configuration environment
ENV HTTP_PORT=3128 \
    ICP_PORT= \
    HTCP_PORT= \
    MITM_PROXY= \
    VISIBLE_HOSTNAME=docker-squid4 \
    MAX_CACHE_SIZE=40000 \
    MAX_OBJECT_SIZE="1536 MB" \
    MEM_CACHE_SIZE="128 MB" \
    DNS_SERVER="127.0.0.1" \
    NETPOLICE_PROXY=yes \
    NETPOLICE_ICAP_ADDR="127.0.0.1" \
    PLAIN_PROXY=yes \
    SSL_BUMP_PEEK_AND_SLICE= \
    HTTP_TRANSPARENT_PORT= \
    HTTPS_TRANSPARENT_PORT=

EXPOSE 3128 3129 3130

ENTRYPOINT [ "/entrypoint.sh" ]
