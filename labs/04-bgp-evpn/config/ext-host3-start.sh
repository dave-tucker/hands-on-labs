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

# P2P link to leaf3 VRF (leaf3 eth2: 10.0.5.0/31)
ip addr add 10.0.5.1/31 dev eth1

# Replace the clab management default route with the leaf3 VRF gateway.
# leaf3 handles L3VNI encapsulation for traffic toward cluster pods.
ip route del default 2>/dev/null || true
ip route add default via 10.0.5.0 dev eth1

# Simulated external host address — this is what cluster pods will ping.
# Leaf3 advertises 10.70.0.0/24 as a Type-5 EVPN route via a VRF static route.
ip link add lo-ext type dummy 2>/dev/null || true
ip link set lo-ext up
ip addr add 10.70.0.100/24 dev lo-ext

exec sleep infinity
