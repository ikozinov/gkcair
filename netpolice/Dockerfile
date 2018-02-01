FROM ubuntu:12.04

WORKDIR /root
#wget --quiet http://repo.netpolice.ru/ubuntu/Release.key -O - | apt-key add - && \


RUN locale-gen en_US.UTF-8; locale-gen ru_RU.UTF-8;  export LANGUAGE=ru_RU.UTF-8; export LANG=ru_RU.UTF-8; export LC_ALL=ru_RU.UTF-8; DEBIAN_FRONTEND=noninteractive dpkg-reconfigure locales

ENV LANG=ru_RU.UTF-8 \
    LANGUAGE=ru_RU:ru \
    LC_ALL=ru_RU.UTF-8

RUN echo 'Acquire::ForceIPv4 "true";' > /etc/apt/apt.conf.d/99force-ipv4 && \
echo deb http://repo.netpolice.ru/ubuntu/ / > /etc/apt/sources.list.d/netpolice.list && \
apt-get update && apt-get install -y --force-yes mc busybox net-tools \
netpolice-main

RUN a2dissite default && echo "NameVirtualHost 127.0.0.1:9000" > /etc/apache2/ports.conf && \
echo "Listen 127.0.0.1:9000" >> /etc/apache2/ports.conf && \
cp /etc/powerdns/netpolice-pdns.conf /etc/powerdns/pdns.conf && \
cp /etc/squid3/netpolice-squid.conf /etc/squid3/squid.conf

COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
