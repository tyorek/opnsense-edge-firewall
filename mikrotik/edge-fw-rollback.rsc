# edge-fw-rollback.rsc -- reverses edge-fw-cutover.rsc line by line. Also: modem cable back into ether1,
# power-cycle the CM1200. (If still in safe mode, simply ending the winbox session reverts everything.)
# 2026-11-02: vlan100-transit was renamed vlan100-public-handoff; this file uses the new name. Re-upload it to the router (Files) -- the copy there still has the old name.

/system ntp server set broadcast-addresses=10.20.0.1,192.168.5.1,192.168.15.1,192.168.20.1,192.168.25.1,192.168.30.1
/interface list set [find name=DISCOVERY] exclude=IOT,WAN
/interface list set [find name=MGMT-L2] exclude=IOT
/ipv6 nd set [find where default=no and interface!="bridge10"] ra-lifetime=30m
/queue type set [find name~"^cake-"] cake-nat=yes
/ipv6 firewall mangle set [find out-interface=vlan100-public-handoff] out-interface=ether1
/ipv6 firewall mangle set [find in-interface=vlan100-public-handoff] in-interface=ether1
/ip firewall mangle set [find out-interface=vlan100-public-handoff] out-interface=ether1
/ip firewall mangle set [find in-interface=vlan100-public-handoff] in-interface=ether1
/ip route remove [find comment="edge-fw default"]
/ip firewall nat set [find comment="public: NPM 80/443"] disabled=no
/ip firewall nat set [find where chain=srcnat and action=masquerade and !comment] disabled=no
# If that matches nothing, use: /ip firewall nat print where chain=srcnat ; then: /ip firewall nat enable <number of the uncommented masquerade>
/ip dns set servers=""
/ipv6 dhcp-client set [find interface=ether1] disabled=no
/ip dhcp-client set [find interface=ether1] disabled=no
/ipv6 nd set [find interface=bridge10] disabled=no
/ipv6 address set [find interface=bridge10 dynamic=no] disabled=no
/ip dhcp-server set [find name=dhcp3] disabled=no
/ip address add address=10.20.0.1/25 interface=bridge10 network=10.20.0.0
/interface list member remove [find interface=vlan100-public-handoff]
/interface bridge port remove [find interface=vlan10-edge]
/ip address remove [find interface=vlan100-public-handoff]
/interface vlan remove [find name=vlan10-edge]
/interface vlan remove [find name=vlan100-public-handoff]
