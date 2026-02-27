#!/bin/sh
PATH=/usr/sbin:/usr/bin:/sbin:/bin:${PATH}
set -e

wait=0
while [ $wait -lt 30 ]; do
  if [ -d /sys/class/net/eth1 ] && [ -d /sys/class/net/eth2 ] && [ -d /sys/class/net/eth3 ]; then
    break
  fi
  sleep 1
  wait=$((wait + 1))
done
if ! [ -d /sys/class/net/eth1 ] || ! [ -d /sys/class/net/eth2 ] || ! [ -d /sys/class/net/eth3 ]; then
  echo "r1-start.sh: eth1-eth3 not all found after 30s" >&2
  exec sleep infinity
fi

ip link set eth1 up
ip link set eth2 up
ip link set eth3 up

PATH="/usr/lib/frr:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
if command -v watchfrr >/dev/null 2>&1; then
  exec watchfrr -F traditional zebra staticd
elif [ -x /usr/lib/frr/watchfrr ]; then
  exec /usr/lib/frr/watchfrr -F traditional zebra staticd
elif [ -x /usr/libexec/frr/watchfrr ]; then
  exec /usr/libexec/frr/watchfrr -F traditional zebra staticd
else
  echo "r1-start.sh: watchfrr not found" >&2
  ls -la /usr/lib/frr /usr/libexec/frr 2>/dev/null || true
  exec sleep infinity
fi
