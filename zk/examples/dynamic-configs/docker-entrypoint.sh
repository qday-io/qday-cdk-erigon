#!/bin/sh
set -e

# Named Docker volumes are created as root; cdk-erigon runs as the erigon user (UID 1000).
if ! su -s /bin/sh erigon -c 'test -w /data' 2>/dev/null; then
  chown -R erigon:erigon /data
fi

exec su -s /bin/sh erigon -c 'exec cdk-erigon "$@"' sh "$@"
