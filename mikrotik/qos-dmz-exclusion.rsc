# 2026-11-08 ~21:47 RB5009 (RTR-HOMELAB-CN-1, RouterOS 7.23.5) -- QoS DMZ exclusion
# Why: since the 11-01 OPNsense cutover the DMZ is reached through vlan100-public-handoff, so every QoS mangle rule
# (in-/out-interface=vlan100-public-handoff) treated LAN<->DMZ traffic as WAN download/upload and fed it into CAKE.
# A File History SMB session to pibox's DMZ leg (10.20.0.2:445) filled the 35M cake-upload and halved everyone's upload.
# Placed after the dmz-dns-hairpin connection-mark rules and before "mark WAN download for cake" (v4) /
# "mark WAN v6 download for cake" (v6); mangle accept stops further mangle processing for these packets only.

/ip firewall mangle
add chain=forward action=accept out-interface=vlan100-public-handoff dst-address=10.20.0.0/24 \
    comment="qos: skip LAN->DMZ (not WAN upload)" place-before=[find comment="mark WAN download for cake"]
add chain=forward action=accept in-interface=vlan100-public-handoff src-address=10.20.0.0/24 \
    comment="qos: skip DMZ->LAN (not WAN download)" place-before=[find comment="mark WAN download for cake"]

/ipv6 firewall address-list
add list=qos-dmz6 address=fd12:3456:789a:10::/64 comment="DMZ ULA (qos exclusion)"
add list=qos-dmz6 address=2001:db8:4a00:1f01::/64 comment="DMZ GUA (qos exclusion) - update on prefix change"

/ipv6 firewall mangle
add chain=forward action=accept out-interface=vlan100-public-handoff dst-address-list=qos-dmz6 \
    comment="qos: skip LAN->DMZ v6 (not WAN upload)" place-before=[find comment="mark WAN v6 download for cake"]
add chain=forward action=accept in-interface=vlan100-public-handoff src-address-list=qos-dmz6 \
    comment="qos: skip DMZ->LAN v6 (not WAN download)" place-before=[find comment="mark WAN v6 download for cake"]

# Rollback:
# /ip firewall mangle remove [find comment~"^qos: skip (LAN->DMZ|DMZ->LAN)"]
# /ipv6 firewall mangle remove [find comment~"^qos: skip (LAN->DMZ|DMZ->LAN) v6"]
# /ipv6 firewall address-list remove [find list=qos-dmz6]
