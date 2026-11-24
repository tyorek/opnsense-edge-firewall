# OPNsense edge firewall: Phase 0 record

**Captured:** 2026-11-01 ~00:50 CDT, read-only, from RTR-HOMELAB-CN-1 (RB5009, RouterOS 7.23.5)
**Companion to:** `opnsense-edge-firewall-dmz-runbook.md`
**Raw sources (in `MikroTik & Service Configs/`):**
- `pre-edge-fw.rsc`: full `/export` taken before any edge-firewall change (also still on the router as `pre-edge-fw.rsc`)
- `phase0-runtime.txt`: bridge10 detail, dhcp3 leases, live DMZ conntrack, bridge10 host table and ARP at capture time

Phase 0 gate: **export saved off-router (done); flow list written (below).**

---

## 1. Runbook placeholder values

| Item | Value |
|---|---|
| Transit VLAN ID | 100 (unchanged suggestion) |
| Transit subnet | 172.16.255.0/30 (OPNsense .1, RB5009 .2) |
| OPNsense mgmt IP (VLAN 99) | 192.168.99.9/28, verified free (pve ARP resolved it to VM 109 net0 `02:00:5E:C2:9A:A7`) |
| VMID / storage | 109 / EFI on `local-lvm`, 32G qcow2 on `hot1` |
| Firewall NICs (USB trial, no i226) | WAN = vtnet1 = vmbr2 = `enx00051b637fea` (02:00:5e:8f:d5:c6); inside = vtnet2 = vmbr3 = `enxf8e43be51b52` (02:00:5E:5A:EE:62) |
| RB5009 ether1 MAC | **02:00:5e:b7:f7:b0** (mac = orig-mac, never changed) |
| Current public IPv4 | **203.0.113.10/23**, gateway 203.0.113.1 (`/ip cloud` agrees) |
| RB5009 bridge holding 10.20.0.1/25 | **bridge10** |
| DMZ MTU | bridge10 `mtu=auto actual-mtu=9014 l2mtu=9014` (router side). Hosts: **caddy ens18 1500** (was 9014, changed 2026-11-01, see F1); **pibox br1/eth0 1500**; buauth/bunode1/bunode2 are libvirt VMs on pibox's br1 (vnet6/8/10 at 1500). Only caddy is jumbo. See finding F1. |
| NPM | 10.20.0.2:80,443 (pibox, Docker) |
| NPM backends | All leave pibox via the DMZ leg (src 10.20.0.2). Boundary-crossing: 192.168.20.2:11000 (nextcloud), 192.168.99.8:3000 (home), 192.168.99.8:8090 (digest), 192.168.99.3:8099 https (sup), 192.168.15.9:53443 https (primenodetls), 192.168.5.12:443 https (node), 192.168.20.14:4444 (search). Full list in flow 6 |
| Wazuh manager | 192.168.5.12 (agents 1514/1515, API 55000, indexer 9200) |

## 2. DMZ inventory (bridge10)

Ports: `vlan10sfp` (SFP+ trunk to AG01/pve), `vlan10ether3` (Asus to AG03/pibox), `vlan10cap` (cAP via bridgecap, ether4 pvid 10).

| IP | Host | MAC | Seen on | Addressing |
|---|---|---|---|---|
| 10.20.0.2 | pibox (NPM) | 02:00:5e:6b:55:70 | vlan10ether3 | DHCP reservation |
| 10.20.0.7 | caddy (VM 106, local reverse proxy) | 02:00:5E:C7:83:C0 | vlan10sfp | DHCP reservation |
| 10.20.0.9 | buauth (Technitium, DMZ auth resolver; libvirt VM on pibox br1) | 02:00:5e:96:72:71 | vlan10ether3 | DHCP reservation |
| 10.20.0.13 | bunode1 (Unbound) | 02:00:5e:39:43:37 | vlan10ether3 | DHCP reservation |
| 10.20.0.14 | bunode2 (Unbound) | 02:00:5e:f5:16:2e | vlan10ether3 | DHCP reservation |
| 10.20.0.4 | AG02 switch | 02:00:5E:06:62:E4 | vlan10sfp | dynamic lease |
| 10.20.0.5 | AG01 switch | 02:00:5E:6E:EA:CE | vlan10sfp | dynamic lease |
| 10.20.0.12 | AG03 switch | 02:00:5E:4D:A2:68 | vlan10ether3 | dynamic lease |
| 10.20.0.6 | cAP | 02:00:5E:FD:BC:11 | vlan10cap | dynamic lease |
| ~~10.20.0.10~~ | Living-Room Apple TV, moved to IoT; now 192.168.25.4 (dhcp6, bound) | 02:00:5e:d6:2a:0f | stale ARP leftover only | not a DMZ host |

(10.20.0.3 in ARP is the 192.168.99.10 laptop's MAC from an earlier DMZ session; 10.20.0.11 is a failed ARP entry with no MAC. Neither is a current host.)

DHCP server `dhcp3` on bridge10: pool 10.20.0.2-126, gateway 10.20.0.1, DNS 10.20.0.9, 192.168.15.9.

## 3. Flow list: everything crossing the DMZ boundary today

"Rule" = the RB5009 rule that allows it now. "Live" = seen in conntrack at capture time. Each line needs an explicit equivalent after cutover.

### Into the DMZ

| # | Flow | Rule / evidence | After cutover |
|---|---|---|---|
| 1 | WAN to 10.20.0.2 tcp 80,443 | dst-nat "public: NPM 80/443" + "forward: allow port-forwards" | OPNsense WAN port forward |
| 2 | Internal clients to 10.20.0.2 tcp 80,443 | "forward: clients to NPM reverse proxy (pibox: nextcloud, homepage, sup)"; live from 192.168.99.10 | OPNsense TRANSIT allow 192.168.0.0/16 to 10.20.0.2:80,443 |
| 3 | Internal clients to 10.20.0.9 udp/tcp 53 | "forward: dns udp/tcp" (dst-address-list=dns-auth) | OPNsense TRANSIT allow to 10.20.0.9:53 |
| 4 | **RB5009 itself** to 10.20.0.9:53 every 30s | `dns-fallback-check` script; live (src 10.20.0.1) | Source becomes **172.16.255.2**, which `192.168.0.0/16` does not cover. Add it to the TRANSIT DNS rule |
| 5 | Admin 192.168.5.9 and mgmt 192.168.99.0/28 to **any DMZ host, any port** | "forward: admin desktop to all vlans", "forward: mgmt vlan99 to all vlans"; live 99.10 to caddy :443, 99.8 (Homepage) to bunode1/2 :53 | Wider than the runbook's "admin SSH". Decide the scope: at least caddy :443 (pve.home.arpa etc.), SSH, and the Homepage DNS probes |

### Out of the DMZ

| # | Flow | Rule / evidence | After cutover |
|---|---|---|---|
| 6 | NPM 10.20.0.2 to its backends (from `/data/nginx/proxy_host/*.conf`, read 2026-11-01): 192.168.20.2:11000 nextcloud (live), 192.168.99.8:3000 home, 192.168.99.8:8090 digest, 192.168.99.3:8099 sup, 192.168.15.9:53443 primenodetls, 192.168.5.12:443 node, 192.168.20.14:4444 search | "forward: public reverse proxy (NPM 10.20.0.2) to all vlans" (broad) | OPNsense DMZ allow exactly these seven; RB5009 accept from transit above its drops. Not boundary-crossing: proxy (192.168.5.5:81), omv.pibox (192.168.5.5:8080) and example.com (10.20.0.2:80) are pibox itself. Dead: secnodetls/tertnodetls point at 10.20.10.4/.3:9090, a subnet that no longer exists (F10) |
| 7 | caddy 10.20.0.7 to its boundary-crossing backends (from `/etc/caddy/Caddyfile`, read 2026-11-01): 192.168.15.9:5380 (primenodetls Technitium UI), 192.168.15.10:9090 and 192.168.15.11:9090 (secnodetls/tertnodetls, HTTPS), 192.168.99.2:8006 (pve), 192.168.5.5:8080 (pibox), **192.168.5.1:80 (RB5009 webfig, "map")** | "forward: local reverse proxy (caddy 10.20.0.7) to all vlans" (broad); :8006 live | OPNsense DMZ allow exactly these six; RB5009 accept from transit. The 192.168.5.1:80 one lands in the RB5009 **input** chain ("Local proxy input" + `www` service limited to 10.20.0.7) and keeps working without NAT, since the source stays 10.20.0.7 |
| 7a | Clients to caddy 10.20.0.7 tcp 80,443 (`*.home.arpa` front end for pve, the resolvers' UIs, pibox, map) | covered today only by the admin and mgmt "to all vlans" rules (flow 5); live from 192.168.99.10 | OPNsense TRANSIT allow (scope with flow 5) |
| 8 | buauth .9, bunode1 .13, bunode2 .14 to 192.168.5.12 tcp 1514,1515 | three per-host wazuh agent rules; live | OPNsense DMZ allow; RB5009 accept from transit |
| 9 | DMZ resolvers to internet 53/853 (upstream / DoT) | "forward: lan to wan"; QoS `up-dns` marks | OPNsense DMZ allow; DoT 853 per runbook |
| 10 | DMZ hosts to internet (updates) | "forward: lan to wan" | OPNsense DMZ allow 80/443 |
| 11 | pibox 10.20.0.2 to router NTP 192.168.15.1 / .25.1 / .30.1 udp 123 | input "NTP clients"; live | Point pibox at 10.20.0.1 (OPNsense NTP) or allow explicitly |

### Services the RB5009 provides to the DMZ (these move or change)

| # | Service | Today | After cutover |
|---|---|---|---|
| 12 | DHCP | `dhcp3` on bridge10, 5 reservations + 4 dynamic (table above) | Rebuild on OPNsense DMZ with the same reservations and options, then disable `dhcp3` (runbook Phase 5 step 3) |
| 13 | DMZ DNS enforcement | dst-nat any DMZ :53 not to resolvers -> 10.20.0.9 (+ hairpin masquerade, mangle mark); drops for 53/853 to non-resolvers; IPv6 equivalents | These match `src-address=10.20.0.0/25` / `in-interface=bridge10` and stop matching once DMZ traffic no longer routes through the RB5009. Rebuild on OPNsense DMZ (port forward + block) |
| 14 | DNS fallback automation | `dns-fallback-check` (30s) toggles the disabled fallback NAT rules | The DMZ half has nothing to act on after cutover. Decide whether OPNsense needs an equivalent |
| 15 | NTP | RB5009 NTP server, broadcast to 10.20.0.1 among others | Remove 10.20.0.1 from broadcast-addresses; OPNsense serves NTP on DMZ |
| 16 | CAPsMAN | `interfaces=bridge10`; the cAP connects **at the MAC layer** (`02:00:5E:FD:BC:11@bridge10`) | Keeps working as long as bridge10 stays a bridge on the RB5009 with `vlan10-edge` as a port (runbook design). Do not delete bridge10 |
| 17 | IPv6 | bridge10 has PD address `::1:0:0:0:1`, ULA `fd12:3456:789a:10::1`, RA advertising buauth/primenode DNS | Phase 7 / runbook step 10 |

## 4. Findings that change the plan

**F1. MTU: only caddy is jumbo, and it would black-hole through a 1500 gateway.** Host check: pibox's DMZ leg (br1/eth0) and the three libvirt VMs on it are 1500; caddy (ens18) is 9014. pibox's jumbo is on its VLAN 5 storage leg, so the DMZ no longer carries the NAS jumbo traffic. The OPNsense side of the USB trial (USB adapter, vmbr3, vtnet2) is 1500, so caddy could send >1500 frames to its gateway (e.g. to its VLAN 15 backends if they advertise a jumbo MSS) and they'd be dropped. bridge10 is `mtu=auto` and would also fall to 1500 once a 1500 `vlan10-edge` joins it. **Simplest fix: set caddy's ens18 to 1500 before cutover**, which makes the whole DMZ 1500 and matches the OPNsense path; then bridge10 auto-MTU is harmless (pinning it is optional). The alternative is to keep caddy at 9014 and enable MSS clamping on the OPNsense DMZ interface.

**Done 2026-11-01:** the 9014 came from Proxmox, not the guest: caddy's netplan only does DHCP, and the VirtIO NIC advertised vmbr0's 9014 as its MTU. Fixed on the host with `qm set 106 --net0 virtio=02:00:5E:C7:83:C0,bridge=vmbr0,tag=10,mtu=1500` (applied live; the NIC hot-replugged). Verified: ens18 mtu 1500, still 10.20.0.7, gateway pings, and pve, primenodetls and bauth all return 200 through caddy. The whole DMZ is now 1500.

**F2. The RB5009 loses its DNS servers at cutover.** `/ip dns servers` is empty; it uses the dynamic servers from the ether1 DHCP client (198.51.100.61-63). Disabling that client (Phase 5 step 4) leaves the router with no resolver, which breaks NTP client (pool.ntp.org names) and anything else resolving on the router. Add `/ip dns set servers=192.168.15.9,10.20.0.9` to the cutover script.

**F3. Runbook step 8 references a rule that doesn't exist.** There is no "drop not DSTNATed" rule. The equivalent ordering points are "forward: allow port-forwards" and "forward: drop all else". Step 9's "formerly rule 27" is `forward: clients to NPM reverse proxy (pibox: nextcloud, homepage, sup)`.

**F4. (Corrected after checking pibox.)** All NPM backends route out pibox's DMZ leg: `ip route get` for 192.168.20.2, 192.168.99.8 and 192.168.99.3 all give `via 10.20.0.1 dev br1 src 10.20.0.2`. pibox only uses its VLAN 5 leg for 192.168.5.0/28 (policy rule 200 for traffic sourced from 192.168.5.5) and the two DCs (192.168.20.6/.7, static routes). So the RB5009 rule `npm: Homepage + digest viewer` (src 192.168.5.5) and 192.168.5.5's entry in `supervisor-clients` look unused; NPM reaches those via the broad "public reverse proxy to all vlans" rule. Nothing bypasses the edge firewall.

**F5. caddy and NPM are allowed to every VLAN today.** Both have "to all vlans" rules. The OPNsense DMZ rules should name specific backends. caddy's list is now known (flow 7); its DMZ-internal backends (bauth 10.20.0.9:5380, bunode1/2 10.20.0.13/.14:9090) never cross the boundary and need no rule.

**F6. Switches and the cAP have DMZ IPs.** AG01, AG02, AG03 and the cAP pull dynamic leases on VLAN 10, so they are reachable at L3 from the DMZ. The cAP's lease is just its untagged management on ether4 pvid 10. The switches are probably DHCP clients on their VLAN 10 interfaces left over from setup. Consider disabling those clients (their real management is on VLAN 99, .4-.6).

**F7. MAC-level router management is reachable from the DMZ.** `mac-server` and `mac-winbox` use `MGMT-L2` = LAN minus IoT, and bridge10 is in LAN; `DISCOVERY` includes it too. After cutover the RB5009 still sits on bridge10 at L2, so exclude the `DMZ` list from both.

**F8. Stray MLAG setting on ether1.** `mgmtbridge99` has `mlag-peer-port=ether1`. ether1 is about to become the transit/DMZ trunk; clear it in the cutover script or before.

**F10. NPM publishes internal admin UIs on public names, and has two dead hosts.** `node.example.com` -> Wazuh dashboard 192.168.5.12:443, `primenodetls.example.com` -> Technitium 192.168.15.9:53443, `proxy.example.com` -> the NPM admin UI (:81), `sup.example.com` -> the agent supervisor chat, and `omv.pibox.example.com` -> OpenMediaVault. If any of these resolve publicly and lack an NPM access list, they're reachable from the internet through the WAN port forward. Decision 2026-11-01: no NPM access lists; each of these UIs already requires its own login, and a second auth layer isn't wanted. `secnodetls`/`tertnodetls` point at 10.20.10.4/.3, a subnet that no longer exists. Remove them or repoint them at 192.168.15.10/.11.

**F9. Resolved.** 10.20.0.10 (`02:00:5e:d6:2a:0f`) is the Living-Room Apple TV. It was moved to the IoT VLAN and now holds 192.168.25.4 from `dhcp6`. The bridge10 ARP entry is just stale. Nothing to allow.

## 5. Still to collect before Phase 4 rules
- buauth/bunode guest MTUs, from inside the VMs (host side is 1500, so they can't usefully be higher). Low priority.

## 6. Decisions for Phase 4 rules (2026-11-01)
- **Into the DMZ, keep today's behavior:** 192.168.5.9 and 192.168.99.0/28 reach any DMZ host on any port. All other internal VLANs reach only 10.20.0.2 tcp 80,443 and the DMZ resolver(s) on 53. caddy (10.20.0.7) stays admin/mgmt-only. The RB5009 transit address (172.16.255.2) is included for DNS (flow 4).
- **Out of the DMZ, tighten:** NPM only to its seven backends (flow 6), caddy only to its six (flow 7), Wazuh agents only to 192.168.5.12:1514,1515 (flow 8), resolvers DNS/DoT out, DMZ hosts 80/443 out (and NTP to OPNsense). Everything else from the DMZ into 192.168.0.0/16 is blocked.
- **No NPM access lists:** the admin UIs are published deliberately for remote access and keep their own logins (F10).
- **DMZ MTU 1500 everywhere** (caddy changed; F1).

