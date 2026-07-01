#!/bin/sh
set -e

# Named Docker volumes are created as root; cdk-erigon runs as the erigon user (UID 1000).
if ! su -s /bin/sh erigon -c 'test -w /data' 2>/dev/null; then
  chown -R erigon:erigon /data
fi

# BusyBox su (Alpine) requires all args inside -c; it cannot accept "$@" after USER.
cmd="exec cdk-erigon"
for arg in "$@"; do
  cmd="$cmd $arg"
done

exec su -s /bin/sh erigon -c "$cmd"
