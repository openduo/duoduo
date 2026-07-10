#!/bin/bash
# Refresh channel map + fill empty descriptors.
# Run via cron every 5 minutes:
#   */5 * * * * cd ~/ENG/openduo/openduo && bash scripts/sync-channels.sh >> /tmp/sync-channels.log 2>&1

cd ~/ENG/openduo/openduo

python3 scripts/refresh-channel-map.py
python3 scripts/fill-empty-descriptors.py
