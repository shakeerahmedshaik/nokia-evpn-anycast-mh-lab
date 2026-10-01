#!/usr/bin/env bash
# Walks through the anycast MH evidence chain on the lab, step by step.
# Usage: ./scripts/verify.sh [step]   (step = underlay|es|routes|forwarding|traffic|all; default all)
set -uo pipefail

LAB=anycast-mh
ESI=00:11:11:11:11:11:11:00:00:01

srl() {
    local node=$1; shift
    printf '\n\033[1;36m[%s]\033[0m %s\n' "$node" "$*"
    docker exec "clab-${LAB}-${node}" sr_cli -d "$*"
}

host() {
    local node=$1; shift
    printf '\n\033[1;33m[%s]\033[0m %s\n' "$node" "$*"
    docker exec "clab-${LAB}-${node}" sh -c "$*"
}

step_underlay() {
    echo "=== 1. Underlay: anycast /32 learned on leaf3 with 2-way ECMP (spine1 + spine2) ==="
    srl leaf3 "show network-instance default protocols bgp neighbor"
    srl leaf3 "show network-instance default protocols bgp routes ipv4 prefix 12.12.12.12/32"
    srl spine1 "show network-instance default protocols bgp routes ipv4 prefix 12.12.12.12/32"
}

step_es() {
    echo "=== 2. Egress PEs: ES-1 is all-active + anycast, preference DF ==="
    srl leaf1 "show system network-instance ethernet-segments ES-1 detail"
    srl leaf2 "show system network-instance ethernet-segments ES-1 detail"
    srl leaf1 "show interface lag1 detail"
}

step_routes() {
    echo "=== 3. Control plane on ingress leaf3 ==="
    echo "Expect: RT-1 per-ES (Tag 4294967295) from leaf1 + leaf2 with esi-label .../All-Active/Anycast"
    echo "Expect: ZERO RT-1 per-EVI (Tag 0) routes for this ESI -- they are suppressed"
    srl leaf3 "show network-instance default protocols bgp routes evpn route-type 1 summary"
    srl leaf3 "show network-instance default protocols bgp routes evpn route-type 1 esi ${ESI} detail"
    echo "Expect: RT-2 for ts1's MAC carries ESI ${ESI}"
    srl leaf3 "show network-instance default protocols bgp routes evpn route-type 2 summary"
}

step_forwarding() {
    echo "=== 4. Forwarding on leaf3: ts1 MAC -> ES destination resolved to the anycast VTEP ==="
    srl leaf3 "show network-instance mac-vrf-100 bridge-table mac-table all"
    srl leaf3 "show tunnel-interface vxlan1 vxlan-interface 100 bridge-table unicast-destinations destination"
    srl leaf3 "show tunnel-interface vxlan1 vxlan-interface 100 bridge-table multicast-destinations destination"
}

step_traffic() {
    echo "=== 5. Data plane: ts3 -> ts1 across the anycast VTEP ==="
    host ts1 "cat /proc/net/bonding/bond0 | grep -E 'Aggregator ID|Partner Mac|MII Status|Slave Interface'"
    host ts3 "ping -c 5 -i 0.2 192.168.100.1"
}

case "${1:-all}" in
    underlay)   step_underlay ;;
    es)         step_es ;;
    routes)     step_routes ;;
    forwarding) step_forwarding ;;
    traffic)    step_traffic ;;
    all)        step_underlay; step_es; step_routes; step_forwarding; step_traffic ;;
    *) echo "unknown step: $1"; exit 2 ;;
esac
