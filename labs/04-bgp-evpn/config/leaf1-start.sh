#!/bin/sh
PATH=/usr/sbin:/usr/bin:/sbin:/bin:${PATH}
set -e

wait=0
while [ $wait -lt 30 ]; do
  if [ -d /sys/class/net/eth1 ] && [ -d /sys/class/net/eth2 ] && [ -d /sys/class/net/eth3 ] && [ -d /sys/class/net/eth4 ]; then
    break
  fi
  sleep 1
  wait=$((wait + 1))
done
if ! [ -d /sys/class/net/eth1 ] || ! [ -d /sys/class/net/eth2 ] || ! [ -d /sys/class/net/eth3 ] || ! [ -d /sys/class/net/eth4 ]; then
  echo "leaf1-start.sh: eth1-eth4 not all found after 30s" >&2
  exec sleep infinity
fi

ip link set lo up
ip link set eth1 up
ip link set eth2 up
ip link set eth3 up
ip link set eth4 up

# Create VTEP loopback
ip link add lo-vtep type dummy 2>/dev/null || true
ip link set lo-vtep up
ip addr add 100.64.0.11/32 dev lo-vtep 2>/dev/null || true

# Create VXLAN interface for VNI 100 (tenant 1)
ip link add vxlan100 type vxlan \
  id 100 \
  local 100.64.0.11 \
  dstport 4789 \
  nolearning

ip link set vxlan100 up

# Create bridge for VNI 100
ip link add br-vni100 type bridge
ip link set br-vni100 up

# Add VXLAN to bridge (eth4 is a routed P2P interface, not bridged)
ip link set vxlan100 master br-vni100

PATH="/usr/lib/frr:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
if command -v watchfrr >/dev/null 2>&1; then
  exec watchfrr -F traditional zebra bgpd bfdd staticd
elif [ -x /usr/lib/frr/watchfrr ]; then
  exec /usr/lib/frr/watchfrr -F traditional zebra bgpd bfdd staticd
elif [ -x /usr/libexec/frr/watchfrr ]; then
  exec /usr/libexec/frr/watchfrr -F traditional zebra bgpd bfdd staticd
else
  echo "leaf1-start.sh: watchfrr not found" >&2
  exec sleep infinity
fi
