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
  echo "leaf3-start.sh: eth1-eth2 not found after 30s" >&2
  exec sleep infinity
fi

ip link set lo up
ip link set eth1 up
ip link set eth2 up

# VTEP loopback
ip link add lo-vtep type dummy 2>/dev/null || true
ip link set lo-vtep up
ip addr add 100.64.0.16/32 dev lo-vtep 2>/dev/null || true

# VRF for tenant-2 IP-VRF (L3VNI = 201)
ip link add tenant2-ipvrf type vrf table 10
ip link set tenant2-ipvrf up

# eth2 is the host-facing P2P leg — put it in the VRF (routed, not bridged)
ip link set eth2 master tenant2-ipvrf

# L3VNI VXLAN interface
ip link add vxlan201 type vxlan \
  id 201 \
  local 100.64.0.16 \
  dstport 4789 \
  nolearning

# Bridge for L3VNI (required for EVPN Type-5 advertisement)
ip link add br-l3vni201 type bridge
ip link set br-l3vni201 master tenant2-ipvrf
ip link set br-l3vni201 up
ip link set vxlan201 master br-l3vni201
ip link set vxlan201 up

PATH="/usr/lib/frr:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
if command -v watchfrr >/dev/null 2>&1; then
  exec watchfrr -F traditional zebra bgpd bfdd staticd
elif [ -x /usr/lib/frr/watchfrr ]; then
  exec /usr/lib/frr/watchfrr -F traditional zebra bgpd bfdd staticd
elif [ -x /usr/libexec/frr/watchfrr ]; then
  exec /usr/libexec/frr/watchfrr -F traditional zebra bgpd bfdd staticd
else
  echo "leaf3-start.sh: watchfrr not found" >&2
  exec sleep infinity
fi
