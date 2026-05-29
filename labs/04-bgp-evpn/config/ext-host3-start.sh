#!/bin/sh
PATH=/usr/sbin:/usr/bin:/sbin:/bin:${PATH}
set -e

wait=0
while [ $wait -lt 30 ]; do
  if [ -d /sys/class/net/eth1 ]; then
    break
  fi
  sleep 1
  wait=$((wait + 1))
done
if ! [ -d /sys/class/net/eth1 ]; then
  echo "ext-host3-start.sh: eth1 not found after 30s" >&2
  exec sleep infinity
fi

ip link set lo up
ip link set eth1 up

# Create dummy interface for the subnet
ip link add lo-subnet type dummy 2>/dev/null || true
ip link set lo-subnet up

PATH="/usr/lib/frr:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
if command -v watchfrr >/dev/null 2>&1; then
  exec watchfrr -F traditional zebra bgpd bfdd staticd
elif [ -x /usr/lib/frr/watchfrr ]; then
  exec /usr/lib/frr/watchfrr -F traditional zebra bgpd bfdd staticd
elif [ -x /usr/libexec/frr/watchfrr ]; then
  exec /usr/libexec/frr/watchfrr -F traditional zebra bgpd bfdd staticd
else
  echo "ext-host3-start.sh: watchfrr not found" >&2
  exec sleep infinity
fi
