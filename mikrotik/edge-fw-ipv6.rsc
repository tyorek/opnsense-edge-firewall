# edge-fw-ipv6.rsc -- RB5009 side of IPv6 behind OPNsense (runbook Phase 7). Written 2026-11-01.
# the ISP PD on OPNsense: 2001:db8:4a00:1f00::/56. OPNsense keeps 1f00-1f7f (DMZ = 1f01 via track6),
# routes 1f80::/57 and fd12:3456:789a::/48 to this router at fd12:3456:789a:ff::2.
# If the ISP ever changes the /56: update the wan-pd pool prefix here, the OPNsense /57 route and INTERNAL6 alias.
# 2026-11-02: interface names updated for the vlan100-transit -> vlan100-public-handoff rename.

# RB5009 was learning a default from OPNsense's DMZ RA on bridge10 (L2 pass-through); stop accepting RAs.
/ipv6 settings set accept-router-advertisements=no
/ipv6 pool add name=wan-pd prefix=2001:db8:4a00:1f80::/57 prefix-length=64 comment="edge-fw: static /57 routed by OPNsense"
/ipv6 address add address=fd12:3456:789a:ff::2/64 interface=vlan100-public-handoff advertise=no comment="edge-fw: transit v6"
/ipv6 route add dst-address=::/0 gateway=fd12:3456:789a:ff::1 comment="edge-fw v6 default"
# accept-router-advertisements=no only takes effect after a reboot; until then these keep the stray DMZ RA default from winning:
/ipv6 route add dst-address=2000::/3 gateway=fd12:3456:789a:ff::1 comment="edge-fw v6 global unicast (beats stray RA default)"
/ipv6 route add dst-address=fd12:3456:789a:10::/64 gateway=fd12:3456:789a:ff::1 comment="edge-fw: DMZ ULA via OPNsense"
/ipv6 firewall filter add chain=input action=drop protocol=icmpv6 icmp-options=134:0 in-interface=bridge10 comment="edge-fw: ignore OPNsense DMZ RAs" place-before=[find comment="input: icmpv6"]
# REVISED after the 03:17 reboot: from-pool hints were not sticky (bridge5 came back as 1f81, bridge15 as 1f87),
# which broke the resolver GUA in the lists. The VLAN GUAs are now plain static addresses; wan-pd is only a record.
/ipv6 address remove [find where from-pool=wan-pd and interface!=bridge10]
/ipv6 address remove [find where interface=mgmtbridge99 and address~"^2600:" and dynamic=no]
/ipv6 address add address=2001:db8:4a00:1f80::1/64 interface=bridge30
/ipv6 address add address=2001:db8:4a00:1f82::1/64 interface=bridge20
/ipv6 address add address=2001:db8:4a00:1f83::1/64 interface=bridge25
/ipv6 address add address=2001:db8:4a00:1f84::1/64 interface=bridge5
/ipv6 address add address=2001:db8:4a00:1f85::1/64 interface=bridge15
/ipv6 address add address=2001:db8:4a00:1f86::1/64 interface=mgmtbridge99
# Router-originated v6 otherwise sources from the transit ULA and dies upstream:
/ipv6 address add address=2001:db8:4a00:1fff::2/64 interface=vlan100-public-handoff advertise=no comment="edge-fw: transit GUA (router-originated v6 source)"
# A stray static ::/0 via OPNsense's DMZ link-local on bridge10 (no comment, origin unknown) was removed:
/ipv6 route remove [find where dst-address=::/0 and gateway~"bridge10"]
# TEMPORARY: deprecate stale client prefixes (old 2b0x and the post-reboot 1f81/1f87). Remove after ~2h:
#   /ipv6 nd prefix remove [find comment="edge-fw: deprecate stale prefix"]
/ipv6 nd prefix add prefix=2001:db8:4a00:1f81::/64 interface=bridge5 preferred-lifetime=0s valid-lifetime=2h comment="edge-fw: deprecate stale prefix"
/ipv6 nd prefix add prefix=2001:db8:4a00:2b04::/64 interface=bridge5 preferred-lifetime=0s valid-lifetime=2h comment="edge-fw: deprecate stale prefix"
/ipv6 nd prefix add prefix=2001:db8:4a00:1f87::/64 interface=bridge15 preferred-lifetime=0s valid-lifetime=2h comment="edge-fw: deprecate stale prefix"
/ipv6 nd prefix add prefix=2001:db8:4a00:2b05::/64 interface=bridge15 preferred-lifetime=0s valid-lifetime=2h comment="edge-fw: deprecate stale prefix"
/ipv6 nd prefix add prefix=2001:db8:4a00:2b02::/64 interface=bridge20 preferred-lifetime=0s valid-lifetime=2h comment="edge-fw: deprecate stale prefix"
/ipv6 nd prefix add prefix=2001:db8:4a00:2b03::/64 interface=bridge25 preferred-lifetime=0s valid-lifetime=2h comment="edge-fw: deprecate stale prefix"
/ipv6 nd prefix add prefix=2001:db8:4a00:2b00::/64 interface=bridge30 preferred-lifetime=0s valid-lifetime=2h comment="edge-fw: deprecate stale prefix"
/ipv6 nd prefix add prefix=2001:db8:4a00:2b06::/64 interface=mgmtbridge99 preferred-lifetime=0s valid-lifetime=2h comment="edge-fw: deprecate stale prefix"

/ipv6 firewall address-list set [find where address~"^2001:db8:4a00:2b05::"] address=2001:db8:4a00:1f85::/64
/ipv6 firewall address-list set [find where address~"^2001:db8:4a00:2b01:216:3eff:fe0e:c59"] address=2001:db8:4a00:1f01:216:3eff:fe0e:c59/128
/ipv6 firewall address-list set [find where address~"^2001:db8:4a00:2b01:216:3eff:fe0e:458d"] address=2001:db8:4a00:1f01:216:3eff:fe0e:458d/128 comment="bunode1 GUA (current 1f01)"
/ipv6 firewall address-list set [find where address~"^2001:db8:4a00:2b01:216:3eff:fefd:c36a"] address=2001:db8:4a00:1f01:216:3eff:fefd:c36a/128 comment="bunode2 GUA (current 1f01)"
/ipv6 firewall address-list set [find where address~"^2001:db8:4a00:2b05:be24:11ff:fe6a:93b0"] address=2001:db8:4a00:1f85:be24:11ff:fe6a:93b0/128
/ipv6 firewall address-list set [find where address~"^2001:db8:4a00:2b06:be24:11ff:feb3:21d2"] address=2001:db8:4a00:1f86:be24:11ff:feb3:21d2/128
/ipv6 firewall address-list set [find where comment="bauth GUA (current 2b01)"] comment="bauth GUA (current 1f01)"

/ipv6 nd set [find where interface=bridge5 or interface=bridge20 or interface=bridge30] dns="fd12:3456:789a:15:be24:11ff:fe6a:93b0,2001:db8:4a00:1f85:be24:11ff:fe6a:93b0,fd12:3456:789a:10:216:3eff:fe0e:c59,2001:db8:4a00:1f01:216:3eff:fe0e:c59"
/ipv6 nd set [find where interface=bridge25] dns="fd12:3456:789a:10:216:3eff:fe0e:c59,2001:db8:4a00:1f01:216:3eff:fe0e:c59,fd12:3456:789a:15:be24:11ff:fe6a:93b0,2001:db8:4a00:1f85:be24:11ff:fe6a:93b0"
/ipv6 nd set [find where interface=mgmtbridge99] dns="fd12:3456:789a:10:216:3eff:fe0e:c59,2001:db8:4a00:1f01:216:3eff:fe0e:c59"
/ipv6 nd set [find where default=no and interface!="bridge10"] ra-lifetime=30m
