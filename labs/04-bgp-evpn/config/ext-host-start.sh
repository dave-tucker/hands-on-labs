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
  echo "ext-host-start.sh: eth1 not found after 30s" >&2
  exec sleep infinity
fi

ip link set lo up
ip link set eth1 up

# Create VTEP loopback interface
ip link add lo-vtep type dummy 2>/dev/null || true
ip link set lo-vtep up

# Create VXLAN interface
ip link add vxlan100 type vxlan \
  id 100 \
  local 100.64.0.13 \
  dstport 4789 \
  nolearning

ip link set vxlan100 up

# Create bridge
ip link add br-evpn type bridge
ip link set br-evpn up

# Add VXLAN to bridge
ip link set vxlan100 master br-evpn

# Add IP to bridge SVI
ip addr add 10.50.0.100/24 dev br-evpn

PATH="/usr/lib/frr:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
if command -v watchfrr >/dev/null 2>&1; then
  exec watchfrr -F traditional zebra bgpd bfdd staticd
elif [ -x /usr/lib/frr/watchfrr ]; then
  exec /usr/lib/frr/watchfrr -F traditional zebra bgpd bfdd staticd
elif [ -x /usr/libexec/frr/watchfrr ]; then
  exec /usr/libexec/frr/watchfrr -F traditional zebra bgpd bfdd staticd
else
  echo "ext-host-start.sh: watchfrr not found" >&2
  exec sleep infinity
fi
