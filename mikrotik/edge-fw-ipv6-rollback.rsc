# Reverts edge-fw-ipv6.rsc (back to "no v6 default advertised"). GUA list entries are left on 1f** (harmless).
/ipv6 settings set accept-router-advertisements=yes-if-forwarding-disabled
/ipv6 nd set [find where default=no and interface!="bridge10"] ra-lifetime=0s
/ipv6 route remove [find comment="edge-fw v6 default"]
/ipv6 address remove [find comment="edge-fw: transit v6"]
/ipv6 address remove [find where address~"^2001:db8:4a00:1f" and dynamic=no]
/ipv6 nd prefix remove [find comment="edge-fw: deprecate stale prefix"]
/ipv6 pool remove [find name=wan-pd]
/ipv6 route remove [find comment~"^edge-fw"]
/ipv6 firewall filter remove [find comment="edge-fw: ignore OPNsense DMZ RAs"]
