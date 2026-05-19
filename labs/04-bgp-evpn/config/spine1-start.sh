#!/bin/sh
PATH=/usr/sbin:/usr/bin:/sbin:/bin:${PATH}
set -e

wait=0
while [ $wait -lt 30 ]; do
  if [ -d /sys/class/net/eth1 ] && [ -d /sys/class/net/eth2 ]; then
    break
  fi
  sleep 1
  wait=$((wait + 1))
done
if ! [ -d /sys/class/net/eth1 ] || ! [ -d /sys/class/net/eth2 ]; then
  echo "spine1-start.sh: eth1-eth2 not all found after 30s" >&2
  exec sleep infinity
fi

ip link set lo up
ip link set eth1 up
ip link set eth2 up
ip link set eth3 up 2>/dev/null || true

# Create VTEP loopback
ip link add lo-vtep type dummy 2>/dev/null || true
ip link set lo-vtep up
ip addr add 100.64.0.10/32 dev lo-vtep 2>/dev/null || true

# Create VRF for IP-VRF 201
ip link add tenant2-ipvrf type vrf table 10
ip link set tenant2-ipvrf up

# Create L3VNI VXLAN interface
ip link add vxlan201 type vxlan \
  id 201 \
  local 100.64.0.10 \
  dstport 4789 \
  nolearning

ip link set vxlan201 master tenant2-ipvrf
ip link set vxlan201 up

PATH="/usr/lib/frr:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
if command -v watchfrr >/dev/null 2>&1; then
  exec watchfrr -F traditional zebra bgpd bfdd staticd
elif [ -x /usr/lib/frr/watchfrr ]; then
  exec /usr/lib/frr/watchfrr -F traditional zebra bgpd bfdd staticd
elif [ -x /usr/libexec/frr/watchfrr ]; then
  exec /usr/libexec/frr/watchfrr -F traditional zebra bgpd bfdd staticd
else
  echo "spine1-start.sh: watchfrr not found" >&2
  exec sleep infinity
fi
