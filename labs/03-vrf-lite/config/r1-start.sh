#!/bin/sh
# Interfaces must be in kernel VRFs before FRR starts so Zebra discovers them.
# See https://docs.frrouting.org/en/stable-10.0/zebra.html#virtual-routing-and-forwarding
PATH=/usr/sbin:/usr/bin:/sbin:/bin:${PATH}
set -e

# Containerlab creates eth1-eth4 after the container starts
wait=0
while [ $wait -lt 30 ]; do
  if [ -d /sys/class/net/eth1 ] && [ -d /sys/class/net/eth2 ] && [ -d /sys/class/net/eth3 ] && [ -d /sys/class/net/eth4 ]; then
    break
  fi
  sleep 1
  wait=$((wait + 1))
done
if ! [ -d /sys/class/net/eth1 ] || ! [ -d /sys/class/net/eth2 ] || ! [ -d /sys/class/net/eth3 ] || ! [ -d /sys/class/net/eth4 ]; then
  echo "r1-start.sh: eth1-eth4 not all found after 30s" >&2
  exec sleep infinity
fi

ip link add name tenant1 type vrf table 1001
ip link set tenant1 up
ip link add name tenant2 type vrf table 1002
ip link set tenant2 up

# eth1/eth3 -> tenant1 (BGP + site2), eth2/eth4 -> tenant2
ip link set eth1 master tenant1
ip link set eth2 master tenant2
ip link set eth3 master tenant1
ip link set eth4 master tenant2
ip link set eth1 up
ip link set eth2 up
ip link set eth3 up
ip link set eth4 up

PATH="/usr/lib/frr:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
if command -v watchfrr >/dev/null 2>&1; then
  exec watchfrr -F traditional zebra bgpd staticd
elif [ -x /usr/lib/frr/watchfrr ]; then
  exec /usr/lib/frr/watchfrr -F traditional zebra bgpd staticd
elif [ -x /usr/libexec/frr/watchfrr ]; then
  exec /usr/libexec/frr/watchfrr -F traditional zebra bgpd staticd
else
  echo "r1-start.sh: watchfrr not found" >&2
  ls -la /usr/lib/frr /usr/libexec/frr 2>/dev/null || true
  exec sleep infinity
fi
