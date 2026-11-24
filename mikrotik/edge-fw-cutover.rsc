# edge-fw-cutover.rsc -- RB5009 side of the OPNsense edge-firewall cutover (runbook Phase 5/6)
# Target: RTR-HOMELAB-CN-1, RouterOS 7.23.5. Written 2026-11-01 from pre-edge-fw.rsc.
# Run in SAFE MODE from a winbox session on VLAN 5/99 (not via ether1). Paste the whole file in one go:
# the internet-cutting commands are last, so everything runs even if the remote session drops.
# Rollback: edge-fw-rollback.rsc (and modem cable back into ether1).
# 2026-11-02: the interface below was later renamed vlan100-public-handoff (OPNsense side: PUBLIC_HANDOFF). Kept as the historical record.

# --- 1. Transit + DMZ trunk on ether1 -------------------------------------
/interface vlan add name=vlan100-transit interface=ether1 vlan-id=100 comment="edge-fw: transit to OPNsense"
/interface vlan add name=vlan10-edge interface=ether1 vlan-id=10 comment="edge-fw: DMZ to OPNsense"
/ip address add address=172.16.255.2/30 interface=vlan100-transit comment="edge-fw: transit"
/interface bridge port add bridge=bridge10 interface=vlan10-edge comment="edge-fw: DMZ to OPNsense"
/interface list member add list=WAN interface=vlan100-transit comment="edge-fw"

# --- 2. DMZ gateway moves to OPNsense (L2 stays) ---------------------------
/ip address remove [find address="10.20.0.1/25"]
/ip dhcp-server set [find name=dhcp3] disabled=yes
/ipv6 address set [find interface=bridge10 dynamic=no] disabled=yes
/ipv6 nd set [find interface=bridge10] disabled=yes

# --- 4. QoS follows the new uplink ----------------------------------------
/ip firewall mangle set [find in-interface=ether1] in-interface=vlan100-transit
/ip firewall mangle set [find out-interface=ether1] out-interface=vlan100-transit
/ipv6 firewall mangle set [find in-interface=ether1] in-interface=vlan100-transit
/ipv6 firewall mangle set [find out-interface=ether1] out-interface=vlan100-transit
/queue type set [find name~"^cake-"] cake-nat=no

# --- 5. IPv6: stop advertising a v6 default until Phase 7 ------------------
/ipv6 nd set [find where default=no and interface!="bridge10"] ra-lifetime=0s

# --- 6. Housekeeping from Phase 0 (F7, flow 15) ----------------------------
/interface list set [find name=MGMT-L2] exclude=IOT,DMZ
/interface list set [find name=DISCOVERY] exclude=IOT,WAN,DMZ
/system ntp server set broadcast-addresses=192.168.5.1,192.168.15.1,192.168.20.1,192.168.25.1,192.168.30.1

# --- 3. LAST: router stops being the internet edge (internet drops here) ---
/ip dhcp-client set [find interface=ether1] disabled=yes
/ipv6 dhcp-client set [find interface=ether1] disabled=yes
/ip dns set servers=192.168.15.9,10.20.0.9
/ip firewall nat set [find where chain=srcnat and action=masquerade and !comment] disabled=yes
# NOTE 2026-11-01: the old find (action=masquerade out-interface-list=WAN) silently matched nothing; rule was disabled by number (nat disable 0).
/ip firewall nat set [find comment="public: NPM 80/443"] disabled=yes
/ip route add dst-address=0.0.0.0/0 gateway=172.16.255.1 comment="edge-fw default"

# Not in this script (do after cutover is committed): remove fw-edge-temp rules and the fw-edge-mgmt list;
# clear mlag-peer-port=ether1 on mgmtbridge99 (F8).
