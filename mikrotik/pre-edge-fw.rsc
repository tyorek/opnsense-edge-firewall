# 2026-11-01 00:48:43 by RouterOS 7.23.5
# software id = 948Y-JEZB
#
# model = RB5009UG+S+
# serial number = XXXXXXXXXXX
/interface bridge
add name=bridge5
add name=bridge10
add name=bridge15
add name=bridge20
add name=bridge25
add name=bridge30
add comment="ether4 cAP trunk demux" name=bridgecap vlan-filtering=yes
/interface ethernet
set [ find default-name=ether3 ] l2mtu=9018 mtu=9018
set [ find default-name=ether4 ] l2mtu=9018 mtu=9018
set [ find default-name=ether5 ] l2mtu=9018 mtu=9018
set [ find default-name=sfp-sfpplus1 ] l2mtu=9018 mtu=9018
/interface vlan
add interface=ether2 name=mgmt99ether2 vlan-id=99
add interface=ether3 mtu=9014 name="mgmt99ether3 " vlan-id=99
add interface=ether6 name=mgmt99ether6 vlan-id=99
add interface=ether3 mtu=9014 name=vlan5ether3 vlan-id=5
add interface=sfp-sfpplus1 mtu=9014 name=vlan5sfp vlan-id=5
add interface=bridgecap mtu=9014 name=vlan10cap vlan-id=10
add interface=ether3 mtu=9014 name=vlan10ether3 vlan-id=10
add interface=sfp-sfpplus1 mtu=9014 name=vlan10sfp vlan-id=10
add interface=sfp-sfpplus1 mtu=9014 name=vlan15sfp vlan-id=15
add interface=bridgecap mtu=9014 name=vlan20cap vlan-id=20
add interface=ether3 mtu=9014 name=vlan20ether3 vlan-id=20
add interface=sfp-sfpplus1 mtu=9014 name=vlan20sfp vlan-id=20
add interface=bridgecap mtu=9014 name=vlan25cap vlan-id=25
add interface=ether3 mtu=9014 name=vlan25ether3 vlan-id=25
add interface=sfp-sfpplus1 mtu=9014 name=vlan25sfpplus vlan-id=25
add interface=bridgecap mtu=9014 name=vlan30cap vlan-id=30
/interface list
add name=WAN
add name=LAN
add name=DMZ
add comment="IoT VLAN 25 interfaces" name=IOT
add comment="MAC-winbox/MAC-telnet: LAN minus IoT" exclude=IOT include=LAN \
    name=MGMT-L2
add comment="neighbor discovery: everything except IoT and WAN" exclude=\
    IOT,WAN include=all name=DISCOVERY
/interface wifi datapath
add name=dp-wifi-iot vlan-id=25
add name=dp-wifi-main vlan-id=30
add name=dp-wifi-guest vlan-id=20
/interface wifi security
add authentication-types=wpa2-eap,wpa3-eap ft=yes ft-over-ds=yes name=sec-eap
add authentication-types=wpa2-psk disabled=no encryption=ccmp ft=yes \
    ft-over-ds=yes name=sec-wifi-iot
add authentication-types=wpa2-psk,wpa3-psk disabled=no ft=yes ft-over-ds=yes \
    name=sec-wifi-main
/interface wifi configuration
add channel.band=2ghz-ax .frequency=2437 .width=20mhz country="United States" \
    datapath=dp-wifi-iot disabled=no name=cfg-wifi-iot security=sec-wifi-iot \
    security.encryption=ccmp ssid=wifi-iot
add channel.band=5ghz-ax .frequency=5260 .width=20/40/80mhz country=\
    "United States" datapath=dp-wifi-main disabled=no name=cfg-wifi-main security=\
    sec-wifi-main ssid=WiFi-Main
add channel.band=5ghz-ax country="United States" datapath=dp-wifi-guest name=\
    cfg-wifi-guest security=sec-eap ssid=WiFi-Guest
/ip pool
add name=dhcp_pool1 ranges=192.168.5.2-192.168.5.14
add name=dhcp_pool2 ranges=192.168.30.2-192.168.30.126
add name=dhcp_pool3 ranges=10.20.0.2-10.20.0.126
add name=dhcp_pool4 ranges=192.168.15.2-192.168.15.14
add name=dhcp_pool5 ranges=192.168.20.2-192.168.20.14
add name=dhcp_pool6 ranges=192.168.25.2-192.168.25.126
add name=dhcp_pool7 ranges=192.168.99.2-192.168.99.14
/ip dhcp-server
add address-pool=dhcp_pool1 interface=bridge5 name=dhcp1
add add-arp=yes address-pool=dhcp_pool2 interface=bridge30 name=dhcp2
add address-pool=dhcp_pool3 interface=bridge10 name=dhcp3
add address-pool=dhcp_pool4 interface=bridge15 name=dhcp4
add address-pool=dhcp_pool5 interface=bridge20 name=dhcp5
add address-pool=dhcp_pool6 interface=bridge25 name=dhcp6
/queue tree
add comment="qos-up: parent, replaces ether1 interface queue" max-limit=38M \
    name=cake-upload parent=global
/queue type
add cake-ack-filter=filter cake-bandwidth=38.0Mbps cake-diffserv=diffserv4 \
    cake-flowmode=dual-srchost cake-nat=yes kind=cake name=cake-up
add cake-bandwidth=775.0Mbps cake-flowmode=dual-dsthost cake-nat=yes kind=\
    cake name=cake-down
add cake-ack-filter=filter cake-diffserv=diffserv4 cake-flowmode=dual-srchost \
    cake-nat=yes kind=cake name=cake-up-class
/queue interface
set ether2 queue=cake-down
set ether3 queue=cake-down
set ether4 queue=cake-down
set ether5 queue=cake-down
set ether6 queue=cake-down
set ether7 queue=cake-down
set ether8 queue=default
/queue tree
# CAKE type with bandwidth setting detected, configure traffic limits within queue itself
add max-limit=775M name=cake-download packet-mark=wan-down parent=global \
    queue=cake-down
add limit-at=12M max-limit=38M name=up-game packet-mark=up-game parent=\
    cake-upload priority=1 queue=cake-up-class
add limit-at=14M max-limit=38M name=up-wifi packet-mark=up-wifi parent=\
    cake-upload priority=4 queue=cake-up-class
add limit-at=8M max-limit=38M name=up-other packet-mark=up-other parent=\
    cake-upload priority=6 queue=cake-up-class
add comment="qos-up: resolver upstream DNS/DoT" limit-at=2M max-limit=38M \
    name=up-dns packet-mark=up-dns parent=cake-upload priority=1 queue=\
    cake-up-class
/system logging action
set 0 memory-lines=5000
add memory-lines=2000 name=fwmemory target=memory
/system script
add dont-require-permissions=no name=dns-fallback-check owner=labadmin policy=\
    read,write,test source=":local lanOk false\
    \n:local dmzOk false\
    \n:do {:resolve \"example.com\" server=192.168.15.9; :set lanOk true} on-e\
    rror={}\
    \n:do {:resolve \"example.com\" server=10.20.0.9; :set dmzOk true} on-erro\
    r={}\
    \n:foreach k,ok in={\"LAN\"=\$lanOk;\"DMZ\"=\$dmzOk} do={\
    \n  :local pri (\"^\" . \$k . \" DNS redirect primary\")\
    \n  :local fb (\"^\" . \$k . \" DNS redirect fallback\")\
    \n  :local blk (\"^DNS fallback block \" . \$k)\
    \n  :foreach i in=[/ip firewall nat find where comment~\$pri] do={:if ([/i\
    p firewall nat get \$i disabled] = \$ok) do={/ip firewall nat set \$i disa\
    bled=(!\$ok)}}\
    \n  :foreach i in=[/ip firewall nat find where comment~\$fb] do={:if ([/ip\
    \_firewall nat get \$i disabled] != \$ok) do={/ip firewall nat set \$i dis\
    abled=\$ok}}\
    \n  :foreach i in=[/ip firewall filter find where comment~\$blk] do={:if (\
    [/ip firewall filter get \$i disabled] = \$ok) do={/ip firewall filter set\
    \_\$i disabled=(!\$ok)}}\
    \n  :foreach i in=[/ipv6 firewall nat find where comment~\$pri] do={:if ([\
    /ipv6 firewall nat get \$i disabled] = \$ok) do={/ipv6 firewall nat set \$\
    i disabled=(!\$ok)}}\
    \n  :foreach i in=[/ipv6 firewall nat find where comment~\$fb] do={:if ([/\
    ipv6 firewall nat get \$i disabled] != \$ok) do={/ipv6 firewall nat set \$\
    i disabled=\$ok}}\
    \n  :foreach i in=[/ipv6 firewall filter find where comment~\$blk] do={:if\
    \_([/ipv6 firewall filter get \$i disabled] = \$ok) do={/ipv6 firewall fil\
    ter set \$i disabled=(!\$ok)}}\
    \n}\
    \n"
add dont-require-permissions=no name=rtr-backup-rotate owner=labadmin policy=\
    ftp,reboot,read,write,policy,test,password,sniff,sensitive,romon source=":\
    local dateStr [/system clock get date]\
    \n:local baseName (\"rtr-backup-\" . \$dateStr)\
    \n:local keep 7\
    \n\
    \n/system backup save name=\$baseName dont-encrypt=yes\
    \n/export compact file=\$baseName\
    \n\
    \n:local backups [/file find where name~\"^rtr-backup-.*\\\\.backup\\\$\"]\
    \n:if ([:len \$backups] > \$keep) do={\
    \n    :for i from=\$keep to=([:len \$backups] - 1) do={\
    \n        /file remove [:pick \$backups \$i]\
    \n    }\
    \n}\
    \n\
    \n:local exports [/file find where name~\"^rtr-backup-.*\\\\.rsc\\\$\"]\
    \n:if ([:len \$exports] > \$keep) do={\
    \n    :for i from=\$keep to=([:len \$exports] - 1) do={\
    \n        /file remove [:pick \$exports \$i]\
    \n    }\
    \n}"
/user group
add comment="read-only group for Claude monitoring agent" name=agent-ro \
    policy="ssh,ftp,read,test,api,!local,!telnet,!reboot,!write,!policy,!winbo\
    x,!password,!web,!sniff,!sensitive,!romon,!rest-api"
add comment="read-only REST for Homepage dashboard" name=homepage-ro policy="r\
    ead,api,rest-api,!local,!telnet,!ssh,!ftp,!reboot,!write,!policy,!test,!wi\
    nbox,!password,!web,!sniff,!sensitive,!romon"
add name=digest-ro policy="ssh,read,!local,!telnet,!ftp,!reboot,!write,!policy\
    ,!test,!winbox,!password,!web,!sniff,!sensitive,!api,!romon,!rest-api"
/interface bridge
add mlag-peer-port=ether1 name=mgmtbridge99
/interface bridge port
add bridge=bridge10 interface=vlan10sfp
add bridge=bridge15 interface=vlan15sfp
add bridge=bridge20 interface=vlan20sfp
add bridge=bridge5 interface=vlan5ether3
add bridge=bridge5 interface=vlan5sfp
add bridge=bridge10 interface=vlan10ether3
add bridge=bridgecap interface=ether4 pvid=10
add bridge=bridge10 interface=vlan10cap
add bridge=bridge20 interface=vlan20cap
add bridge=bridge25 interface=vlan25cap
add bridge=bridge30 interface=vlan30cap
add bridge=mgmtbridge99 interface="mgmt99ether3 "
add bridge=bridge20 interface=vlan20ether3
add bridge=bridge25 interface=vlan25sfpplus
add bridge=mgmtbridge99 interface=mgmt99ether2
add bridge=mgmtbridge99 interface=mgmt99ether6
add bridge=bridge25 comment="IoT25: trunk via Asus to AG03" interface=\
    vlan25ether3
/ip firewall connection tracking
set enabled=yes
/ip neighbor discovery-settings
set discover-interface-list=DISCOVERY lldp-med=no
/interface bridge vlan
add bridge=bridgecap tagged=bridgecap untagged=ether4 vlan-ids=10
add bridge=bridgecap tagged=bridgecap,ether4 vlan-ids=20
add bridge=bridgecap tagged=bridgecap,ether4 vlan-ids=25
add bridge=bridgecap tagged=bridgecap,ether4 vlan-ids=30
/interface list member
add interface=ether1 list=WAN
add interface=bridge5 list=LAN
add interface=bridge10 list=LAN
add interface=bridge15 list=LAN
add interface=bridge20 list=LAN
add interface=bridge25 list=LAN
add interface=bridge30 list=LAN
add interface=bridge10 list=DMZ
add interface=mgmtbridge99 list=LAN
add interface=bridge25 list=IOT
add interface=vlan25cap list=IOT
add interface=vlan25sfpplus list=IOT
add interface=vlan25ether3 list=IOT
/interface wifi capsman
set enabled=yes interfaces=bridge10 upgrade-policy=suggest-same-version
/interface wifi provisioning
add action=create-dynamic-enabled comment="2.4GHz radio" \
    master-configuration=cfg-wifi-iot supported-bands=2ghz-ax
add action=create-dynamic-enabled comment="5GHz radio" master-configuration=\
    cfg-wifi-main slave-configurations=cfg-wifi-guest supported-bands=5ghz-ax
/ip address
add address=192.168.5.1/28 interface=bridge5 network=192.168.5.0
add address=192.168.30.1/25 interface=bridge30 network=192.168.30.0
add address=10.20.0.1/25 interface=bridge10 network=10.20.0.0
add address=192.168.15.1/28 interface=bridge15 network=192.168.15.0
add address=192.168.20.1/28 interface=bridge20 network=192.168.20.0
add address=192.168.25.1/25 interface=bridge25 network=192.168.25.0
add address=192.168.99.1/28 interface=mgmtbridge99 network=192.168.99.0
/ip dhcp-client
add default-route-tables=main interface=ether1 name=WAN
/ip dhcp-server
add address-pool=dhcp_pool7 interface=mgmtbridge99 name=dhcp7
/ip dhcp-server lease
add address=10.20.0.7 client-id=\
    ff:ca:53:9:5a:0:2:0:0:ab:11:6:02:00:5e:53:99:90:2a mac-address=\
    02:00:5E:C7:83:C0 server=dhcp3
add address=192.168.15.10 client-id=\
    ff:76:87:1c:56:0:2:0:0:02:00:5e:e0:c1:e9:59:27:b8:e6 mac-address=\
    02:00:5E:A5:EE:91 server=dhcp4
add address=192.168.15.9 client-id=\
    ff:f2:e4:e9:62:0:2:0:0:ab:11:6:02:00:5e:e4:e6:a4:a6 mac-address=\
    02:00:5E:E6:58:AA server=dhcp4
add address=192.168.15.11 client-id=\
    ff:92:18:17:dd:0:2:0:0:02:00:5e:34:33:b7:f6:37:2f:bc mac-address=\
    02:00:5E:9A:CD:9D server=dhcp4
add address=192.168.5.12 client-id=\
    ff:8d:a3:f2:85:0:2:0:0:02:00:5e:36:e7:22:ac:86:d0:73 mac-address=\
    02:00:5E:03:76:DD server=dhcp1
add address=10.20.0.13 mac-address=02:00:5e:39:43:37 server=dhcp3
add address=10.20.0.14 mac-address=02:00:5e:f5:16:2e server=dhcp3
add address=10.20.0.9 client-id=1:0:16:3e:e:c:59 mac-address=\
    02:00:5e:96:72:71 server=dhcp3
add address=10.20.0.2 client-id=\
    ff:ca:98:a1:f4:0:2:0:0:02:00:5e:3f:93:62:40:c7:b6:e mac-address=\
    02:00:5e:6b:55:70 server=dhcp3
add address=192.168.5.10 client-id=1:02:00:5e:4d:a2:68 mac-address=\
    02:00:5E:4D:A2:68 server=dhcp1
add address=192.168.20.2 client-id=\
    ff:9d:57:a3:64:0:2:0:0:02:00:5e:c0:19:3c:f:b7:88:74 mac-address=\
    02:00:5E:20:52:E7 server=dhcp5
add address=192.168.99.2 mac-address=02:00:5e:1a:b2:96 server=dhcp7
add address=192.168.5.9 client-id=1:02:00:5e:03:3d:db mac-address=\
    02:00:5e:03:3d:db server=dhcp1
add address=192.168.5.14 client-id=1:02:00:5e:37:bf:b5 mac-address=\
    02:00:5E:37:BF:B5 server=dhcp1
add address=192.168.20.3 client-id=1:02:00:5e:31:13:ed comment=\
    "laptop DESKTOP-K49Q9G5" mac-address=02:00:5E:31:13:ED server=dhcp5
add address=192.168.20.8 client-id=1:02:00:5e:c4:ad:41 comment=phone \
    mac-address=02:00:5e:c4:ad:41 server=dhcp5
add address=192.168.5.5 comment="pibox VLAN5 (USB NIC, jumbo)" mac-address=\
    02:00:5e:be:56:86 server=dhcp1
add address=192.168.5.13 comment="pve vmbr0.5 iSCSI portal" mac-address=\
    02:00:5e:de:32:c0 server=dhcp1
/ip dhcp-server network
add address=10.20.0.0/25 dns-server=10.20.0.9,192.168.15.9 gateway=10.20.0.1
add address=192.168.5.0/28 dns-server=192.168.15.9,10.20.0.9 gateway=\
    192.168.5.1
add address=192.168.15.0/28 dns-server="1.1.1.1,1.0.0.1,8.8.8.8,8.8.4.4,208.67\
    .222.222,208.67.220.220,9.9.9.9,149.112.112.112" gateway=192.168.15.1
add address=192.168.20.0/28 dns-server=192.168.15.9,10.20.0.9 gateway=\
    192.168.20.1
add address=192.168.25.0/25 dns-server=10.20.0.9,192.168.15.9 gateway=\
    192.168.25.1
add address=192.168.30.0/25 dns-server=192.168.15.9,10.20.0.9 gateway=\
    192.168.30.1
add address=192.168.99.0/28 dns-server=192.168.15.9,10.20.0.9 gateway=\
    192.168.99.1
/ip firewall address-list
add address=192.168.5.9 comment="the admin desktop" list=admin
add address=10.20.0.0/25 comment="DMZ vlan10" list=dns-srv
add address=192.168.15.0/28 comment="DNS vlan15" list=dns-srv
add address=192.168.15.9 comment="primary auth resolver" list=dns-auth
add address=10.20.0.9 comment="DMZ auth resolver" list=dns-auth
add address=10.20.0.9 list=dns-dmz
add address=192.168.15.9 list=dns
add address=192.168.15.10 comment="unbound forwarder" list=dns
add address=192.168.15.11 comment="unbound forwarder" list=dns
add address=192.168.15.0/28 comment="resolver vlan upstream egress" list=dns
add address=192.168.5.0/28 list=lan-clients
add address=192.168.20.0/28 list=lan-clients
add address=192.168.25.0/25 list=lan-clients
add address=192.168.30.0/25 list=lan-clients
add address=192.168.99.0/28 comment="mgmt vlan 99 " list=mgmt-clients
add address=10.20.0.7 comment="local reverse proxy ip address " list=\
    local-proxy
add address=10.20.0.2 comment="public proxy ip address " list="public proxy "
add address=192.168.15.9 comment="LAN auth resolver (DMZ fallback target)" \
    list=dns-lan
add address=192.168.99.3 comment="claude agent LXC" list=agent-box
add address=192.168.5.12 comment="Wazuh manager" list=agent-targets
add address=192.168.99.2 comment="Proxmox API" list=agent-targets
add address=192.168.99.1 comment="RouterOS read-only (SSH/API-SSL)" list=\
    agent-targets
add address=192.168.5.5 comment="pibox (NAS health)" list=agent-targets
add address=192.168.20.3 comment="laptop DESKTOP-K49Q9G5" list=\
    supervisor-clients
add address=192.168.20.8 comment=phone list=supervisor-clients
add address=192.168.15.10 comment=secnodetls list=unbound-nodes
add address=192.168.15.11 comment=tertnodetls list=unbound-nodes
add address=10.20.0.13 comment=bunode1 list=unbound-nodes
add address=10.20.0.14 comment=bunode2 list=unbound-nodes
add address=192.168.5.5 comment="pibox NPM -> sup.example.com" list=\
    supervisor-clients
add address=10.20.0.9 list=dns
add address=192.168.99.9 comment="OPNsense fw-edge mgmt (VM 109)" list=\
    fw-edge-mgmt
/ip firewall filter
add action=drop chain=forward comment="G9 block internet" out-interface-list=\
    WAN src-address=192.168.25.5
add action=accept chain=input comment="input: est/rel" connection-state=\
    established,related
add action=accept chain=input comment="Local proxy input " src-address-list=\
    local-proxy
add action=drop chain=input comment="input: drop invalid" connection-state=\
    invalid
add action=accept chain=input comment="IoT25: DHCP to router" dst-port=67 \
    in-interface=bridge25 protocol=udp
add action=drop chain=input comment="IoT25: no router access" in-interface=\
    bridge25
add action=accept chain=input comment="input: icmp" protocol=icmp
add action=accept chain=input comment="input: dhcp" dst-port=67-68 \
    in-interface-list=LAN protocol=udp
add action=accept chain=input comment="input: capwap from caps" dst-port=\
    5246-5247 in-interface-list=LAN protocol=udp
add action=accept chain=input comment="input: mgmt from vlan5" dst-port=\
    8291,22 in-interface=bridge5 protocol=tcp
add action=accept chain=input comment="input: mgmt from admin desktop" \
    dst-port=8291,22,80 protocol=tcp src-address-list=admin
add action=accept chain=input comment=\
    "agent: input RouterOS mgmt (read-only audit)" dst-address=192.168.99.1 \
    dst-port=22,8729 protocol=tcp src-address=192.168.99.3
add action=accept chain=input comment="NTP clients" dst-port=123 \
    in-interface-list=LAN protocol=udp
add action=accept chain=input comment="homepage: REST API (read-only)" \
    dst-address=192.168.99.1 dst-port=8443 protocol=tcp src-address=\
    192.168.99.8
add action=drop chain=input comment="input: drop all else"
add action=fasttrack-connection chain=forward comment="forward: fasttrack" \
    connection-state=established,related
add action=accept chain=forward comment="forward: est/rel" connection-state=\
    established,related
add action=drop chain=forward comment="forward: drop invalid" \
    connection-state=invalid
add action=drop chain=forward comment="IoT25: other VLANs -> IoT blocked" \
    in-interface-list=!WAN out-interface=bridge25
add action=accept chain=forward comment="forward: admin desktop to all vlans" \
    out-interface-list=LAN src-address-list=admin
add action=accept chain=forward comment=\
    "forward: mgmt vlan99 to all vlans (excl. agent LXC)" out-interface-list=\
    LAN src-address=!192.168.99.3 src-address-list=mgmt-clients
add action=accept chain=forward comment=\
    "forward: local reverse proxy (caddy 10.20.0.7) to all vlans" \
    out-interface-list=LAN src-address-list=local-proxy
add action=accept chain=forward comment=\
    "forward: public reverse proxy (NPM 10.20.0.2) to all vlans" \
    out-interface-list=LAN src-address-list="public proxy "
add action=drop chain=forward comment=\
    "DNS policy: DMZ clients may only use DMZ resolvers" dst-address-list=\
    !dns-auth dst-port=53 protocol=udp src-address=10.20.0.0/25 \
    src-address-list=!dns
add action=drop chain=forward comment=\
    "DNS policy: DMZ clients may only use DMZ resolvers (tcp/DoT)" \
    dst-address-list=!dns-auth dst-port=53,853 protocol=tcp src-address=\
    10.20.0.0/25 src-address-list=!dns
add action=drop chain=forward comment=\
    "DNS policy: internal clients -> local resolvers only" dst-address-list=\
    !dns-auth dst-port=53 protocol=udp src-address-list=lan-clients
add action=drop chain=forward comment=\
    "DNS policy: internal clients -> local resolvers only (tcp/DoT)" \
    dst-address-list=!dns-auth dst-port=53,853 protocol=tcp src-address-list=\
    lan-clients
add action=drop chain=forward comment="DNS fallback block DMZ v4 udp" \
    dst-address-list=dns-lan dst-port=53 protocol=udp src-address=\
    10.20.0.0/25 src-address-list=!dns
add action=drop chain=forward comment="DNS fallback block DMZ v4 tcp" \
    dst-address-list=dns-lan dst-port=53,853 protocol=tcp src-address=\
    10.20.0.0/25 src-address-list=!dns
add action=drop chain=forward comment="DNS fallback block LAN v4 udp" \
    dst-address-list=dns-dmz dst-port=53 protocol=udp src-address-list=\
    lan-clients
add action=drop chain=forward comment="DNS fallback block LAN v4 tcp" \
    dst-address-list=dns-dmz dst-port=53,853 protocol=tcp src-address-list=\
    lan-clients
add action=accept chain=forward comment="IoT25: internet" in-interface=\
    bridge25 out-interface-list=WAN
add action=accept chain=forward comment="IoT25: local DNS udp" \
    dst-address-list=dns-auth dst-port=53 in-interface=bridge25 protocol=udp
add action=accept chain=forward comment="IoT25: local DNS tcp" \
    dst-address-list=dns-auth dst-port=53 in-interface=bridge25 protocol=tcp
add action=drop chain=forward comment="IoT25: drop all else (inter-VLAN)" \
    in-interface=bridge25 log=yes log-prefix=ISO25
add action=accept chain=forward comment="forward: dns udp" dst-address-list=\
    dns-auth dst-port=53 in-interface-list=LAN out-interface-list=LAN \
    protocol=udp
add action=accept chain=forward comment="forward: dns tcp" dst-address-list=\
    dns-auth dst-port=53 in-interface-list=LAN out-interface-list=LAN \
    protocol=tcp
add action=accept chain=forward comment="forward: infra vlan20 in" \
    in-interface-list=LAN out-interface=bridge20
add action=accept chain=forward comment="forward: infra vlan20 out" \
    in-interface=bridge20 out-interface-list=LAN
add action=accept chain=forward comment="forward: resolver vlan to wazuh" \
    dst-address=192.168.5.12 dst-port=1514,1515 protocol=tcp src-address=\
    192.168.15.0/28
add action=accept chain=forward comment=\
    "forward: clients to NPM reverse proxy (pibox: nextcloud, homepage, sup)" \
    dst-address=10.20.0.2 dst-port=80,443 in-interface-list=LAN \
    out-interface=bridge10 protocol=tcp
add action=accept chain=forward comment=\
    "forward: bunode1 wazuh agent to wazuh manager" dst-address=192.168.5.12 \
    dst-port=1514,1515 protocol=tcp src-address=10.20.0.13
add action=accept chain=forward comment=\
    "forward: buauth1 wazuh agent to wazuh manager" dst-address=192.168.5.12 \
    dst-port=1514,1515 protocol=tcp src-address=10.20.0.9
add action=accept chain=forward comment=\
    "forward: bunode2 wazuh agent to wazuh manager" dst-address=192.168.5.12 \
    dst-port=1514,1515 protocol=tcp src-address=10.20.0.14
add action=accept chain=forward comment="agent: Wazuh API" dst-address=\
    192.168.5.12 dst-port=55000 protocol=tcp src-address-list=agent-box
add action=accept chain=forward comment="agent: SSH / API-SSL to targets" \
    dst-address-list=agent-targets dst-port=22,8729 protocol=tcp \
    src-address-list=agent-box
add action=accept chain=forward comment="agent: HTTPS out" dst-port=443 \
    out-interface-list=WAN protocol=tcp src-address-list=agent-box
add action=accept chain=forward comment="agent: Wazuh Indexer API" \
    dst-address=192.168.5.12 dst-port=9200 protocol=tcp src-address-list=\
    agent-box
add action=accept chain=forward comment="agent: Technitium API" \
    dst-address-list=dns-auth dst-port=5380 protocol=tcp src-address-list=\
    agent-box
add action=accept chain=forward comment="agent: Wazuh agent to manager" \
    dst-address=192.168.5.12 dst-port=1514,1515 protocol=tcp \
    src-address-list=agent-box
add action=drop chain=forward comment="agent: drop all other egress" log=yes \
    log-prefix=AGENT-DROP src-address-list=agent-box
add action=accept chain=forward comment="agent: admin SSH in" \
    dst-address-list=agent-box dst-port=22 protocol=tcp src-address=\
    192.168.5.9
add action=accept chain=forward comment="agent: supervisor chat" \
    dst-address-list=agent-box dst-port=8099 protocol=tcp src-address-list=\
    supervisor-clients
add action=drop chain=forward comment="agent: drop all other ingress" \
    dst-address-list=agent-box
add action=accept chain=forward comment="npm: Homepage + digest viewer" \
    dst-address=192.168.99.8 dst-port=3000,8090 protocol=tcp src-address=\
    192.168.5.5
add action=accept chain=forward comment="fw-edge-temp: DNS udp" \
    dst-address-list=dns-auth dst-port=53 protocol=udp src-address-list=\
    fw-edge-mgmt
add action=accept chain=forward comment="fw-edge-temp: DNS tcp" \
    dst-address-list=dns-auth dst-port=53 protocol=tcp src-address-list=\
    fw-edge-mgmt
add action=accept chain=forward comment="fw-edge-temp: updates out" dst-port=\
    80,443 out-interface-list=WAN protocol=tcp src-address-list=fw-edge-mgmt
add action=accept chain=forward comment="fw-edge-temp: NTP out" dst-port=123 \
    out-interface-list=WAN protocol=udp src-address-list=fw-edge-mgmt
add action=accept chain=forward comment="fw-edge: admin GUI/SSH in" \
    dst-address-list=fw-edge-mgmt dst-port=22,443 protocol=tcp src-address=\
    192.168.5.9
add action=drop chain=forward comment="forward: isolate vlans" \
    in-interface-list=LAN log=yes log-prefix=ISO4 out-interface-list=LAN
add action=accept chain=forward comment="forward: lan to wan" \
    in-interface-list=LAN out-interface-list=WAN
add action=accept chain=forward comment="forward: allow port-forwards" \
    connection-nat-state=dstnat connection-state=new in-interface-list=WAN
add action=drop chain=forward comment="forward: drop all else" log=yes \
    log-prefix=DROP4
/ip firewall mangle
add action=mark-connection chain=forward comment=\
    "mark redirected DMZ DNS (udp)" connection-nat-state=dstnat \
    connection-state=new dst-address=10.20.0.9 dst-port=53 in-interface=\
    bridge10 new-connection-mark=dmz-dns-hairpin passthrough=no protocol=udp
add action=mark-connection chain=forward comment=\
    "mark redirected DMZ DNS (tcp)" connection-nat-state=dstnat \
    connection-state=new dst-address=10.20.0.9 dst-port=53 in-interface=\
    bridge10 new-connection-mark=dmz-dns-hairpin passthrough=no protocol=tcp
add action=mark-packet chain=forward comment="mark WAN download for cake" \
    in-interface=ether1 new-packet-mark=wan-down
add action=mark-packet chain=forward comment="qos-up: default class" \
    new-packet-mark=up-other out-interface=ether1
add action=mark-packet chain=forward comment="qos-up: WiFi-Main wifi class" \
    in-interface=bridge30 new-packet-mark=up-wifi out-interface=ether1
add action=mark-packet chain=forward comment=\
    "qos-up: admin workstation 5.9 (game class)" new-packet-mark=up-game \
    out-interface=ether1 src-mac-address=02:00:5e:03:3d:db
add action=mark-packet chain=forward comment=\
    "qos-up: laptop DESKTOP-K49Q9G5 (game class)" new-packet-mark=up-game \
    out-interface=ether1 src-mac-address=02:00:5E:31:13:ED
add action=mark-packet chain=forward comment=\
    "qos-up: resolver upstream DNS udp" dst-port=53,853 new-packet-mark=\
    up-dns out-interface=ether1 protocol=udp
add action=mark-packet chain=forward comment=\
    "qos-up: resolver upstream DNS tcp/DoT" dst-port=53,853 new-packet-mark=\
    up-dns out-interface=ether1 protocol=tcp
/ip firewall nat
add action=masquerade chain=srcnat out-interface-list=WAN
add action=accept chain=dstnat comment=\
    "homepage: Unbound probes skip the resolver redirect" dst-address-list=\
    unbound-nodes src-address=192.168.99.8
add action=dst-nat chain=dstnat comment="DMZ DNS redirect primary (udp)" \
    dst-address=!10.20.0.9 dst-port=53 protocol=udp src-address=10.20.0.0/25 \
    src-address-list=!dns to-addresses=10.20.0.9
add action=dst-nat chain=dstnat comment="DMZ DNS redirect primary (tcp)" \
    dst-address=!10.20.0.9 dst-port=53 protocol=tcp src-address=10.20.0.0/25 \
    src-address-list=!dns to-addresses=10.20.0.9
add action=dst-nat chain=dstnat comment="LAN DNS redirect primary (udp)" \
    dst-address=!192.168.15.9 dst-port=53 protocol=udp src-address-list=\
    lan-clients to-addresses=192.168.15.9
add action=dst-nat chain=dstnat comment="LAN DNS redirect primary (tcp)" \
    dst-address=!192.168.15.9 dst-port=53 protocol=tcp src-address-list=\
    lan-clients to-addresses=192.168.15.9
add action=dst-nat chain=dstnat comment="LAN DNS redirect fallback (udp)" \
    disabled=yes dst-address=!10.20.0.9 dst-port=53 protocol=udp \
    src-address-list=lan-clients to-addresses=10.20.0.9
add action=dst-nat chain=dstnat comment="LAN DNS redirect fallback (tcp)" \
    disabled=yes dst-address=!10.20.0.9 dst-port=53 protocol=tcp \
    src-address-list=lan-clients to-addresses=10.20.0.9
add action=masquerade chain=srcnat comment="DMZ DNS redirect hairpin" \
    connection-mark=dmz-dns-hairpin out-interface=bridge10
add action=dst-nat chain=dstnat comment="public: NPM 80/443" dst-port=80,443 \
    in-interface-list=WAN protocol=tcp to-addresses=10.20.0.2
add action=dst-nat chain=dstnat comment="DMZ DNS redirect fallback (udp)" \
    disabled=yes dst-address=!192.168.15.9 dst-port=53 protocol=udp \
    src-address=10.20.0.0/25 src-address-list=!dns to-addresses=192.168.15.9
add action=dst-nat chain=dstnat comment="DMZ DNS redirect fallback (tcp)" \
    disabled=yes dst-address=!192.168.15.9 dst-port=53 protocol=tcp \
    src-address=10.20.0.0/25 src-address-list=!dns to-addresses=192.168.15.9
/ip firewall raw
add action=drop chain=prerouting dst-port=53 in-interface-list=WAN protocol=\
    udp
add action=drop chain=prerouting dst-port=53 in-interface-list=WAN protocol=\
    tcp
/ip service
set ftp address=192.168.99.0/28 disabled=yes
set ssh address=192.168.5.0/28,192.168.99.0/28
set telnet disabled=yes
set www address=192.168.5.0/28,10.20.0.7/32
set winbox address=192.168.99.0/28,192.168.5.0/28
set www-ssl address=10.20.0.7/32,192.168.99.8/32 certificate=api-ssl-cert \
    disabled=no port=8443
set api disabled=yes
set api-ssl address=192.168.5.0/28,192.168.99.0/28 certificate=api-ssl-cert
/ipv6 address
add address=::4:0:0:0:1 from-pool=wan-pd interface=bridge5
add address=::1:0:0:0:1 from-pool=wan-pd interface=bridge10
add address=::5:0:0:0:1 from-pool=wan-pd interface=bridge15
add address=::2:0:0:0:1 from-pool=wan-pd interface=bridge20
add address=::3:0:0:0:1 from-pool=wan-pd interface=bridge25
add address=::1 from-pool=wan-pd interface=bridge30
add address=fd12:3456:789a:5::1 interface=bridge5
add address=fd12:3456:789a:10::1 interface=bridge10
add address=fd12:3456:789a:15::1 interface=bridge15
add address=fd12:3456:789a:20::1 interface=bridge20
add address=fd12:3456:789a:25::1 interface=bridge25
add address=fd12:3456:789a:30::1 interface=bridge30
add address=fd12:3456:789a:99::1 interface=mgmtbridge99
add address=2001:db8:4a00:2b06::1 interface=mgmtbridge99
/ipv6 dhcp-client
add add-default-route=yes default-route-tables=main interface=ether1 \
    pool-name=wan-pd pool-prefix-length=64 prefix-hint=::/56 request=\
    address,prefix
/ipv6 firewall address-list
add address=fd12:3456:789a:10::/64 list=dns6-srv
add address=fd12:3456:789a:15::/64 list=dns6-srv
add address=2001:db8:4a00:2b05::/64 comment="resolver vlan GUA" list=dns6
add address=fd12:3456:789a:15::/64 comment="resolver vlan ULA" list=dns6
add address=fd12:3456:789a:10:216:3eff:fe0e:c59/128 comment="buauth ULA" \
    list=dns6
add address=fd12:3456:789a:10:216:3eff:fe0e:458d/128 comment="bunode1 ULA" \
    list=dns6
add address=fd12:3456:789a:10:216:3eff:fefd:c36a/128 comment="bunode2 ULA" \
    list=dns6
add address=fd12:3456:789a:15:be24:11ff:fe6a:93b0/128 comment=\
    "primenodetls ULA" list=dns-auth6
add address=fd12:3456:789a:10:216:3eff:fe0e:c59/128 comment="buauth ULA" \
    list=dns-auth6
add address=fd12:3456:789a:10:216:3eff:fe0e:c59/128 comment="buauth ULA" \
    list=dns-dmz6
add address=fd12:3456:789a:15:be24:11ff:fe6a:93b0/128 comment=\
    "LAN auth resolver (DMZ fallback target)" list=dns-lan6
add address=2001:db8:4a00:2b01:216:3eff:fe0e:c59/128 comment=\
    "bauth GUA (DMZ auth)" list=dns-auth6
add address=2001:db8:4a00:2b05:be24:11ff:fe6a:93b0/128 comment=\
    "primenode GUA (LAN auth)" list=dns-auth6
add address=2001:db8:4a00:2b01:216:3eff:fe0e:c59/128 comment=\
    "bauth GUA (DMZ auth)" list=dns-dmz6
add address=2001:db8:4a00:2b05:be24:11ff:fe6a:93b0/128 comment=\
    "primenode GUA (LAN auth)" list=dns-lan6
add address=2001:db8:4a00:2b01:216:3eff:fe0e:c59/128 comment=\
    "bauth GUA (current 2b01)" list=dns6
add address=2001:db8:4a00:2b01:216:3eff:fe0e:458d/128 comment=\
    "bunode1 GUA (current 2b01)" list=dns6
add address=2001:db8:4a00:2b01:216:3eff:fefd:c36a/128 comment=\
    "bunode2 GUA (current 2b01)" list=dns6
add address=2001:db8:4a00:2b06:be24:11ff:feb3:21d2/128 comment=\
    "agent LXC GUA" list=agent-box6
add address=fd12:3456:789a:99:be24:11ff:feb3:21d2/128 comment="agent LXC ULA" \
    list=agent-box6
/ipv6 firewall filter
add action=accept chain=input comment="input: est/rel" connection-state=\
    established,related
add action=drop chain=input comment="input: drop invalid" connection-state=\
    invalid
add action=accept chain=input comment="IoT25 v6: ND router solicit" \
    icmp-options=133:0 in-interface=bridge25 protocol=icmpv6
add action=accept chain=input comment="IoT25 v6: ND neighbor solicit" \
    icmp-options=135:0 in-interface=bridge25 protocol=icmpv6
add action=accept chain=input comment="IoT25 v6: ND neighbor advert" \
    icmp-options=136:0 in-interface=bridge25 protocol=icmpv6
add action=drop chain=input comment="IoT25 v6: no router access" \
    in-interface=bridge25
add action=accept chain=input comment="input: icmpv6" protocol=icmpv6
add action=accept chain=input comment="input: dhcpv6 client" dst-port=546 \
    protocol=udp src-address=fe80::/10
add action=accept chain=input comment="input: capwap" dst-port=5246-5247 \
    in-interface-list=LAN protocol=udp
add action=accept chain=input comment="NTP clients v6" dst-port=123 \
    in-interface-list=LAN protocol=udp
add action=drop chain=input comment="input: drop all else"
add action=fasttrack-connection chain=forward comment="forward: fasttrack6" \
    connection-state=established,related
add action=accept chain=forward comment="forward: est/rel" connection-state=\
    established,related
add action=drop chain=forward comment="forward: drop invalid" \
    connection-state=invalid
add action=drop chain=forward comment="IoT25 v6: other VLANs -> IoT blocked" \
    in-interface-list=!WAN out-interface=bridge25
add action=drop chain=forward comment="IoT25 v6: no ICMPv6 to other VLANs" \
    in-interface=bridge25 out-interface-list=!WAN protocol=icmpv6
add action=accept chain=forward comment="forward: icmpv6" protocol=icmpv6
add action=drop chain=forward comment=\
    "DNS policy v6: DMZ clients -> DMZ resolver only" dst-address-list=\
    !dns-auth6 dst-port=53 in-interface=bridge10 protocol=udp \
    src-address-list=!dns6
add action=drop chain=forward comment=\
    "DNS policy v6: DMZ clients -> DMZ resolver only (tcp/DoT)" \
    dst-address-list=!dns-auth6 dst-port=53,853 in-interface=bridge10 \
    protocol=tcp src-address-list=!dns6
add action=drop chain=forward comment=\
    "DNS policy v6: internal clients -> local resolvers only (udp)" \
    dst-address-list=!dns-auth6 dst-port=53 in-interface-list=LAN protocol=\
    udp src-address-list=!dns6
add action=drop chain=forward comment=\
    "DNS policy v6: internal clients -> local resolvers only (tcp/DoT)" \
    dst-address-list=!dns-auth6 dst-port=53,853 in-interface-list=LAN \
    protocol=tcp src-address-list=!dns6
add action=drop chain=forward comment="DNS fallback block DMZ v6 udp" \
    dst-address-list=dns-lan6 dst-port=53 in-interface=bridge10 protocol=udp \
    src-address-list=!dns6
add action=drop chain=forward comment="DNS fallback block DMZ v6 tcp" \
    dst-address-list=dns-lan6 dst-port=53,853 in-interface=bridge10 protocol=\
    tcp src-address-list=!dns6
add action=drop chain=forward comment="DNS fallback block LAN v6 udp" \
    dst-address-list=dns-dmz6 dst-port=53 in-interface-list=!DMZ protocol=udp \
    src-address-list=!dns6
add action=drop chain=forward comment="DNS fallback block LAN v6 tcp" \
    dst-address-list=dns-dmz6 dst-port=53,853 in-interface-list=!DMZ \
    protocol=tcp src-address-list=!dns6
add action=accept chain=forward comment="IoT25 v6: internet" in-interface=\
    bridge25 out-interface-list=WAN
add action=accept chain=forward comment="IoT25 v6: local DNS udp" \
    dst-address-list=dns-auth6 dst-port=53 in-interface=bridge25 protocol=udp
add action=accept chain=forward comment="IoT25 v6: local DNS tcp" \
    dst-address-list=dns-auth6 dst-port=53 in-interface=bridge25 protocol=tcp
add action=drop chain=forward comment="IoT25 v6: drop all else (inter-VLAN)" \
    in-interface=bridge25 log=yes log-prefix=ISO25-6
add action=accept chain=forward comment="forward: dns6 udp" dst-address-list=\
    dns-auth6 dst-port=53 in-interface-list=LAN out-interface-list=LAN \
    protocol=udp
add action=accept chain=forward comment="forward: dns6 tcp" dst-address-list=\
    dns-auth6 dst-port=53 in-interface-list=LAN out-interface-list=LAN \
    protocol=tcp
add action=accept chain=forward comment="forward: infra vlan20 in" \
    in-interface-list=LAN out-interface=bridge20
add action=accept chain=forward comment="forward: infra vlan20 out" \
    in-interface=bridge20 out-interface-list=LAN
add action=drop chain=forward comment="agent: drop v6 egress" \
    src-address-list=agent-box6
add action=drop chain=forward comment="agent: drop v6 ingress" \
    dst-address-list=agent-box6
add action=drop chain=forward comment="forward: isolate vlans" \
    in-interface-list=LAN log-prefix=ISO6 out-interface-list=LAN
add action=accept chain=forward comment="forward: lan to wan" \
    in-interface-list=LAN out-interface-list=WAN
add action=drop chain=forward comment="forward: drop all else"
/ipv6 firewall mangle
add action=mark-connection chain=forward comment=\
    "mark redirected DMZ DNS v6 (udp)" connection-nat-state=dstnat \
    connection-state=new dst-address=fd12:3456:789a:10:216:3eff:fe0e:c59/128 \
    dst-port=53 in-interface=bridge10 new-connection-mark=dmz-dns6-hairpin \
    passthrough=no protocol=udp
add action=mark-connection chain=forward comment=\
    "mark redirected DMZ DNS v6 (tcp)" connection-nat-state=dstnat \
    connection-state=new dst-address=fd12:3456:789a:10:216:3eff:fe0e:c59/128 \
    dst-port=53 in-interface=bridge10 new-connection-mark=dmz-dns6-hairpin \
    passthrough=no protocol=tcp
add action=mark-packet chain=forward comment="mark WAN v6 download for cake" \
    in-interface=ether1 new-packet-mark=wan-down
add action=mark-packet chain=forward comment="qos-up: default class" \
    new-packet-mark=up-other out-interface=ether1
add action=mark-packet chain=forward comment="qos-up: WiFi-Main wifi class" \
    in-interface=bridge30 new-packet-mark=up-wifi out-interface=ether1
add action=mark-packet chain=forward comment=\
    "qos-up: admin workstation 5.9 (game class)" new-packet-mark=up-game \
    out-interface=ether1 src-mac-address=02:00:5e:03:3d:db
add action=mark-packet chain=forward comment=\
    "qos-up: laptop DESKTOP-K49Q9G5 (game class)" new-packet-mark=up-game \
    out-interface=ether1 src-mac-address=02:00:5E:31:13:ED
add action=mark-packet chain=forward comment=\
    "qos-up: resolver upstream DNS udp" dst-port=53,853 new-packet-mark=\
    up-dns out-interface=ether1 protocol=udp
add action=mark-packet chain=forward comment=\
    "qos-up: resolver upstream DNS tcp/DoT" dst-port=53,853 new-packet-mark=\
    up-dns out-interface=ether1 protocol=tcp
/ipv6 firewall nat
add action=masquerade chain=srcnat comment="DMZ DNS redirect hairpin v6" \
    connection-mark=dmz-dns6-hairpin out-interface=bridge10
add action=dst-nat chain=dstnat comment="DMZ DNS redirect primary v6 (udp)" \
    dst-address-list=!dns-dmz6 dst-port=53 in-interface=bridge10 protocol=udp \
    src-address-list=!dns6 to-address=fd12:3456:789a:10:216:3eff:fe0e:c59/128
add action=dst-nat chain=dstnat comment="DMZ DNS redirect primary v6 (tcp)" \
    dst-address-list=!dns-dmz6 dst-port=53 in-interface=bridge10 protocol=tcp \
    src-address-list=!dns6 to-address=fd12:3456:789a:10:216:3eff:fe0e:c59/128
add action=dst-nat chain=dstnat comment="LAN DNS redirect primary v6 (udp)" \
    dst-address=!fd12:3456:789a:15:be24:11ff:fe6a:93b0/128 dst-port=53 \
    in-interface-list=!DMZ protocol=udp src-address-list=!dns6 to-address=\
    fd12:3456:789a:15:be24:11ff:fe6a:93b0/128
add action=dst-nat chain=dstnat comment="LAN DNS redirect primary v6 (tcp)" \
    dst-address=!fd12:3456:789a:15:be24:11ff:fe6a:93b0/128 dst-port=53 \
    in-interface-list=!DMZ protocol=tcp src-address-list=!dns6 to-address=\
    fd12:3456:789a:15:be24:11ff:fe6a:93b0/128
add action=dst-nat chain=dstnat comment="LAN DNS redirect fallback v6 (udp)" \
    disabled=yes dst-address=!fd12:3456:789a:10:216:3eff:fe0e:c59/128 \
    dst-port=53 in-interface-list=!DMZ protocol=udp src-address-list=!dns6 \
    to-address=fd12:3456:789a:10:216:3eff:fe0e:c59/128
add action=dst-nat chain=dstnat comment="LAN DNS redirect fallback v6 (tcp)" \
    disabled=yes dst-address=!fd12:3456:789a:10:216:3eff:fe0e:c59/128 \
    dst-port=53 in-interface-list=!DMZ protocol=tcp src-address-list=!dns6 \
    to-address=fd12:3456:789a:10:216:3eff:fe0e:c59/128
add action=dst-nat chain=dstnat comment="DMZ DNS redirect fallback v6 (udp)" \
    disabled=yes dst-address=!fd12:3456:789a:15:be24:11ff:fe6a:93b0/128 \
    dst-port=53 in-interface=bridge10 protocol=udp src-address-list=!dns6 \
    to-address=fd12:3456:789a:15:be24:11ff:fe6a:93b0/128
add action=dst-nat chain=dstnat comment="DMZ DNS redirect fallback v6 (tcp)" \
    disabled=yes dst-address=!fd12:3456:789a:15:be24:11ff:fe6a:93b0/128 \
    dst-port=53 in-interface=bridge10 protocol=tcp src-address-list=!dns6 \
    to-address=fd12:3456:789a:15:be24:11ff:fe6a:93b0/128
/ipv6 firewall raw
add action=drop chain=prerouting comment="drop WAN-inbound DNS v6 (udp)" \
    dst-port=53 in-interface-list=WAN protocol=udp
add action=drop chain=prerouting comment="drop WAN-inbound DNS v6 (tcp)" \
    dst-port=53 in-interface-list=WAN protocol=tcp
/ipv6 nd
set [ find default=yes ] disabled=yes ra-lifetime=none
add advertise-dns=yes dns="fd12:3456:789a:10:216:3eff:fe0e:c59,2001:db8:4a00:\
    2b01:216:3eff:fe0e:c59,fd12:3456:789a:15:be24:11ff:fe6a:93b0,2001:db8:4a0\
    0:2b05:be24:11ff:fe6a:93b0" interface=bridge10
add advertise-dns=yes dns="fd12:3456:789a:15:be24:11ff:fe6a:93b0,2001:db8:4a0\
    0:2b05:be24:11ff:fe6a:93b0,fd12:3456:789a:10:216:3eff:fe0e:c59,2001:db8:4\
    a00:2b01:216:3eff:fe0e:c59" interface=bridge5
add advertise-dns=yes dns="fd12:3456:789a:15:be24:11ff:fe6a:93b0,2001:db8:4a0\
    0:2b05:be24:11ff:fe6a:93b0,fd12:3456:789a:10:216:3eff:fe0e:c59,2001:db8:4\
    a00:2b01:216:3eff:fe0e:c59" interface=bridge20
add advertise-dns=yes dns="fd12:3456:789a:10:216:3eff:fe0e:c59,2001:db8:4a00:\
    2b01:216:3eff:fe0e:c59,fd12:3456:789a:15:be24:11ff:fe6a:93b0,2001:db8:4a0\
    0:2b05:be24:11ff:fe6a:93b0" interface=bridge25
add advertise-dns=yes dns="fd12:3456:789a:15:be24:11ff:fe6a:93b0,2001:db8:4a0\
    0:2b05:be24:11ff:fe6a:93b0,fd12:3456:789a:10:216:3eff:fe0e:c59,2001:db8:4\
    a00:2b01:216:3eff:fe0e:c59" interface=bridge30
add advertise-dns=yes dns="2606:4700:4700::1111,2606:4700:4700::1001,2001:4860\
    :4860::8888,2001:4860:4860::8844,2620:fe::fe,2620:fe::9,2620:119:35::35,26\
    20:119:53::53" interface=bridge15
add dns=\
    fd12:3456:789a:10:216:3eff:fe0e:c59,2001:db8:4a00:2b01:216:3eff:fe0e:c59 \
    interface=mgmtbridge99
/radius
add address=192.168.20.7 comment="wifi EAP" service=wireless timeout=1s
/system clock
set time-zone-name=America/Chicago
/system identity
set name=RTR-HOMELAB-CN-1
/system logging
set 0 topics=info,!firewall
add action=fwmemory topics=firewall
/system ntp client
set enabled=yes
/system ntp server
set broadcast=yes broadcast-addresses=\
    10.20.0.1,192.168.5.1,192.168.15.1,192.168.20.1,192.168.25.1,192.168.30.1 \
    enabled=yes
/system ntp client servers
add address=0.pool.ntp.org
add address=1.pool.ntp.org
add address=2.pool.ntp.org
add address=3.pool.ntp.org
/system package update
set channel=long-term
/system routerboard settings
set auto-upgrade=yes
/system scheduler
add interval=30s name=dns-fallback-check on-event=dns-fallback-check policy=\
    ftp,reboot,read,write,policy,test,password,sniff,sensitive,romon \
    start-date=2026-07-19 start-time=11:50:53
add interval=1d name=rtr-backup-rotate on-event=\
    "/system script run rtr-backup-rotate" policy=\
    ftp,reboot,read,write,policy,test,password,sniff,sensitive,romon \
    start-date=2026-10-02 start-time=02:00:00
/tool mac-server
set allowed-interface-list=MGMT-L2
/tool mac-server mac-winbox
set allowed-interface-list=MGMT-L2
/tool romon
set enabled=yes
/tool romon port
add comment="IoT: no RoMON" forbid=yes interface=vlan25sfpplus
add comment="IoT: no RoMON" forbid=yes interface=vlan25cap
add comment="IoT: no RoMON" forbid=yes interface=vlan25ether3
/tool sniffer
set filter-interface=ether5 memory-limit=2000KiB
