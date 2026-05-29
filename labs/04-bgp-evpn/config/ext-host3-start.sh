#!/bin/sh
# ext-host3: plain L3 host behind leaf3's VRF (host_l3 pattern).
# No FRR — leaf3 owns the VRF and generates the EVPN Type-5 for 10.70.0.0/24.
PATH=/usr/sbin:/usr/bin:/sbin:/bin:${PATH}

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

# Host IP on the shared /24 subnet — leaf3 eth2 (in VRF) is 10.70.0.1/24.
# leaf3 redistributes 10.70.0.0/24 as EVPN Type-5 via redistribute connected.
ip addr add 10.70.0.100/24 dev eth1

# Replace the clab management default route with the leaf3 VRF gateway.
ip route del default 2>/dev/null || true
ip route add default via 10.70.0.1 dev eth1

exec sleep infinity
