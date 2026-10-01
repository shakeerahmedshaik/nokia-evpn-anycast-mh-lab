#!/usr/bin/env bash
# Failure scenarios from the draft (Sections 4-5). Run verify.sh / watch traffic between steps.
# Usage: ./scripts/fail.sh <scenario>
#   access-down    leaf1 loses its ES link (e1-10). Anycast VTEP stays up on leaf1, so spines still
#                  hash some flows to leaf1 -> leaf1 must fast-reroute them to leaf2 (draft Sec 5).
#   isolate        leaf1 loses both uplinks. 12.12.12.12 is withdrawn from leaf1 only; underlay
#                  converges onto leaf2 with no EVPN change at the ingress (draft Sec 4).
#   anycast-off    remove anycast-multi-homing from ES-1 on both leaves -> classic aliasing:
#                  RT-1 per-EVI reappears and leaf3 does overlay ECMP to 10.0.1.1 / 10.0.1.2.
#   restore        undo all of the above.
set -euo pipefail

LAB=anycast-mh
ES="/ system network-instance protocols evpn ethernet-segments bgp-instance 1 ethernet-segment ES-1"

cfg() {
    local node=$1; shift
    local c
    for c in "$@"; do
        printf '\033[1;35m[%s]\033[0m %s\n' "$node" "$c"
        docker exec "clab-${LAB}-${node}" sr_cli -d -ec "$c"
    done
}

case "${1:-}" in
    access-down)
        cfg leaf1 "set / interface ethernet-1/10 admin-state disable"
        ;;
    isolate)
        cfg leaf1 "set / interface ethernet-1/1 admin-state disable" \
                  "set / interface ethernet-1/2 admin-state disable"
        ;;
    anycast-off)
        for n in leaf1 leaf2; do
            cfg "$n" "delete ${ES} anycast-multi-homing"
        done
        ;;
    restore)
        cfg leaf1 "set / interface ethernet-1/10 admin-state enable" \
                  "set / interface ethernet-1/1 admin-state enable" \
                  "set / interface ethernet-1/2 admin-state enable" \
                  "set ${ES} anycast-multi-homing ip-address 12.12.12.12"
        cfg leaf2 "set ${ES} anycast-multi-homing ip-address 12.12.12.12"
        ;;
    *)
        sed -n '2,12p' "$0"; exit 2 ;;
esac
