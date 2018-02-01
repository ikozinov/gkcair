#!/bin/sh

chown root:www-data /var/lib/netpolice && chmod g+rw /var/lib/netpolice
/etc/init.d/memcached start && \
/etc/init.d/pdns start && \
/etc/init.d/netpolice-c-icap start && \
/etc/init.d/apache2 start && \
tail -f /var/log/memcached.log /var/log/netpolice/stat.log /var/log/c-icap/access.log /var/log/c-icap/server.log
