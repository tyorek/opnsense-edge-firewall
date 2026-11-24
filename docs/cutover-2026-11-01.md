# OPNsense edge firewall cutover: maintenance window postmortem

**Window:** 2026-10-31 (USB bridge prep) through 2026-11-01 04:30 CST
**Owner:** the admin (hands-on), with Claude driving OPNsense, the RB5009 and pve remotely
**Outcome:** complete. OPNsense (VM 109 `fw-edge` on pve) is now the internet edge and the DMZ gateway. The RB5009
routes the internal VLANs behind it over a /30 transit link. IPv4 and IPv6 both work end to end.
**Runbook:** `Runbooks & Setup Guides/opnsense-edge-firewall-dmz-runbook.md` (Phases 0-9 plus the cutover log)
**Phase 0 record:** `Runbooks & Setup Guides/opnsense-edge-phase0-record-2026-11-01.md`

> **Time note.** US daylight saving time ended at 02:00 CDT on 2026-11-01, in the middle of this window, so the
> 01:00 hour happened twice. Local times below are CST (UTC-6) unless marked CDT, and the timeline gives UTC too.

## Summary

The goal was to put a real firewall in front of the network and move the DMZ (VLAN 10) off the RB5009, so a
compromised DMZ host has to get through a stateful, logged policy before it reaches anything internal. The new
path is: the ISP modem > USB NIC > OPNsense WAN; OPNsense inside trunk (VLAN 100 transit, VLAN 10 DMZ) > RB5009
ether1. OPNsense does NAT, the port forward to NPM, DMZ DHCP, the DMZ and transit policy, IDS and logging. The
RB5009 keeps the internal VLANs, their DNS policy and CAKE, and no longer does NAT.

The cutover took three attempts. The first failed because the WAN USB adapter re-enumerated on link change and
dropped out of its bridge. The second worked, but the router auto-reverted when the Safe Mode session died. The
third stuck. Internal services then stayed unreachable for about 20 minutes because the RB5009's masquerade rule
was still on. After that the window covered IPv6 (which needed a design change and two post-reboot fixes), the
post-cutover cleanup, the Phase 7-9 features, a wazuh-triage outage caused by an address clash from the build,
and console NAT.

## Final state

| Component | State |
|---|---|
| OPNsense WAN (vtnet1 / vmbr2 / AX88179B `02:00:5e:8f:d5:c6`) | DHCP 203.0.113.10/23, MAC cloned to the RB5009's `02:00:5e:b7:f7:b0`; DHCPv6-PD `2001:db8:4a00:1f00::/56` |
| Transit (VLAN 100, `vlan01`) | OPNsense 172.16.255.1/30 + `fd12:3456:789a:ff::1/64`; RB5009 172.16.255.2 + `ff::2` + `2001:db8:4a00:1fff::2` |
| DMZ (VLAN 10, `vlan02`) | OPNsense 10.20.0.1/25, `2001:db8:4a00:1f01::1/64` (track6), VIP `fd12:3456:789a:10::1/64`; DHCP and RA from OPNsense |
| RB5009 | default `0.0.0.0/0` and `::/0` via OPNsense; no NAT; VLAN GUAs `1f80`-`1f86` static; CAKE upload 35M |
| Management | https://172.16.255.1 (GUI/SSH from ADMIN_SRC only); out of band = VM console in pve |
| VM 109 NICs | net0 = disconnected placeholder (`link_down=1`, keeps vtnet numbering), net1 = WAN, net2 = inside |
| Security | Suricata IDS on vtnet2 (ET Open + abuse.ch), Wazuh agent `fw-edge` (ID 021) reporting to 192.168.5.12 |
| Monitoring | Kuma: `fw-edge GUI`, `Internet via fw-edge`; Homepage: "Edge firewall" tile |

## Timeline

| Local | UTC | Event |
|---|---|---|
| 10-31 | | USB trial chosen over i226 passthrough. vmbr2/vmbr3 built on pve; stale `enx00051b97be67` stanza removed (that adapter is the bedroom TV's 1G link). |
| 10-31 | | IPv6 got disabled on the new bridges by mistake (see I-1); reverted from backup. |
| 11-01 ~00:00-00:45 CDT | 05:00-05:45 | VM 109 created; OPNsense 26.7 installed on ZFS (stripe); base config. reply-to and DNS problems fixed (I-2, I-3). |
| 00:46 CDT | 05:46 | Phase 3 config backup. |
| 00:50 CDT | 05:50 | Phase 0: full RB5009 export (`pre-edge-fw.rsc`) and runtime capture; DMZ inventory, flow list, findings F1-F10. caddy MTU 9014 > 1500 (F1). |
| ~01:00-01:45 CDT | 06:00-06:45 | Phase 4 built through the OPNsense API: VLANs, aliases, NAT, DHCP, DMZ/TRANSIT rules. Decision: manage over transit, drop the VLAN 99 leg. |
| 01:45 CDT | 06:45 | Phase 4 config backup. Cutover/rollback scripts staged. |
| 01:07 CST | 07:07 | **Cutover attempt 1** fails: WAN USB adapter re-enumerates and leaves vmbr2 (I-4). Rolled back. |
| ~01:20 CST | 07:20 | udev re-attach rule installed by the admin on pve and tested by toggling USB `authorized`. |
| 01:28 CST | 07:28 | **Attempt 2**: internet up through OPNsense, then the Safe Mode session dies at 01:31:01 and the router reverts (I-5). |
| 01:57 CST | 07:57 | **Attempt 3**: no Safe Mode, admin PC on the iPhone hotspot. Script runs clean; OPNsense LAN leg disabled. Internet works for every VLAN. |
| ~02:00-02:20 | 08:00-08:20 | Internet up but Nextcloud, NPM and other services unreachable. tcpdump on OPNsense shows every client as 172.16.255.2. RB5009 masquerade disabled at 02:20 (I-6). Services back; OPNsense GUI reachable on transit. |
| ~02:40-03:14 | 08:40-09:14 | IPv6 configured on both sides (I-7, I-8). Backup taken at 03:14. |
| 03:17 | 09:17 | RB5009 rebooted to apply `accept-router-advertisements=no`. Reboot shows renumbered VLANs and a stray v6 default (I-9, I-10); both fixed by 03:23. |
| 03:26-03:45 | 09:26-09:45 | Cleanup and Phases 7-9: LAN leg/net0, temp rules, mlag, Homepage, upload shaping, Suricata, Wazuh (I-11, I-12). |
| 03:47-04:00 | 09:47-10:00 | Kuma monitors added. wazuh-triage outage traced to the 192.168.99.9 clash (I-13); Claude fallback restored after the admin re-logged in. |
| 04:05 | 10:05 | pibox NTP repointed to 10.20.0.1 (the admin). |
| 04:08 | 10:08 | Console NAT for VLANs 25 and 30. |
| 04:10 | 10:10 | Final OPNsense backup (`config-OPNsense.internal-20261101101046.xml`). |
| 04:12 | 10:12 | Temporary stale-prefix announcements removed; missing RA prefixes found and fixed (I-14). |

## Work completed

**Hardware path and VM.** The two USB NICs (no i226 yet) are bridged on pve with no host IP, and the VM gets VirtIO
NICs on them, not USB passthrough. VM 109: q35/OVMF, 4 cores, `cpu host`, 8 GB with no balloon, ZFS root, guest
agent, `startup order=1`. udev rule `90-fw-edge-usb-bridge.rules` plus `/usr/local/sbin/fw-edge-usb-attach`
re-attach each adapter to its bridge by MAC whenever it re-enumerates.

**OPNsense base (Phase 3).** Root password, HTTPS GUI, SSH by key only, updates, guest agent. reply-to disabled. System DNS set to
192.168.15.9 and 10.20.0.9 with "do not use the local DNS service". Offloads were already off by default.

**Inside build (Phase 4).** Built from the Phase 0 flow list with explicit backend lists going out of the DMZ:
NPM to its 7 backends, caddy to its 6, the DMZ resolvers out on DNS/DoT, DMZ hosts out on 80/443, NTP and ICMP;
everything else from the DMZ to RFC1918 or to the firewall is blocked and logged. On transit, ADMIN_SRC gets
into the DMZ, internal clients reach buauth on :53 and NPM on 80/443, everything else into the DMZ is blocked,
and internal traffic goes out to the internet. The WAN port forward 80/443 goes to NPM and keeps today's inbound
behavior; the NPM admin UIs stay public on purpose because each has its own login (F10). The DMZ DNS redirect
hairpin is carried over from the RB5009. Dnsmasq serves DMZ DHCP with the nine existing reservations.

**RB5009 cutover (Phase 5/6).** `edge-fw-cutover.rsc`: VLAN 100 and VLAN 10 on ether1, transit IP, vlan10-edge into
bridge10, 10.20.0.1 removed, dhcp3 off, bridge10 IPv6 off, CAKE mangle moved to vlan100-transit with cake-nat off,
ND ra-lifetime 0 (later restored), MGMT-L2/DISCOVERY exclude the DMZ (F7), NTP broadcast to 10.20.0.1 dropped,
ether1 DHCP clients off, DNS set to 192.168.15.9/10.20.0.9, masquerade and NPM dstnat off, default route via
172.16.255.1. On OPNsense: WAN_DHCP is the upstream gateway, LAN_GW is no longer upstream, and the
192.168.0.0/16 route is enabled.

**IPv6 (Phase 7).** OPNsense holds the /56 and gives the DMZ `1f01` by track6. It statically routes
`1f80::/57` and the ULA /48 to the RB5009 over fixed ULA next-hops, so the transit link doesn't depend on the ISP
prefix. The RB5009 numbers its VLANs out of that /57 (`1f80` bridge30, `1f82` bridge20, `1f83` bridge25,
`1f84` bridge5, `1f85` bridge15, `1f86` mgmt99) and advertises a 30-minute default again. Its address lists and
RA DNS were renumbered from `2b0x` to `1f0x`/`1f8x`. The OPNsense v6 rules mirror the v4 policy, using
`dynipv6host` aliases so the resolver GUAs follow any future prefix change. The DMZ RA hands out buauth's ULA as
DNS. The plan to have Kea delegate a prefix to the RB5009 was dropped for static routing (simpler, and it survives
a renumber on the transit side).

**Cleanup.** OPNsense LAN interface and LAN_GW deleted. net0 removed and re-added as a disconnected placeholder
(I-11). The four `fw-edge-temp` rules, `fw-edge: admin GUI/SSH in` and the `fw-edge-mgmt` list deleted.
`mlag-peer-port=none` on mgmtbridge99 (F8). `llm`'s DHCP lease made static. Homepage tile and Kuma monitors added.
pibox NTP moved to 10.20.0.1. The disabled masquerade, the NPM dstnat and dhcp3 stay on the RB5009 for now
because `edge-fw-rollback.rsc` re-enables them.

**Phases 7-9.** Upload: an OPNsense FQ-CoDel pipe at 38 Mbit/s on WAN out, with RB5009 `cake-upload` and its
children lowered from 38M to 35M, so the RB5009 keeps per-host fairness and OPNsense only queues when DMZ upload
pushes the total over. Console NAT: alias `CONSOLE_VLANS` (192.168.25.0/24, 192.168.30.0/24) with
static-port outbound NAT, plus endpoint-independent mapping for UDP. Suricata in IDS (pcap) mode on vtnet2 with
all ET Open sets except `emerging-deleted` plus four abuse.ch lists, home nets including both v6 ranges, and a daily
04:17 rule update. Wazuh agent with Suricata eve plus filterlog, audit, configd, dpinger, kernel and pkg logs;
active response off. 266 Suricata alerts had reached the manager within 35 minutes.

## Issues and root causes

| # | Issue | Root cause | Fix | Whose |
|---|---|---|---|---|
| I-1 | IPv6 disabled on the new USB bridges | Claude added it unasked during bridge setup | Reverted from backup; runbook corrected | Claude |
| I-2 | GUI unreachable from VLAN 99 although ARP worked | LAN had an upstream gateway, so OPNsense added `reply-to` and replies went to the RB5009 and died at "isolate vlans" | Firewall > Advanced > Disable reply-to | Config default |
| I-3 | Firmware updates timed out | Local Unbound recursed to the roots on :53, which the DNS egress policy blocks | System DNS to the internal resolvers + "do not use local DNS"; stuck pkg lock cleared by reboot | Design interaction |
| I-4 | Attempt 1: no WAN | AX88179B (cdc_ncm) re-enumerated on link change and came back outside vmbr2 | udev rule re-attaches by MAC on add/move | Hardware |
| I-5 | Attempt 2: router auto-reverted | The Safe Mode session came from the admin PC on VLAN 99, which loses internet until OPNsense's LAN leg is removed; the session died at 01:31:01 | Attempt 3 without Safe Mode, PC on hotspot, rollback file on the router | Plan |
| I-6 | Services unreachable after cutover (~20 min) | The script's masquerade find (`action=masquerade out-interface-list=WAN`) matched nothing, so rule 0 kept NATing every client to 172.16.255.2, which TRANSIT only allows for DNS | `/ip firewall nat disable 0`; both scripts fixed to match the uncommented rule | Claude (script) |
| I-7 | RB5009 had an ECMP v6 default via the DMZ | It accepted OPNsense's DMZ RA through bridge10 (L2 pass-through) | `accept-router-advertisements=no` (needed reboot), RA drop on bridge10, `2000::/3` and DMZ ULA routes via transit | Design gap |
| I-8 | RDNSS pointed DMZ hosts at OPNsense | radvd default advertises the interface's own address | RDNSS = buauth ULA | Default |
| I-9 | After reboot, VLAN GUAs renumbered (bridge5 `1f81`, bridge15 `1f87`), breaking resolver GUAs in lists and RA DNS | RouterOS didn't keep the `from-pool` hints across a reboot | Static GUAs; stale prefixes advertised deprecated for ~50 min | Claude (design) |
| I-10 | Static `::/0` via OPNsense's DMZ link-local on bridge10 | Origin unknown (no comment, not in the pre-cutover export) | Removed | Unknown |
| I-11 | Removing net0 would have swapped WAN and inside on the next boot | FreeBSD numbers vtnet by PCI order; without net0, net1 becomes vtnet0 | net0 re-added as a link-down placeholder; checked vtnet0/1/2 MACs | Caught before reboot |
| I-12 | Router's own v6 traffic failed | Its only address on transit was ULA, so it sourced from ULA | Added `1fff::2/64` on transit | Claude (design) |
| I-13 | wazuh-triage "exit 1" at 00:04 | OPNsense's LAN leg used static 192.168.99.9, which DHCP also gave `llm` (ollama). The ARP clash timed out the local model; the Claude fallback then failed on an expired login | Clash ended when the leg was removed; `llm` lease made static; the admin re-logged in; reran OK | Claude (IP choice) + expired login |
| I-14 | VLANs 20/25/30/99 advertised no GUA prefix for ~50 min | Dynamic ND prefixes weren't regenerated after the 03:22 address re-add (no outage: the same numbers were still valid on clients) | Toggled the addresses; all six advertised | Claude (change order) |

Other friction, recorded for the next big change: noVNC drops Shift, Winbox focus slips, and the pve xterm console
needs JS paste plus an explicit Enter. The automation guardrails declined two steps (installing the udev rule and
a dead-man revert scheduler), so the admin ran the first and the second was replaced by the hotspot approach. During
the I-6 investigation the admin PC's hotspot link was dropped by a Claude action while in production; the admin was
watching and it caused no harm.

## What went well

- The Phase 0 inventory paid off. The explicit NPM/caddy backend lists, the MTU check (F1) and the RB5009 DNS gap
  (F2) were all handled before cutover instead of found during it.
- Keeping the internet-cutting commands last and the rollback script on the router meant each failed attempt
  rolled back cleanly.
- Driving OPNsense through the MVC API, and running `qm guest exec` inside the VM, gave exact, repeatable changes
  and fast diagnosis (tcpdump on vlan01 found I-6 in minutes).
- The transit design (fixed private next-hops, no NAT on the RB5009) means alerts and logs name real internal
  hosts, and an ISP renumber only touches the delegated side.

## What went poorly / lessons

1. **Find-and-set commands need to be tested against the live config before the window.** I-6 came from a `find`
   that silently matched zero rules. Next time, run every `find` as a `print count-only` during staging.
2. **Pick static IPs outside the DHCP pool and check the lease table.** I-13 would have been avoided by checking
   192.168.99.9 against the leases first.
3. **Safe Mode has to come from a path that survives the change.** For an edge cutover that means the hotspot
   (or the router console), not a VLAN that loses internet partway through.
4. **On RouterOS, `from-pool` hints aren't durable.** With a static upstream prefix, use static addresses.
5. **Removing a virtual NIC from a FreeBSD guest renumbers everything after it.** Keep a link-down placeholder.
6. **Don't change things outside the ask.** I-1 was an unrequested change.
7. **Unattended jobs shouldn't depend on an interactive login.** triage's Claude fallback should use a
   `claude setup-token` token.

## Verification

IPv4: transit ping, router internet and DNS, VLAN 5 and VLAN 99 sources out to 1.1.1.1, NPM reachable from VLAN 20
after the masquerade fix, all services confirmed back by the admin, OPNsense GUI over transit. IPv6: OPNsense and RB5009 ping out; DNS to buauth over ULA and GUA from
the RB5009; clients on VLANs 20/25/30/99 with `1f8x` addresses and v6 states through OPNsense; DMZ hosts on `1f01`
with outbound v6 states; no v6 drops for internal ranges in the filter log; single `::/0` after the reboot.
Services: Kuma all up (including both new monitors), Wazuh agent Active, Suricata alerts at the manager,
wazuh-triage written by Claude at 04:00, OPNsense ntpd synced (stratum 2) and listening on the DMZ.

## Open items

- DC02: 107 bursts of failed Windows logons (rule 60204), still firing at 03:56. Check the 4625 sources.
- wazuh-triage: switch the Claude fallback to a `claude setup-token` token.
- Waveform bufferbloat test from a LAN client and a DMZ host.
- Suricata: suppress the Quad9 DoH SNI alert for the three resolvers; check the 4 "basic auth over HTTP" alerts.
  Move to IPS after about a week of tuning.
- After 24-48 h of normal use: delete the RB5009 masquerade, `public: NPM 80/443` dstnat and dhcp3.
- After any RB5009 reboot: `/ipv6 nd prefix print where prefix~"^2600"` should list `1f80/82/83/84/85/86`.
- Laptop DESKTOP-K49Q9G5: Wazuh agent queue full (dropping events).
- Longer term: replace the USB trial with the i226 card (passthrough), per Phase 1.

## Artifacts

- `MikroTik & Service Configs/pre-edge-fw.rsc`, `phase0-runtime.txt`: pre-cutover state
- `MikroTik & Service Configs/edge-fw-cutover.rsc`, `edge-fw-rollback.rsc` (rollback copy also on the router)
- `MikroTik & Service Configs/edge-fw-ipv6.rsc`, `edge-fw-ipv6-rollback.rsc`
- `MikroTik & Service Configs/config-OPNsense.internal-*.xml`: backups at 05:46, 06:46, 09:14, 10:06 and **10:10 UTC (current)**
- `Scripts - PIBOX & Agent Setup/fw-edge-usb-bridge-install.sh`: udev re-attach installer
