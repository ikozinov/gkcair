#!/bin/bash

# Allow ICMP for squid pinger
setcap cap_net_raw=ep /usr/libexec/pinger

# Setup the ssl_cert directory
if [ ! -d /etc/squid4/ssl_cert ]; then
    mkdir /etc/squid4/ssl_cert
fi

chown -R proxy:proxy /etc/squid4
chmod 700 /etc/squid4/ssl_cert

# Setup the squid cache directory
if [ ! -d /var/cache/squid4 ]; then
    mkdir -p /var/cache/squid4
fi
chown -R proxy: /var/cache/squid4
chmod -R 750 /var/cache/squid4

if [ ! -z $SSL_BUMP_PEEK_AND_SLICE ] || [ ! -z $MITM_PROXY ]; then
    if [ ! -z $SQUID_CA_CERT ]; then
        echo "Copying $SQUID_CA_CERT as CA cert..."
        cp $SQUID_CA_CERT /etc/squid4/ssl_cert/squidCA.pem
        chown root:proxy /etc/squid4/ssl_cert/squidCA.pem
    fi
    
    if [ -z $SQUID_CA_CERT ]; then
        echo "Must specify SQUID_CA_CERT variable in environment" 1>&2
        exit 1
       
    fi    
fi

chown proxy: /dev/stdout
chown proxy: /dev/stderr

# Initialize the certificates database
/usr/libexec/security_file_certgen -c -s /var/spool/squid4/ssl_db
chown -R proxy: /var/spool/squid4/ssl_db

# We using security_file_certgen instead of ssl_crtd 
#ssl_crtd -c -s
#ssl_db

# Set the configuration
if [ "$CONFIG_DISABLE" != "yes" ]; then
    p2 -t /squid.conf.p2 > /etc/squid4/squid.conf

    # Parse the cache peer lines from the environment and add them to the
    # configuration
    echo '# CACHE PEERS FROM DOCKER' >> /etc/squid4/squid.conf
    env | grep 'CACHE_PEER' | sort | while read cacheline; do
        echo "# $cacheline " >> /etc/squid4/squid.conf
        line=$(echo $cacheline | cut -d'=' -f2-)
        echo "cache_peer $line" >> /etc/squid4/squid.conf
    done

    # Parse the extra config lines and append them to the configuration
    echo '# EXTRA CONFIG FROM DOCKER' >> /etc/squid4/squid.conf
    env | grep 'EXTRA_CONFIG' | sort | while read extraline; do
        echo "# $extraline " >> /etc/squid4/squid.conf
        line=$(echo $extraline | cut -d'=' -f2-)
        echo "$line" >> /etc/squid4/squid.conf
    done
else
    echo "/etc/squid4/squid.conf: CONFIGURATION TEMPLATING IS DISABLED."
fi

if [ ! -e /etc/squid4/squid.conf ]; then
    echo "ERROR: /etc/squid4/squid.conf does not exist. Squid will not work."
    exit 1
fi

# Build the configuration directories if needed
squid -z -N

# Start squid normally
squid -N 2>&1 &
PID=$!

# This construct allows signals to kill the container successfully.
trap "kill -TERM $(jobs -p)" INT TERM
wait $PID
wait $PID
exit $?
