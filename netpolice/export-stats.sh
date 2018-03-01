#!/bin/sh

cd /usr/lib/python2.7/dist-packages/webadmin && /usr/local/bin/mantra "$EXPORT_STAT_CRON" /usr/bin/python manage.py export_statistics
