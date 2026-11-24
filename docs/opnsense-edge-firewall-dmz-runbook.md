# OPNsense edge firewall + dual-firewall DMZ: build runbook

**Created:** 2026-10-31
**Status:** Phases 0-4 done 2026-11-01 (USB trial path). Next: Phase 5 (stage the RB5009 cutover script). Phase 0 data and findings:
`opnsense-edge-phase0-record-2026-11-01.md`; read its findings F1-F9 before Phases 4 and 5.
**Goal:** put an OPNsense VM in front of the RB5009. OPNsense owns the WAN (NAT, inbound filtering,
Suricata IPS, port forwards) and is the gateway for the DMZ (VLAN 10). The RB5009 becomes a pure internal
router/segmentation firewall: no NAT, default route to OPNsense over a transit VLAN.

```
CM1200 --> [FW port A: WAN]
           [FW port B: inside] <==> RB5009 ether1  (trunk: VLAN 100 transit + VLAN 10 DMZ, tagged)
                                    RB5009 <==> ether3 / sfp1 trunks (unchanged)
                                        VLAN 10  -> bridged through to OPNsense (DMZ gateway moves)
                                        VLAN 5/15/20/25/30/99 -> still routed + filtered by RB5009
```

No recabling of the DMZ/IoT run on ether3 (AG03 / Asus). VLAN 10 stays on the same trunk; only its gateway
moves, at Layer 2.

## Placeholders (fill in before starting)

| Item | Value |
|---|---|
| Transit VLAN ID | 100 |
| Transit subnet | 172.16.255.0/30 (OPNsense .1, RB5009 .2) |
| OPNsense mgmt IP (VLAN 99) | 192.168.99.9/28 (verified: ARP resolves to VM 109 net0 02:00:5E:C2:9A:A7) |
| VMID / storage | 109 / EFI `local-lvm`, disk `hot1` (qcow2) |
| i226 PCI addresses | n/a for the USB trial (vtnet1/vmbr2 = WAN, vtnet2/vmbr3 = inside) |
| RB5009 ether1 MAC | 02:00:5e:b7:f7:b0 |
| Current public IPv4 | 203.0.113.10/23 (gw 203.0.113.1) |
| RB5009 bridge holding 10.20.0.1/25 | bridge10 |
| DMZ host MTU (check pibox DMZ leg) | 1500 everywhere (caddy changed from 9014 on 2026-11-01 via Proxmox net0 mtu=1500) |
| NPM | 10.20.0.2:80,443 |
| NPM backends (Nextcloud, Homepage, sup) | seven backends, all via the DMZ leg; see Phase 0 record flow 6 |
| Wazuh manager | 192.168.5.12 |

Each phase ends with a **Gate**: what must be true before the next phase.

---

## Phase 0: Prep (changes nothing)

Take a full export on the RB5009 (`/export file=pre-edge-fw`) and copy it off the router. Record ether1's MAC
(`/interface ethernet print where name=ether1`), the current public IPv4, and the bridge holding 10.20.0.1/25
(`/ip address print where address~"10.20.0.1"`).

Write down every flow crossing the DMZ boundary today: DMZ resolvers out on 853, LAN clients to NPM
10.20.0.2:80/443, NPM to its backends (Nextcloud, Homepage, sup), admin SSH into the DMZ, and anything else
found in firewall rules referencing the DMZ bridge or 10.20.0.0/25. Each becomes an explicit allow later;
anything missed breaks silently at cutover.

**Gate:** export saved off-router; flow list written.

## Phase 1: NIC and IOMMU check

Install the dual-port i226 in **PCIEX1_2** (bottom slot, clear of the GPU; the 82599 stays in PCIEX1_1).
Confirm it is alone in its IOMMU group:

```bash
lspci -nn | grep -i i226
for g in /sys/kernel/iommu_groups/*; do echo "Group ${g##*/}:"; for d in $g/devices/*; do echo "  $(lspci -nns ${d##*/})"; done; done | grep -B3 -A3 -i i226
```

Only i226 functions in the group = clear. If it shares a group with the RTL8125 (OOB port, enp9s0), a USB
controller, or SATA, **stop**. Do not use the ACS override (it defeats the isolation passthrough is for).
Fall back to the USB trial or a dedicated box.

### USB trial alternative

Bridge each adapter on the host with no IP; give the VM VirtIO NICs on them (no USB passthrough: FreeBSD
USB NIC drivers are unreliable and lack netmap).

**Done 2026-10-31:** both bridges built and applied on pve. The old `enx00051b97be67` (02:00:5e:96:8a:38)
stanza was removed from `/etc/network/interfaces`; that adapter is now the bedroom TV's 1G link (explains its
sighting on AG02's VLAN 25 port in the 10/26 notes) and is not part of this build.

| Bridge | Adapter | MAC |
|---|---|---|
| vmbr2 | `enx00051b637fea` | 02:00:5e:8f:d5:c6 |
| vmbr3 | `enxf8e43be51b52` | 02:00:5E:5A:EE:62 |

OPNsense sees only VirtIO MACs, never the adapter MACs, so roles map by NIC order: vtnet1 = vmbr2 = WAN
(modem goes into 02:00:5e:8f:d5:c6), vtnet2 = vmbr3 = inside (02:00:5E:5A:EE:62 to RB5009 ether1).
Applied config:

```
auto vmbr2
iface vmbr2 inet manual
        bridge-ports enx00051b637fea
        bridge-stp off
        bridge-fd 0
```

Same for `vmbr3` with `enxf8e43be51b52`. Trial only: the host bridge touches raw WAN frames, and a USB
dropout takes down the household internet.

**Gate:** clean IOMMU group (both PCI addresses recorded), or both USB bridges up with no host IP.

## Phase 2: Create the VM

```bash
qm create <vmid> --name fw-edge --machine q35 --bios ovmf --ostype other \
  --efidisk0 <storage>:1,efitype=4m,pre-enrolled-keys=0 \
  --cores 4 --cpu host --memory 8192 --balloon 0 \
  --scsihw virtio-scsi-single --scsi0 <storage>:32,discard=on,ssd=1 \
  --net0 virtio,bridge=vmbr0,tag=99 \
  --ide2 local:iso/<OPNsense-dvd-amd64.iso>,media=cdrom --boot order='scsi0;ide2' \
  --onboot 1 --startup order=1 --agent enabled=1
qm set <vmid> --hostpci0 <port A addr> --hostpci1 <port B addr>
```

- Ballooning must be off with PCI passthrough; 8 GB stays reserved (Suricata uses the headroom).
- `startup order=1` boots the firewall first after a host reboot.
- `net0` is a **permanent** VLAN 99 management NIC (use the bridge your other VLAN 99 guests use) so the GUI
  stays reachable when transit is broken.
- USB trial: replace the `hostpci` lines with `--net1 virtio,bridge=vmbr2 --net2 virtio,bridge=vmbr3`.
- Download the ISO straight to Proxmox: storage > ISO Images > Download from URL (amd64 DVD image from opnsense.org).

**Gate:** VM boots to the installer console.

## Phase 3: Install and base config

Console login `installer` / `opnsense`, install to ZFS, detach the ISO afterwards.

At the console, assign `vtnet0` as LAN: static 192.168.99.9/28, gateway 192.168.99.1. Assign the WAN-facing
i226 port as WAN and leave it unplugged.

VLAN 99 is locked down: add a temporary RB5009 rule letting 192.168.99.9 out on 80/443 for updates. In the GUI:

- Change the root password; set system DNS to the internal resolvers.
- Apply all updates; install `os-qemu-guest-agent`.
- System > Settings > Administration: bind GUI and SSH to the mgmt interface only; SSH key-only.
- Interfaces > Settings: disable hardware CRC, TSO and LRO (required for Suricata netmap, recommended in VMs).

**Gotchas hit on the 2026-11-01 build:**
- *Unreachable from VLAN 99 even though ARP worked:* giving LAN an upstream gateway (192.168.99.1) makes
  OPNsense add `reply-to` to LAN rules, so replies went to the RB5009 and died at "forward: isolate vlans".
  Fixed with Firewall > Settings > Advanced > **Disable reply-to**. At cutover, remove the LAN upstream gateway
  (WAN carries the default route).
- *Updates timed out:* OPNsense resolves through its local Unbound, which recurses to the root servers on 53,
  blocked by the DNS egress policy. Fixed with System > Settings > General: DNS 192.168.15.9, 10.20.0.9 and
  **Do not use the local DNS service as a nameserver for this system**. Stuck pkg lock cleared by reboot.
- The console flipped the GUI to HTTP; set back to HTTPS under Administration.
- Offload "Disable hardware ..." boxes (CRC, TSO, LRO) were already ticked by default.
- Temporary RB5009 rules for this phase: `fw-edge-temp:` x4 (DNS udp/tcp to dns-auth, 80/443 and 123 out)
  plus permanent `fw-edge: admin GUI/SSH in`, all above "forward: isolate vlans". Remove the temp ones after
  cutover.
- Config backup: `MikroTik & Service Configs/config-OPNsense.internal-20261101054607.xml`.

**Gate:** GUI reachable from the admin workstation; updates done; offloads off.

## Phase 4: Build the inside (inside port unplugged)

Keep the inside port unplugged so the duplicate 10.20.0.1 can't conflict with the RB5009.

**VLANs.** Interfaces > Devices > VLAN, on the inside i226 parent: tag 100 (transit) and tag 10 (DMZ).
Assign and enable both:

| Interface | Address | MTU |
|---|---|---|
| TRANSIT (VLAN 100) | 172.16.255.1/30 | 1500 (keeps path-MTU behavior to the internet as today) |
| DMZ (VLAN 10) | 10.20.0.1/25 | match DMZ hosts (do not guess; jumbo black-hole history) |
| inside parent | (none) | at least the DMZ MTU |

Interface names are FreeBSD-style (`igc0`, `igc1`, `vlan0.10`), not `eth0.10`. The console assignment screen
shows MACs to identify which physical port is which.

**Gateway and route.** Add gateway `RB5009_TRANSIT` = 172.16.255.2. Add one static route:
`192.168.0.0/16` via that gateway (covers every internal VLAN).

**Outbound NAT.** Switch to **Hybrid** and add a rule translating `192.168.0.0/16` to the WAN address.
Required: automatic NAT only covers directly connected networks, so without it nothing behind the RB5009
reaches the internet.

**Port forward.** WAN TCP 80,443 to 10.20.0.2. Enable NAT reflection if anything internal resolves public
names to the public IP (split DNS may already make this unnecessary).

**Rules (default deny), from the Phase 0 flow list:**

- **WAN:** only the port-forward rules; block private and bogon networks on.
- **DMZ:**
  - resolvers out on 853 (53 only if needed);
  - NPM 10.20.0.2 to its specific backend IPs/ports;
  - DMZ hosts out on 80/443 for updates;
  - block DMZ to 192.168.0.0/16 otherwise;
  - block DMZ to the firewall itself.
- **TRANSIT:**
  - 192.168.0.0/16 to the internet;
  - internal clients to DMZ resolvers on 53/853;
  - internal clients to 10.20.0.2 on 80/443;
  - admin SSH from the admin list into the DMZ;
  - block everything else into the DMZ.

**MAC clone.** Interfaces > WAN > MAC address: set the RB5009 ether1 MAC. the ISP binds the IPv4 lease to it,
so the public IP and DNS records should stay the same. No clash: the RB5009 ends up on a different segment.

**As built 2026-11-01 (OPNsense 26.7, all via the MVC pages/API):**
- Devices: `vlan01` (tag 100) and `vlan02` (tag 10) on vtnet2. Interfaces: TRANSIT = opt1 = vlan01
  172.16.255.1/30; DMZ = opt2 = vlan02 10.20.0.1/25, MTU 1500. No gateway set on either interface (avoids
  automatic reply-to).
- Gateway `RB5009_TRANSIT` 172.16.255.2 on TRANSIT, not default, monitoring off. Static route
  192.168.0.0/16 via it is saved **disabled**; enabling it before cutover would black-hole the admin desktop
  and OPNsense's DNS (192.168.15.9). Enable it in Phase 6.
- DHCP (Dnsmasq, interfaces LAN+DMZ, authoritative): DMZ range 10.20.0.2-126, lease 1800s, option 6 =
  10.20.0.9,192.168.15.9, nine reservations (pibox, caddy, buauth, bunode1/2, AG01-03, cAP) matching the
  current dhcp3 addresses.
- Aliases: INTERNAL_NETS, RFC1918, ADMIN_SRC (192.168.5.9/32, 192.168.99.0/28), DNS_CLIENTS_INTERNAL
  (+172.16.255.2), DMZ_NPM, DMZ_CADDY, DMZ_AUTH_RESOLVER, DMZ_RESOLVERS, WAZUH_MANAGER, PORTS_WEB, PORTS_DNS,
  PORTS_WAZUH, PORTS_MGMT.
- Source NAT hybrid: 100 WAN, INTERNAL_NETS -> WAN address; 110 DMZ hairpin for the DNS redirect.
- Destination NAT: 100 WAN tcp PORTS_WEB -> DMZ_NPM (pass); 110 DMZ tcp/udp 53 from !DMZ_RESOLVERS to
  !DMZ_AUTH_RESOLVER -> 10.20.0.9:53 (pass).
- DMZ rules 1010-1090: ping/NTP to the firewall; NPM to its 7 backends; caddy to its 6; Wazuh agents to the
  manager; block DMZ -> RFC1918 and -> firewall (logged); resolvers DNS/DoT out; 80/443, NTP, ICMP out.
- TRANSIT rules 2010-2060: ADMIN_SRC -> DMZ any; DNS_CLIENTS_INTERNAL -> buauth :53; INTERNAL_NETS -> NPM
  80/443; **2025 block IoT 192.168.25.0/24 -> DMZ** (2026-11-01 23:55, after 2020 so IoT DNS still works);
  **2035 CADDY_CLIENTS -> DMZ_CADDY 80/443** (added 2026-11-01 23:50; alias = 192.168.0.0/16 minus
  IoT 192.168.25.0/24; before this only ADMIN_SRC could reach caddy's sites); block -> DMZ (logged); RB5009 ping; **2047 ADMIN_SRC -> firewall PORTS_MGMT**; block -> firewall
  (logged); internal -> internet (!RFC1918).
- GUI and SSH listen on LAN + TRANSIT. WAN MAC cloned to 02:00:5e:b7:f7:b0.
- **Management moves to the transit IP (decided 2026-11-01).** OPNsense's VLAN 99 leg conflicts with the
  design: its automatic anti-spoof rule (`block in on ! vtnet0 from 192.168.99.0/28`) would drop every VLAN 99
  packet arriving via transit, and the direct leg makes replies to VLAN 99 asymmetric. After cutover the LAN
  leg is removed and the GUI is https://172.16.255.1 (reached via the RB5009); out-of-band access is the VM
  console in pve. See Phase 6.

**Gate:** config exported (System > Configuration > Backups); every Phase 0 flow has a rule.

## Phase 5: Stage the RB5009 cutover script (write it; don't run it)

The `.rsc` must:

1. Add `vlan100-transit` on ether1 with 172.16.255.2/30.
2. Add `vlan10-edge` on ether1 (DMZ MTU) and add it as a port of `bridge10`. Pin `bridge10 mtu=9014` first:
   it is `mtu=auto`, and a 1500 port would drag the whole DMZ bridge down (Phase 0 record F1).
3. Remove 10.20.0.1/25; disable `dhcp3`. DMZ hosts do rely on it (reservations .2, .7, .9, .13, .14), so
   rebuild DHCP with those reservations on OPNsense in Phase 4 first.
4. Disable the IPv4 and IPv6 DHCP clients on ether1. The router's DNS comes from that client (servers list is
   empty), so in the same step add `/ip dns set servers=192.168.15.9,10.20.0.9` (Phase 0 record F2).
5. Disable the masquerade rule and the WAN port forwards (find by comment; leave the DNS-egress dst-nat rules
   alone, they match LAN lists, not ether1).
6. Add `/ip route add dst-address=0.0.0.0/0 gateway=172.16.255.1 comment="edge-fw default"`.
7. Repoint every mangle/queue rule matching `out-interface=ether1` / `in-interface=ether1` to `vlan100-transit`
   (the `qos-up` rules and whatever feeds `cake-download`). Set `cake-nat=no` on `cake-up-class` (no NAT on
   the router anymore).
8. (Phase 0 record F3: there is no "drop not DSTNATed" rule; place the accepts above "forward: allow
   port-forwards" / "forward: drop all else".) Put `vlan100-transit` in the WAN interface list so the existing input drops protect the router. Insert
   explicit accepts for NPM-to-backend flows **above** the "drop not DSTNATed" rule: DMZ traffic now arrives
   over transit.
9. Review every filter rule naming the DMZ bridge as in/out-interface (e.g. "forward: clients to NPM reverse
   proxy", formerly rule 27). That traffic now enters/leaves via `vlan100-transit`.
10. IPv6: `ra-lifetime=0` on internal VLANs. Clients keep local v6 but stop using a v6 internet path that won't
    exist yet.

11. Housekeeping from Phase 0 (record F7, F8, 15): clear `mlag-peer-port=ether1` on `mgmtbridge99`; exclude
    the `DMZ` list from `MGMT-L2` and `DISCOVERY`; drop 10.20.0.1 from the NTP server's broadcast-addresses.
    Keep `bridge10` itself: CAPsMAN reaches the cAP at the MAC layer over it.

Write a matching rollback script that reverses each line.

**Written 2026-11-01:** `MikroTik & Service Configs/edge-fw-cutover.rsc` and `edge-fw-rollback.rsc` (24
commands each, in reverse order). Differences from the list above: no bridge10 MTU pin (the DMZ is 1500
everywhere now), bridge10's IPv6 addresses and RA are disabled so DMZ v6 can't route around OPNsense, and
the mlag-peer-port cleanup is left for after commit. Side effect to know: IoT VLAN 25's "internet" rule
matches anything out the WAN list, so IoT can now reach the DMZ subject to OPNsense's TRANSIT rules (DNS and
NPM 80/443 only).

**Gate:** script and rollback reviewed line by line.

## Phase 6: Cutover

Pick a window when the household is offline; pause Uptime Kuma / Discord alerts.

1. Enable Safe Mode on the RB5009 (Ctrl+X) from a VLAN 99 session.
2. Move the modem cable from ether1 to the firewall's WAN port.
3. Cable the firewall's inside port to ether1.
4. Run the cutover script.
5. Power-cycle the CM1200.

Verify, in order:

1. OPNsense WAN has its public IP and can ping 1.1.1.1.
2. Each end of the transit link pings the other.
3. `tracert` from a LAN client shows RB5009, then 172.16.255.1, then the ISP.
4. Name resolution works (resolver upstream DoT from VLAN 15 and the DMZ).
5. On pibox and the other DMZ hosts: `ip neigh flush 10.20.0.1` (they cached the RB5009's MAC), then confirm
   internet access.
6. `home.example.com` loads from a phone on cellular and from inside.
7. Nextcloud syncs.

8. OPNsense: enable the static route 192.168.0.0/16 via RB5009_TRANSIT (System > Routes).
9. From the admin desktop, load https://172.16.255.1 and SSH to it. Only once that works: remove the LAN
   leg. Clear the LAN upstream gateway (LAN_GW) first so WAN is the default, then unassign LAN (vtnet0) under
   Interfaces > Assignments, then `qm set 109 --delete net0` on pve. Disable reply-to can stay on.
10. Confirm VLAN 99 hosts (agent box 192.168.99.3, kuma .7, homepage .8, pve .2) reach the internet and
    their DMZ backends through transit.

All pass: exit Safe Mode to commit. WAN not up within ~15 minutes: modem cable back to ether1, run the
rollback script, power-cycle the modem.

Post-cutover cleanup: remove the four `fw-edge-temp:` rules and the `fw-edge-mgmt` address list on the
RB5009 (the `fw-edge: admin GUI/SSH in` rule pointed at 192.168.99.9 is also obsolete; transit traffic is
covered by "forward: lan to wan"). Point pibox's NTP at 10.20.0.1 (its current 192.168.x.1 servers are
blocked from the DMZ). Update Uptime Kuma and Homepage to monitor 172.16.255.1.

**Gate:** everything verified, plus 24-48 hours of normal household use.

**Cleanup status (2026-11-01 ~03:30-03:45):**
- Done: OPNsense LAN interface unassigned and `LAN_GW` deleted. VM 109 `net0` was removed, then **re-added as a
  disconnected placeholder** (`virtio=02:00:5E:C2:9A:A7,bridge=vmbr1,link_down=1`). Reason: FreeBSD numbers vtnet
  by PCI order, so with net0 gone the next boot would turn WAN (net1) into vtnet0 and the inside NIC into vtnet1,
  and the assignments (wan=vtnet1, VLANs on vtnet2) would land on the wrong ports. Leave the placeholder in.
- Done: the four `fw-edge-temp:` rules, `fw-edge: admin GUI/SSH in` and the `fw-edge-mgmt` list are gone (that
  list still pointed at 192.168.99.9, which DHCP now hands to `llm`). `mlag-peer-port` on mgmtbridge99 is `none`.
- Kept on purpose: the disabled v4 masquerade, `public: NPM 80/443` dstnat and dhcp3 on the RB5009. They're dead but
  `edge-fw-rollback.rsc` re-enables them; delete once the rollback window is over.
- Done: Homepage has an "Edge firewall" tile (Network group, siteMonitor https://172.16.255.1); backup of the old
  file is `services.yaml.pre-fw-edge` in the homepage CT (111).
- Done: Uptime Kuma monitors `fw-edge GUI` (https://172.16.255.1, TLS ignored) and `Internet via fw-edge` (TCP
  1.1.1.1:443; the Kuma CT is unprivileged and can't raw-ping).
- Done: pibox NTP now points at 10.20.0.1 (changed by the admin 04:05; OPNsense ntpd listens on the DMZ and is synced).
- Side effect found 03:50: OPNsense's LAN leg used **192.168.99.9**, which DHCP had also given to the `llm` CT
  (ollama :11434). The ARP clash made wazuh-triage's local-model call time out at 00:04 (Kuma "exit 1"). Fixed when
  the LAN leg was removed; llm's lease is now static. Lesson: pick a static IP outside the DHCP pool next time.

## Phase 7: Finish routing features

**IPv6 (done 2026-11-01, as-built).** Changed from the original PD-to-RB5009 idea to static routing:
- the ISP delegates `2001:db8:4a00:1f00::/56` to the OPNsense WAN (pd len 8, hint on). The prefix changed at
  cutover (old `2b00::/56`), so every GUA moved from `2b0x` to `1f0x`/`1f8x`.
- OPNsense: TRANSIT static `fd12:3456:789a:ff::1/64`; DMZ track6 id `0x1`, ifid `0x1` (= `1f01::1/64`) plus VIP
  `fd12:3456:789a:10::1/64`; radvd on DMZ (unmanaged/SLAAC, advertises both prefixes, RDNSS = buauth ULA).
  Gateway `RB5009_TRANSIT6` = `fd12:3456:789a:ff::2`; static routes `2001:db8:4a00:1f80::/57` and
  `fd12:3456:789a::/48` via it.
- OPNsense v6 aliases: `INTERNAL6` (ULA /48 + the /57), `DMZ_AUTH_RESOLVER6` / `DMZ_RESOLVERS6` (ULA hosts + a
  `dynipv6host` alias of their EUI-64 suffixes on DMZ, so GUAs follow a prefix change).
- OPNsense v6 rules: DMZ 1011/1021 (ICMPv6, NTP to firewall), 1061 block DMZ->INTERNAL6, 1066 block DMZ->self,
  1071 resolvers DNS/DoT out, 1081 web, 1086 NTP, 1091 ICMPv6 out. TRANSIT 2021 INTERNAL6->buauth :53,
  2041/2042 block into DMZ (GUA + ULA), 2046 RB5009 ICMPv6 to firewall, 2051 block mgmt over v6, 2061
  INTERNAL6->!INTERNAL6. No inbound v6 to the DMZ (same as before the cutover).
- RB5009: `edge-fw-ipv6.rsc` (rollback `edge-fw-ipv6-rollback.rsc`). Static `1f80::/57` slice
  (bridge30 `1f80`, bridge20 `1f82`, bridge25 `1f83`, bridge5 `1f84`, bridge15 `1f85`, mgmt99 `1f86`),
  transit `fd12:3456:789a:ff::2/64`, `::/0` via `ff::1`, RA lifetime 30m, address lists and RA DNS renumbered.
- Gotcha: the RB5009 learned a default route from OPNsense's DMZ RA through bridge10 (L2 pass-through), giving an
  ECMP default via the DMZ. Fixed with `accept-router-advertisements=no` (needs a **reboot** to apply), and until
  then an input drop of RA (type 134) on bridge10 plus `2000::/3` and `fd12:3456:789a:10::/64` routes via
  `ff::1`, which beat the stray default. Those can stay after the reboot.
- Gotcha 2 (found after the 03:17 reboot): RouterOS did not keep the `from-pool` hints, so bridge5 came back as
  `1f81` and bridge15 as `1f87`, which broke the resolver GUA in the lists/RA DNS. The VLAN GUAs are now plain
  static addresses (same numbers as above). Stale client prefixes (`2b0x`, `1f81`, `1f87`) are advertised with
  preferred-lifetime 0 / valid 2h; remove those `edge-fw: deprecate stale prefix` entries after a couple of hours.
  Also removed a stray static `::/0` via `fe80::be24:11ff:fe07:c60a%bridge10` (OPNsense DMZ link-local, no
  comment), and added `2001:db8:4a00:1fff::2/64` on vlan100-transit so the router's own v6 traffic has a
  routable source (it was using the transit ULA). Post-reboot check: single `::/0` via `ff::1`, v6 ping OK.
  04:12: deprecation entries removed. Found then that bridge20/25/30/mgmt99 had **no** GUA prefix in their RAs
  since the 03:22 re-add (only bridge5/15 did); toggling those addresses off/on regenerated all six. After any
  future change or reboot, check `/ipv6 nd prefix print where prefix~"^2600"` lists 1f80/82/83/84/85/86.
- If the ISP changes the /56: update the RB5009 `wan-pd` pool, the OPNsense `/57` route and `INTERNAL6`, and the
  `1f85`/`1f01` GUAs in the RB5009 address lists and RA DNS. The DMZ side follows automatically.
- Verified: OPNsense and RB5009 v6 internet; DNS to buauth over ULA and GUA from the RB5009; clients on VLANs
  20/25/30/99 picked up `1f8x` addresses with v6 states through OPNsense; DMZ hosts on `1f01` with outbound v6
  states; no v6 blocks for internal/DMZ ranges in the filter log.

**Consoles.** Static-port outbound NAT rule for the consoles' IPs, or `os-upnp` scoped to just those IPs.
*Done 2026-11-01:* consoles live on IoT VLAN 25 (wired) and Wi-Fi VLAN 30 (son's), so the rules cover both VLANs
via alias `CONSOLE_VLANS` (192.168.25.0/24, 192.168.30.0/24) instead of per-device IPs. Outbound NAT seq 90: UDP,
static port + endpoint-independent; seq 91: any protocol, static port. Both sit above the general seq 100 rule.
Existing states for both VLANs were cleared so the new mapping applies at once.

**Upload shaping.** DMZ upload now bypasses the RB5009's CAKE. Add an FQ-CoDel limiter on the OPNsense WAN at
38M and lower the RB5009 `cake-upload` a few Mbit/s below that. The RB5009 stays the active queue for LAN
traffic (keeping per-host fairness); OPNsense only queues when DMZ upload pushes the total over. (OPNsense is
FreeBSD: no CAKE.)
*Done 2026-11-01:* OPNsense pipe `WAN upload 38M (edge-fw)` (38 Mbit/s, fq_codel, ECN) with a rule on WAN
direction out, proto ip. RB5009 `cake-upload` and its four children dropped from 38M to 35M; queue type `cake-up`
set to 35M too. Waveform check still to run.

**Gate:** Waveform grades A from both a LAN client and a DMZ host; console NAT shows Open.

## Phase 8: Suricata

Services > Intrusion Detection, on the inside parent interface (covers both VLANs). Rules: ET Open plus the
abuse.ch lists. No NAT on the RB5009, so alerts name real internal hosts. Start in IDS mode, tune for about a
week, then switch to IPS.

*Done 2026-11-01 (IDS mode):* enabled on `vtnet2` (the inside parent, so both VLAN 10 and VLAN 100), pcap mode,
not IPS. Home nets: 192.168/16, 10/8, 172.16/12, `2001:db8:4a00:1f00::/56`, `fd12:3456:789a::/48`. Rulesets:
all ET Open files except `emerging-deleted`, plus the four abuse.ch lists (feodotracker, sslblacklist, threatfox,
urlhaus); the `opnsense.*` app-category sets are off. Cron 04:17 daily `ids update`. One ET rule fails to parse
(harmless). RAM after start: ~4 GB free of 8.
*Tuning 2026-11-02 00:25:* first day was ~9.3k alerts, almost all ET INFO noise. Disabled SIDs 2033078 (STUN on high
port), 2034636 (Python SimpleHTTP banner: Homepage/digest viewer behind NPM), 2031071 (Microsoft connection test),
2013504 (APT user-agent). User-defined rules **pass + bypass** for source 192.168.15.0/28 and
2001:db8:4a00:1f85::/64 (resolver VLAN 15: their DoT/DoH upstream to Quad9/Cloudflare/Google was ~75% of all
alerts); the DoH SNI rules stay on for every other host, so a client bypassing local DNS still alerts. Result: 69
alerts in the 5 minutes before vs 1 in the 5 minutes after. Kept on purpose: 2031502 (.env probes reaching Nextcloud
through NPM) and 2006380 (basic auth over HTTP, NPM -> Nextcloud AIO backend, handled in Wazuh below).
Wazuh (siem `local_rules.xml`, backup `.pre-suricata`): 100210 raises Suricata ET severity 1 (child of 86601) to
level 10 so wazuh-triage sees it; 100211 drops the expected NPM 10.20.0.2 -> Nextcloud 192.168.20.2 SID 2006380 to
level 0. Both checked with wazuh-logtest.
*IPS 2026-11-07 16:18Z (React2Shell, CVE-2025-55182):* 17 Wazuh 100210 alerts since 11-03, all 91.92.40.12 ->
10.20.0.2:80, bare-IP `POST /` that NPM's default server answers with 444 (never proxied; Homepage got nothing).
Blocked by behaviour, not IP: capture mode switched to **Netmap (IPS)** on `vtnet2` (vtnet2 now shows NETMAP, Suricata
runs `--netmap`, engine started clean, no interface errors); SIDs **2066027** (RSC), **2066028** (Vite RSC),
**2066029** (Waku RSC) set to **drop** via the Rules tab (`__manual__`). Every other rule is still alert-only, so the
tuning week continues. Pre/post checks identical: WAN ~14.5 ms, DMZ 10.20.0.2 ~1.8 ms, transit ~1.5 ms, NPM :80 open.
Rollback without the network: `qm guest exec 109` -> set `<mode>pcap</mode>` in IDS config, or GUI Settings -> PCAP.
Suricata only sees plaintext (port 80 and Cloudflare-to-origin HTTP), so the HTTPS side is covered on pibox NPM:
`/data/nginx/custom/server_proxy.conf` = `if ($http_next_action) { return 444; }`, included in all 12 proxy hosts;
tested `Next-Action` POST -> 000 (dropped), plain GET -> 401 (Access List, normal).
Apex loop, fixed 2026-11-07 16:34Z: NPM proxy host 17 (`example.com`) still forwarded to 10.20.0.2:80 (NPM
itself) after Zammad and its `/complaint` form were removed, so every request re-entered host 17 until "400 Request
Header Or Cookie Too Large" (one request at 09:29Z = 583 log lines). Advanced config now answers locally and proxies
nothing: `location / { return 401; }`, `error_page 401 /401.html;`, `location = /401.html { root /srv/complaint;
internal; }` (dead `/complaint` block removed). Page: `401.html` in the bind mount
`.../nginxproxymanager/data/complaint` -> `/srv/complaint` (source copy: `HTML Mockups & Images/homelab-401.html`).
Verified GET 401 / POST 401. The mount name `complaint` is cosmetic; rename in the NPM compose if wanted.
**Gate:** a week of IDS alerts reviewed; false positives suppressed.

## Phase 9: Monitoring and integration

- Install `os-wazuh-agent` (System > Firmware > Plugins). Point it at `<wazuh manager>`; enable intrusion
  detection events and firewall logs. Allow the mgmt IP to reach the manager on 1514/1515 on the RB5009.
  Leave active response (`opnsense-fw`) off until rules are tuned. Wazuh lists alerts, not every eve.json event.
- *Done 2026-11-01:* `os-wazuh-agent` installed, manager 192.168.5.12, agent name `fw-edge` (ID 021, Active).
  Log collection: audit, configd.py, dpinger, filterlog, firewall, kernel, pkg, suricata + Suricata eve. Active
  response and remote commands off. RB5009 rule `forward: fw-edge (OPNsense) wazuh agent to wazuh manager`
  (172.16.255.1 -> 192.168.5.12 tcp 1514,1515); the existing `agent: Wazuh agent to manager` rule only covers
  the agent-box list.
- Uptime Kuma: monitors for the firewall GUI and its WAN gateway.
- Schedule config backups; pulling `config.xml` into the mikrotik-audit diff puts the firewall in the daily digest.
  *2026-11-02:* done as a nightly push from OPNsense into mikrotik-audit (redacted diff, 0600 snapshots kept 180
  days); see claude-noc-agent-setup.md "mikrotik-audit now covers fw-edge".
- Take disk snapshots (no RAM state; passthrough rules that out) before major changes. The config backup is the
  real safety net.

## Optional later

- **Squid** (`os-squid`, plugin since 24.1): bump only domain machines (CA pushed by GPO), splice-list pinned
  apps, finance and health. Expect low hit rates on modern content. `web-proxy-sso` adds Kerberos user ID
  against home.arpa.
- **LANCache** for game downloads (DNS redirection, no TLS bump). Served from pve it is capped at ~400 MB/s
  until the 82599's PCIe x1 limit changes (see
  `Incident Reports & Postmortems/82599-pcie-x1-rx-drops-flow-control-2026-10-31.md`).

## Design notes

- **Transit hop:** 1G or 2.5G is enough. It only carries WAN traffic, capped by the 1G / 40M plan. Keep the
  RB5009's single SFP+ port on the LAN trunk.
- **Do not open the transit hop both ways.** The RB5009 accepts only established/related plus explicit DMZ
  backend flows from transit, so a compromised edge firewall doesn't get every VLAN.
- **pibox VLAN 5 leg:** isolated at the host level (only 80/443 to NPM exposed on the DMZ side). Verify Docker
  isn't publishing other ports past the host firewall: bind NPM's admin port 81 to localhost, or put drops in
  the `DOCKER-USER` chain, then port-scan from another DMZ host.

---
## Cutover log 2026-11-01
- Attempt 1 (~01:07): failed. The WAN USB adapter (AX88179B, cdc_ncm) re-enumerated on link change and fell out
  of vmbr2. Fix: udev rule `/etc/udev/rules.d/90-fw-edge-usb-bridge.rules` + `/usr/local/sbin/fw-edge-usb-attach`
  (installer: `Scripts - PIBOX & Agent Setup/fw-edge-usb-bridge-install.sh`), tested by toggling USB `authorized`.
- Attempt 2 (~01:28): internet came up through OPNsense, then the winbox session holding terminal Safe Mode
  dropped at 01:31:01 and the router auto-reverted. Cause: the admin PC is on VLAN 99, which loses internet until
  OPNsense's LAN leg is gone.
- Attempt 3 (~01:57): no Safe Mode (rollback = `/import file-name=edge-fw-rollback.rsc verbose=yes`, file on the
  router). Cutover script ran clean; OPNsense LAN (vtnet0) disabled right after. Verified: transit ping, router
  internet + DNS, VLAN 5 and VLAN 99 sources to 1.1.1.1, OPNsense WAN = 203.0.113.10/23.
- OPNsense pre-stage changes made for this: LAN_GW not upstream, WAN_DHCP gateway (dynamic, upstream, prio 1)
  added, 192.168.0.0/16 route enabled.
- Closed 2026-11-01 04:05: net0 (placeholder kept), temp rules, pibox NTP, Kuma/Homepage, mlag-peer-port, IPv6,
  upload shaping, Suricata (IDS), Wazuh agent. Still open: IPS switch
  after a week of tuning, deleting the rollback-only RB5009 rules once the rollback window is over.
- 02:20 fix: services were unreachable because the RB5009's WAN masquerade (uncommented srcnat rule 0) was still
  active. The cutover's `[find action=masquerade out-interface-list=WAN]` matched nothing, so every internal client
  reached OPNsense as 172.16.255.2, which TRANSIT only allows for DNS. Found by tcpdump on OPNsense vlan01 via
  `qm guest exec 109`. Disabled with `/ip firewall nat disable 0`; VLAN 20 -> NPM then connected. Scripts updated.
- 2026-11-01 23:50 fix: caddy's sites (pve/pibox/RB5009/Technitium UIs, A records -> 10.20.0.7) only worked from
  VLAN 99 and the admin desktop. Cause: TRANSIT had a rule for NPM (2030) but none for caddy, so other VLANs hit
  2040 "block -> DMZ" (filterlog showed 192.168.30.53, .20.8, .20.3 -> 10.20.0.7:80/443 blocked). Added alias
  `CADDY_CLIENTS` (192.168.0.0/16, !192.168.25.0/24) and rule 2035 -> DMZ_CADDY PORTS_WEB. Verified from VLAN 15
  (primenodetls CT): pve 200, pibox 200; no further blocks to caddy. Open: IoT 25 -> DMZ is now decided only by
  OPNsense (the RB5009's "IoT25: internet" rule matches the transit link because it is in the WAN list), and IoT
  could reach NPM internally via 2030. Closed 23:55 (the admin approved): TRANSIT rule **2025 block 192.168.25.0/24 ->
  DMZ net (logged)**, below 2020 so IoT keeps DNS to buauth, above the NPM/caddy rules. IoT internet (2060) is
  unaffected (24 IoT internet states right after); existing IoT -> DMZ states were killed. IPv6 already blocked
  IoT -> DMZ except DNS (2041/2042).
- 2026-11-02 00:48 fix (the admin approved): **buauth -> DC DNS was missing from the Phase 0 flow list.** buauth
  (10.20.0.9) forwards home.arpa to DC01/DC02 on 53; DMZ rule 1060 had dropped ~10k queries since the
  cutover, so AD names failed through the second DNS server every network gets (the 11-01 digest showed pibox's
  domain trust broken). Added alias `DOMAIN_CONTROLLERS` (192.168.20.6, .7) and DMZ rule **1055 DMZ_AUTH_RESOLVER
  -> DOMAIN_CONTROLLERS TCP/UDP 53**. Verified: dc01.home.arpa resolves via 10.20.0.9 from pve; 0 blocks after.
- 2026-11-02 00:50 rename: transit link is now **PUBLIC_HANDOFF** in OPNsense (opt1 description) and
  **vlan100-public-handoff** on the RB5009 (was vlan100-transit; references follow the rename). Gateways keep their
  names (RB5009_TRANSIT / RB5009_TRANSIT6). Workspace rollback/IPv6 scripts updated to the new name; the copy of
  edge-fw-rollback.rsc in the router's Files still has the old name -- re-upload before relying on it.
  Homepage got a "Public handoff" graph of that interface (lab-graphs, RouterOS REST, CAKE cap line 35); "WAN
  traffic" (ether1) unchanged.
- Fixed 2026-11-02 ~01:08 (approved): the agents box couldn't query buauth on 53 (daily-digest's DNS probe
  "NO_RESPONSE"). DMZ is now reached via the handoff (WAN list), so the old LAN->LAN DNS accept didn't match and
  `agent: drop all other egress` caught it. Added RB5009 rules "agent: DNS to auth resolvers (udp)" / "(tcp)"
  (agent-box -> dns-auth, dst-port 53) above that drop. Verified with dig udp+tcp from CT 107 against 10.20.0.9
  and 192.168.15.9 (both resolve dc01.home.arpa). No OPNsense change needed.
- Fixed 2026-11-02 ~01:30 (approved): buauth could resolve plain A records but every query that needed the DCs
  (SRV/_msdcs, e.g. `_ldap._tcp.dc._msdcs`) returned SERVFAIL "No Reachable Authority" -- so pibox (DNS = buauth via
  its DMZ leg br1 10.20.0.2) couldn't find a DC and its domain join/trust failed (Homepage pibox tile "DOMAIN FAIL").
  OPNsense rule 1055 passed the queries but got no replies. Cause on the RB5009: buauth's queries now arrive on
  `vlan100-public-handoff` (WAN list), so (a) RAW prerouting "drop in-interface-list=WAN dst-port=53" udp/tcp killed
  them, and (b) the filter accepts "forward: dns udp/tcp" only match in-interface-list=LAN. Added address-list
  `domain-controllers` (192.168.20.6 DC02, .7 DC01); RAW accepts "buauth (via fw-edge) DNS to DCs udp/tcp" above the
  WAN-53 drops; filter accepts "forward: buauth (via fw-edge) DNS to DCs udp/tcp" above "lan to wan". All scoped
  src 10.20.0.9 -> domain-controllers, port 53, in-interface vlan100-public-handoff. Verified SRV/_msdcs resolve
  via buauth. Lesson: anything in the DMZ that used to reach LAN directly now enters the router as "WAN" -- check
  RAW as well as filter.
- 2026-11-02 ~04:10 (approved) VLAN 5 (data plane) internet egress via Surfshark WireGuard, with kill switch.
  OPNsense: WireGuard instance SURFSHARK (wg0; keypair generated on-box, private key never left it; tunnel
  10.14.0.2/16, MTU 1420, routes disabled), peer surfshark-dal (us-dal.prod.surfshark.com:51820, allowed 0.0.0.0/0,
  keepalive 25; Surfshark key name "fw-edge"). Interface opt3 SURFSHARK (MSS 1380). Gateway SURFSHARK_GW 10.14.0.1
  (far gw, monitor 9.9.9.10, not default). Source NAT 95: opt3, 192.168.5.0/28 -> tunnel address.
  Filter: 10 (WAN out, block, tagged VLAN5_VPN, logged) = KILL SWITCH; 2055 (PUBLIC_HANDOFF in) 192.168.5.0/28 ->
  !RFC1918 via SURFSHARK_GW, tag VLAN5_VPN; 2056 block VLAN5_NET6 -> !INTERNAL6 (tunnel is v4-only); 1067 (DMZ in)
  block PIBOX_DMZ -> any (pibox's br1 leg can't egress unencrypted). "Skip rules when gateway is down" must stay OFF
  or the kill switch is bypassed (rule would vanish and 2060 would pass VLAN 5 straight out).
  pibox -- REVISED same night: first tried making pibox's main-table default VLAN 5 (netplan), but NPM runs in
  Docker on pibox at 10.20.0.2 (WAN 80/443 port-forward target) and its replies + backend connections then left via
  VLAN 5 -> NPM broke (~04:07-04:11). Reverted that routing (kept only the stale v6 policy prefix fix 2b04 -> 1f84 in
  /etc/netplan/50-pibox.yaml; backup /root/50-pibox.yaml.pre-vpn). pibox keeps default via 10.20.0.1 (br1), and
  OPNsense catches it on the DMZ side instead: alias PIBOX_DMZ (10.20.0.2 + its two v6 EUI-64 addrs), rule 1062 (DMZ
  in) PIBOX_DMZ tcp PORTS_WEB -> !RFC1918 via SURFSHARK_GW tag VLAN5_VPN (same port scope the DMZ already had),
  then 1067 block PIBOX_DMZ -> any (logged). Source NAT 96: opt3, 10.20.0.2 -> tunnel address. NPM inbound is
  untouched (state-matched); verified 24 established WAN->NPM states after the change and internal NPM HTTP 200.
  Lesson: before moving a dual-homed host's default route, check what's published on its other leg.
  Verified 2026-11-02 ~04:15: Wazuh manager 192.168.5.12 egress = 198.51.100.84 (Surfshark DAL). Kill switch: with
  the peer disabled and SURFSHARK_GW detected Offline (100% loss), VLAN 5 egress timed out -- no fallback to the
  bare WAN (OPNsense keeps route-to on the down gateway; tag block rule 10 is the backstop, 0 hits). NOTE: forcing
  the gateway "down" does NOT simulate failure (tunnel still carries traffic). Disabling the peer unlinks it from
  the SURFSHARK instance -- re-select it under the instance's Peers when re-enabling, then reconfigure gateways.
  pibox host egress confirmed via Surfshark (user curl ~04:19). Optional: pin pibox chrony to 10.20.0.1 in OMV.
- 2026-11-02 ~04:35 pibox DNS split by interface (user's design: VLAN 5 side uses the VLAN 15 DoT stack, DMZ side
  is buauth's job only). Was: resolved.conf DNS= listed primenode + buauth + dead 2b05/2b01 v6 addrs; drop-in
  resolved.conf.d/homelab-ad.conf DNS=10.20.0.9 192.168.15.9; br1 DHCP pushed buauth (OMV's 60-* file wins over
  50-pibox); stray runtime per-link servers on eth0/br1/enp1s0u1. Now: both resolved files DNS=192.168.15.9
  (backups /root/*.pre-dns); new /etc/netplan/70-pibox-dns.yaml (br1 dhcp4/6 + RA use-dns/use-domains false;
  enp1s0u1 nameservers 192.168.15.9 search home.arpa + route 192.168.15.9/32 via 192.168.5.1); runtime
  per-link reverted. Result: Global + enp1s0u1 = 192.168.15.9 only, nothing on br1/eth0; AD SRV + public lookups OK.
  Check after pibox's next reboot that eth0/br1 still show no servers. OMV interfaces store no DNS (DHCP); the
  10.20.0.9 hits in config.xml / openmediavault-firewall.sh are firewall rules. OMV has unrelated pending apt/rsyslog
  changes queued -- left alone.
  Rollback: disable 2055 (VLAN 5 back to bare WAN via 2060) -- also disable 10/1067 only if dropping the design.

- 2026-11-02 ~01:05 Homepage graphs, stacked in path order for correlating shifts: **WAN traffic** = OPNsense WAN
  port (VM 109 net1 via Proxmox netstat, OPNsense 38M cap line; repointed from ether1), **Public handoff** =
  RB5009 vlan100-public-handoff, **DMZ uplink** = RB5009 ether1 (trunk carrying VLAN 10 + 100). Reading them:
  ether1 ~= handoff + DMZ<->internal traffic; WAN ~= handoff + DMZ<->internet traffic. Patches:
  `Scripts - Monitoring & Audit/lab-graphs-handoff-patch.py` then `lab-graphs-three-links-patch.py`.

- 2026-11-03 ~03:55 Technitium AAAA cleanup after the prefix change (user request). Current GUA subnets: VLAN 5 =
  2001:db8:4a00:1f84::/64, VLAN 15 = :1f85::/64, DMZ = :1f01::/64; hosts keep the interface ID of their (unchanged)
  ULA record. primenodetls: bauth.com, bunode1.com, bunode2.com -> 1f01; node.local (Wazuh, was 4801) -> 1f84;
  pibox.com -> 1f84 (VLAN 5 token) + 1f01 (DMZ leg); primenodetls.com (was 2f02), secnodetls.com, tertnodetls.com ->
  1f85. buauth: bauth.com, bunode2.com -> 1f01; pibox.com -> 1f84 + 1f01. Names that point at Caddy (10.20.0.7) or
  NPM (10.20.0.2) are A-only and were not touched (incl. omv under pibox.com). Sweep afterwards: no GUA on an old
  prefix left on either server. Then (the admin's call, ~03:58): deleted the stale primenodetls.com AAAA
  fd00:db8:4a00:15::9, and the reverse zones for retired prefixes -- primenodetls: 2b00, 2b01, 2b03, 2b04, 2b05,
  2b06, 2f02, 4800, 4802 and the bogus fd00:db8:4a00:10/15 (11 zones); buauth: 2b00, 2b01, 2b03, 2b04, 2b06 (5).
  They held only PTRs for retired addresses. Kept: the fd12:3456:789a ULA reverse zones (05, 10, 15, 20, 99). No
  reverse zones existed yet for the current prefixes -- created next (~04:00, the admin's go): primenodetls got
  ip6.arpa zones for 2001:db8:4a00:1f01, :1f84 and :1f85 with a PTR for every current GUA AAAA (bauth, bunode1,
  bunode2, node.local, pibox x2, primenodetls, secnodetls, tertnodetls); buauth got 1f01 and 1f84 with PTRs for its
  own AAAAs (bauth, bunode2, pibox x2). TTL 3600. Add a PTR here whenever a new GUA AAAA is added.

- 2026-11-03 ~04:05 Technitium forwarder audit (the admin's request). Global forwarders were already pinned right:
  primenodetls -> secnodetls/tertnodetls DoT :853 by IP (192.168.15.10/.11); buauth -> bunode1/bunode2 UDP 53 by IP
  (10.20.0.13/.14 + their fd9a ULAs). The problem was the `home.arpa` conditional-forwarder zone on BOTH
  servers: it still listed the DCs' old GUAs on the retired 2001:db8:4a00:2b02 prefix, so AD lookups were being sent
  out the WAN to the ISP address space (seen in OPNsense's log on 11-02 as buauth -> 2b02:... :53 leaving vtnet1)
  and timing out; plus duplicate / trailing-space entries. Probed every target from each server first. Now:
  primenodetls -> 192.168.20.6, .7, fd12:3456:789a:20:a289:570d:62af:cf45 (DC02), :5033:2cef:f568:c921 (DC01) -- all
  answered in ~10 ms; DC GUAs deliberately not used (Windows rotates them per prefix, ULAs are stable).
  buauth -> 192.168.20.6, .7 only (its v6 to the DCs hangs 20 s: DMZ -> internal v6 is blocked by design, and the
  router/OPNsense buauth->DC exceptions are v4). buauth recursion changed Allow -> AllowOnlyForPrivateNetworks (same
  as primenodetls). Verified after: AD SRV, dc01 AAAA and a public name resolve on both (10-32 ms).
- 2026-11-03 ~04:12 Unbound access-control on all four Unbound nodes still allowed the retired
  2001:db8:4a00:2b00::/56, so anything querying from a current GUA got REFUSED. Replaced in
  /etc/unbound/unbound.conf.d/server.conf with 2001:db8:4a00:1f80::/57 (internal VLANs, = OPNsense INTERNAL6) and
  2001:db8:4a00:1f01::/64 (DMZ); unbound-checkconf clean, restarted; backup server.conf.pre-1f80 on each.
  secnodetls/tertnodetls (CT 104/105) via the pve console; bunode1/bunode2 (LXC on pibox) via their Cockpit terminals
  (sudo password entered by the admin; `unedit` = sudo nano on that file). Verified: primenodetls -> sec/tert over GUA
  DoT NoError; buauth -> bunode1/2 over GUA and ULA answered.
- Same time: primenodetls global forwarders now pinned on v4 + ULA + GUA, all DoT :853 (the admin's request):
  secnodetls 192.168.15.10, [fd12:3456:789a:15:be24:11ff:fe4d:4c62], [2001:db8:4a00:1f85:be24:11ff:fe4d:4c62];
  tertnodetls 192.168.15.11, [fd12:3456:789a:15:be24:11ff:fe15:71fa], [2001:db8:4a00:1f85:be24:11ff:fe15:71fa].
  End-to-end lookup OK. On the next prefix change, update these together: Unbound ACLs, Technitium AAAA + PTR zones,
  forwarder pins, the home.arpa forwarder zone.
- Same time: buauth global forwarders pinned the same way (UDP 53): bunode1 10.20.0.13,
  [fd12:3456:789a:10:216:3eff:fe0e:458d], [2001:db8:4a00:1f01:216:3eff:fe0e:458d]; bunode2 10.20.0.14,
  [fd12:3456:789a:10:216:3eff:fefd:c36a], [2001:db8:4a00:1f01:216:3eff:fefd:c36a].
- 2026-11-03 ~04:17 OPNsense radvd on DMZ (opt2): RDNSS now buauth ULA + GUA (fd12:3456:789a:10:216:3eff:fe0e:c59,
  2001:db8:4a00:1f01:216:3eff:fe0e:c59), matching how the RB5009 advertises both on its VLANs; radvd reconfigured,
  running. (RB5009 ND DNS per VLAN was already authoritative-only from the 11-01 IPv6 work -- edge-fw-ipv6.rsc; VLAN 15
  intentionally advertises none, its resolvers use public DNS.) DMZ hosts reach buauth on-link, so no rule needed.
- 2026-11-03 ~04:30 fw-edge's own resolver (the admin's go). Unbound was already enabled by default (all interfaces,
  full recursion from root) but idle: 0 queries in 24 h -- not the recursion source. Firewall's system DNS had been
  192.168.15.9 (unreachable from 172.16.255.1: the RB5009 RAW drop on WAN-list dst-port 53) plus "allow override by
  WAN DHCP" = the ISP DNS in plain text, with local Unbound excluded. Now: Unbound DoT upstreams (Services > Unbound
  > DNS over TLS) Cloudflare 1.1.1.1/1.0.0.1/2606:4700:4700::1111/::1001 (verify cloudflare-dns.com) and Quad9
  9.9.9.9/149.112.112.112/2620:fe::fe/::9 (verify dns.quad9.net), same providers the Unbound nodes use; DNSSEC on;
  ACL "refuse-non-local" 0.0.0.0/0 + ::/0 refuse (localhost still allowed; firewall rules already block :53 to self
  from DMZ/transit/WAN). System > General: DNS server list emptied, WAN override OFF, "do not use local DNS" OFF ->
  the firewall resolves only via 127.0.0.1 -> DoT. Verified: us-dal.prod.surfshark.com, pkg.opnsense.org,
  example.com resolve via 127.0.0.1 (57-180 ms); SURFSHARK_GW online. GOTCHA: /api/unbound/settings/add_forward
  forces type=forward even with type=dot -> Unbound sends plain UDP to :853 and gets nothing ("unsolicited udp reply
  dropped" at verbosity 3). Use add_dot / search_dot (or the DNS over TLS page). Independent of internal DNS, so the
  Surfshark endpoint still resolves at boot if primenodetls/buauth are down.
- 2026-11-03 ~04:35 Unbound `home.arpa` forward-zone cleanup. secnodetls/tertnodetls (CT 104/105)
  /etc/unbound/unbound.conf.d/forward.conf listed the DCs on an old 2001:db8:4a00:4803 prefix (dead). Replaced with
  the DC ULAs (fd12:3456:789a:20:5033:2cef:f568:c921 DC01, :a289:570d:62af:cf45 DC02) after testing both answer from
  each node; kept 192.168.20.6/.7. checkconf clean, restarted, AD SRV resolves; backup forward.conf.pre-dcula.
  bunode1/bunode2 have no home.arpa forward-zone (only private-domain/domain-insecure) and no old-prefix
  addresses -- nothing to change. Sweep: no 2b/2f/48xx-prefix addresses left in any live Unbound config.
- 2026-11-03 ~04:32 Considered and DECLINED (the admin, narrower footprint): adding home.arpa forwarding to
  bunode1/bunode2 as an AD fallback. It would need the DMZ->DC DNS exception (OPNsense rule 1055 + RB5009 raw/filter
  buauth rules) widened from buauth alone to three DMZ hosts. AD lookups from the DMZ stay buauth-only; don't
  re-propose without a reason that outweighs the wider exception.

- 2026-11-03 ~05:50 RB5009 QoS repaired (the admin's go). Found: since the 11-01 cutover every QoS mangle rule matched
  in-/out-interface=ether1, but WAN traffic now leaves on vlan100-public-handoff, so all marks and the whole CAKE
  queue tree (cake-download 775M, cake-upload 35M -> up-game/up-wifi/up-other/up-dns) passed 0 bytes; and fasttrack
  (forward, established/related, no exclusions) fast-pathed everything around mangle/queues anyway. Effective
  upload shaping was only OPNsense's 38 Mbit pipe.
  Changes: mangle "mark WAN download for cake" in-interface -> vlan100-public-handoff; mangle 6-11 (qos-up default,
  WiFi-Main wifi, admin workstation 5.9, laptop DESKTOP-K49Q9G5, resolver DNS udp/tcp) out-interface ->
  vlan100-public-handoff; fasttrack now `in-interface=!vlan100-public-handoff out-interface=!vlan100-public-handoff`
  (internal/inter-VLAN traffic incl. jumbo SMB to pibox still fasttracked, WAN traffic goes through CAKE).
  Verified: counters/queues now move (wan-down, up-other, up-dns). Under a speed test: cake-down 422-476 Mbps at
  55-62% total CPU (RB5009 4x1.4 GHz) -> watch CPU if downloads approach the 775M cap; if it saturates, lower
  cake-download max-limit or exempt download from CAKE. OPNsense 38M pipe left in place (router's 35M CAKE sits
  below it, so the router queue is where upload priority happens). Note: WiFi-Guest (VLAN 20) Wi-Fi clients land in
  up-other; the Wi-Fi class only matches WiFi-Main (bridge30).
  Rollback: /ip firewall filter set [find where action=fasttrack-connection] !in-interface !out-interface ; mangle
  rules back to ether1 (no effect either way since ether1 no longer carries WAN L3).
- Same session, Wi-Fi: CAPsMAN cAP ax (cAPGi-5HaxD2HaxD, 7.23.5) 5 GHz on 5260/ch52 80 MHz (52-64): 20 s scan found
  17 neighbours, none in 52-64 (strongest: the ISP router at -59/-60 on 36-48, adjacent). iPhone (WiFi-Guest, VLAN 20)
  heard at -73 dBm; live trace showed its upload reaching the router at only 8-18 Mbps and leaving 1:1 -> the
  limit is the client->cAP radio uplink (distance/walls), not interference or anything downstream. ether4 to the cAP:
  1 Gbps full, zero errors.
- Follow-up ~05:55: the first test still showed 923 down because IPv6 bypassed CAKE -- /ipv6 firewall mangle had the
  same seven QoS rules on ether1 and fasttrack6 had no exclusions. Same fix applied: v6 mangle 5 in-interface and 6-11
  out-interface -> vlan100-public-handoff; fasttrack6 in-/out-interface=!vlan100-public-handoff. Re-test (wired PC):
  cake-download held at 774-785 Mbps (the 775M cap) with total CPU 68-71% and busiest core 77-84%; cake-upload held
  34-35 Mbps. So the RB5009 can shape the full plan with ~15-20% single-core headroom. If the ISP plan goes up,
  re-check CPU before raising cake-download.
- 2026-11-03 ~06:10 "speedtest.net takes ~1 min to start" -- not our network. Ookla's web client probes candidate
  servers on :8080 first; AT&T Dallas (dlstxook.speedtest.sbcglobal.net, 12.255.189.70-72 / 2001:1890:200:44::6-8)
  never answers on 8080 (v4 and v6; its :443 answers), so the client waits ~30 s before giving up. Outbound 8080 is
  fine (portquiz.net :8080/:8443/:9000 connect in ~270 ms). Workaround: pin a nearby ISP server via Change Server, or
  use speed.cloudflare.com. Post-QoS results: Ookla 757/33 with ping 12/13/12 ms idle/down/up; Cloudflare test OK.
  (Waveform's bufferbloat test is separately broken on their side: speedtest-c0/c3.waveform.com fail the CORS
  preflight the test sends, so it aborts at "error getting cloudflare latencies".)
- 2026-11-03 ~06:20 Wi-Fi upload follow-up: iPhone next to the cAP doubled download but upload stayed ~10-11 Mbps,
  only on WiFi-Guest (laptop on WiFi-Guest 332/26.5; iPhone fine elsewhere) -> not signal, not router/QoS. Cipher idea
  dropped: sec-eap/cfg-wifi-guest set no encryption, so RouterOS default CCMP-128 only (no GCMP-256 offered). A/B test:
  FT off for WiFi-Guest -- /interface wifi security sec-eap ft=no ft-over-ds=no AND cfg-wifi-guest inline
  security.ft=no security.ft-over-ds=no (the inline values override the profile). Single cAP, so FT gave nothing.
  Applying it re-provisions the cAP radio (5 GHz clients drop a few seconds). Revert: set both back to yes.
  RESULT: iPhone on WiFi-Guest with FT off = 517/33 (was ~10 up) -> FT-EAP (802.11r over-the-DS with EAP) was the
  cause on iOS. Keep FT off for WiFi-Guest; revisit only if a second cAP is added (then test ft-over-ds=no first).
  Also flagged: the iPhone authenticates to WiFi-Guest as "Administrator".
- 2026-11-03 ~06:35 WiFi-Guest EAP from Windows (laptop DESKTOP-K49Q9G5, Wi-Fi MAC 02:00:5E:31:13:ED): NPS on DC01
  accepted labadmin from the laptop at 06:14/06:19 (6272), but after the 06:22 drop the laptop retried with its
  COMPUTER account (host/DESKTOP-K49Q9G5) -> 6273 reason 65 at 06:26. Cause: policy "802.x" (order 1; NAS-Port-Type
  wireless + Windows Groups + Called-Station "WiFi-Guest", VLAN 20 tunnel attrs) only listed Domain Users (-513), so
  machine auth fell through to the default deny policy. Dial-in on both accounts = "Control access through NPS".
  Fix (user approved): Windows Groups condition now Domain Users OR Domain Computers (-513;-515). Same log window:
  labadmin accepted from 02:00:5E:17:9C:C2 (06:26) and Administrator from 02:00:5e:c4:ad:41 (05:38, 06:23).
  GOTCHA: `netsh nps set np name=... conditionid=... conditiondata=...` REPLACES the policy's whole condition and
  profile set (wiped NAS-Port-Type, SSID, EAP config, VLAN attrs). Restored from export in ~20 s; the change was then
  made by editing NTGROUPS("...-513") -> NTGROUPS("...-513;...-515") in the export XML and `netsh nps import`.
  Backup: DC01 C:\Windows\Temp\nps-pre-machineauth.xml (contains RADIUS shared secrets in clear -- delete or move
  once confirmed). Rollback: `netsh nps import filename=<that file>`.
  Follow-up ~06:50: Windows "use my Windows account" still fails; parked by user (typed AD login works, keep using it).
  Findings: Credential Guard NOT running (SecurityServicesRunning=0). Laptop's original WiFi-Guest profile had
  authMode=machineOrUser, UseWinLogonCredentials=false, ServerNames empty, TrustedRootCA = DC01's RADIUS LEAF cert
  (69F8E087...) instead of Homelab-Root-CA (DD0D883C...). Machine-context PEAP at 06:39:27 did 4 Access-Challenge
  round trips then the client aborted (12013, 0x80070285 internal authentication error) -- consistent with server
  validation failing where no prompt is allowed. Profile was re-added (netsh wlan add profile ... user=all) with root
  CA DD0D883C..., ServerNames DC01.home.arpa, UseWinLogonCredentials=true, no server-validation prompt; still
  failed per user (not diagnosed further). Next time: read WLAN-AutoConfig 12013 + NPS IN*.log for the new attempt,
  or skip PEAP SSO and go GPO-deployed Wi-Fi profile / EAP-TLS with autoenrolled certs. Also noted: laptop
  LocalMachine\Root holds a self-signed CN=DESKTOP-K49Q9G5.home.arpa.
- 2026-11-03 ~08:20-09:00 Nextcloud uploads from VLAN 5 stalled (desktop sync: claude-noc-agent-setup.md and
  supervisor-setup.sh, ~92 KB each, "An unexpected error occurred"). Not Nextcloud: restarting the AIO container
  and rebooting VM 108 changed nothing. Reproduced from pve with curl through NPM (Expect: off, --resolve to
  10.20.0.2): sourced from 192.168.99.2, 100 KB/1 MB uploads finished in 0.06/0.2 s; sourced from 192.168.5.13,
  20 KB took 6.4 s and 100 KB/1 MB stalled. Cause: ASYMMETRIC path. VLAN 5 clients reach NPM via RB5009 -> handoff ->
  OPNsense -> DMZ, but pibox has a leg on VLAN 5 (main-table connected route 192.168.5.0/28 on enp1s0u1), so the
  replies went straight out that leg (tcpdump on pve: src MAC 02:00:5e:be:56:86, pibox's USB NIC). OPNsense only
  saw the client half and dropped data once it went past the window it could track. Started with the 11-01
  cutover (the RB5009's loose tracking tolerated it before). Laptop (VLAN 20) and anything not in 192.168.5.0/28
  were unaffected.
  First try, `ip rule from 10.20.0.2 table 110`, did nothing: NPM is Docker, and at routing time the reply's source is
  still the container address (rewritten to 10.20.0.2 after routing). Fix on pibox (the admin ran it): table 110 =
  default via 10.20.0.1 dev br1; mangle PREROUTING -i br1 ctstate NEW -> CONNMARK set 0x110; PREROUTING ! -i br1 and
  OUTPUT restore the connmark; `ip rule fwmark 0x110 table 110 priority 150`. Replies to connections that arrived
  on br1 now leave via br1; VLAN 5 SMB/NAS traffic and NPM's own backend connections are untouched. Verified:
  replies arrive from the router MAC 02:00:5e:5c:a3:9d, 100 KB/1 MB from 192.168.5.13 in 0.09/0.2 s, browser
  WebDAV PUT 100 KB/1 MB in 0.2/0.3 s, home/sup/digest 200 from VLAN 5. Persistence: oneshot
  `pibox-dmz-replies.service` -> /usr/local/sbin/pibox-dmz-replies (idempotent: ip route replace, rule add if
  missing, iptables -C || -A), After=network-online.target docker.service. An OMV firewall apply could flush the
  mangle rules; `systemctl restart pibox-dmz-replies` restores them. Removal: disable the unit, `ip rule del fwmark
  0x110 table 110`, and -D the three mangle rules.
- 2026-11-05 09:05 OPNsense rule 2056 (opt1/public handoff, inet6, VLAN5_NET6 -> !INTERNAL6) changed by the admin from
  block to REJECT (logging still on): VLAN 5 clients hold a GUA, try v6 first, and a silent drop made non-browser
  apps wait before falling back to v4. Context: Surfshark has no IPv6 at all (support article updated 2026-09-11:
  "does not support the IPv6 protocol"), so v6 egress for VLAN 5 would need a different provider (e.g. Mullvad
  carries v6 in WireGuard; would mean a v6 tunnel address, outbound NAT66 for VLAN5_NET6 and a v6 kill-switch rule).
  Alternative if anything still stalls: stop advertising the GUA prefix on VLAN 5 so clients only hold the ULA.
  Note: in 26.7 the API-created rules live under Firewall -> Rules (/ui/firewall/filter); there is no Automation menu.
- 2026-11-08 ~20:35 VLAN 5 flattened back onto the public handoff / bare WAN, IPv6 re-enabled (the admin's call:
  Surfshark subscription about to expire, no dual-stack WireGuard provider chosen yet). OPNsense rules DISABLED (not
  deleted): 2055 (VLAN 5 -> Surfshark), 2056 (VLAN5_NET6 reject), 10 (kill switch), 1062 (pibox DMZ leg -> Surfshark),
  1067 (pibox DMZ leg block). Applied; then deleted every state with route-to 10.14.0.1@wg0 (0 left). VLAN 5 v4 now
  exits via 2060, v6 via 2061; pibox's DMZ leg is back on the plain DMZ web-out rules 1080/1081. Verified from the
  admin workstation (192.168.5.9): v4 egress 203.0.113.10 (ISP), v6 egress 2001:db8:4a00:1f84:... native,
  api64 prefers v6. Left in place: WireGuard instance SURFSHARK / peer surfshark-dal, interface opt3, SURFSHARK_GW,
  outbound NAT 95/96 (only match on opt3, inert). Expect SURFSHARK_GW to go Offline once the subscription lapses.
  Restore the VPN design: re-enable 10, 2055, 2056, 1062, 1067 and apply (2056 needed again only while the tunnel is v4-only).
  When restoring, also move 1062 above block 1060 first: in its current position it can never match (found in the
  2026-11-23 rule export; harmless while it stays disabled).
- 2026-11-08 ~20:44 Ads leaking on WiFi-Guest (VLAN 20) -- cause: Technitium recursion "AllowOnlyForPrivateNetworks"
  on primenodetls (and buauth) treats only RFC1918 + ULA as private, so every query sourced from a GUA (2600:...)
  got REFUSED instead of blocked; the client (the admin's phone queries over its 1f82 GUA) then failed over and the ad
  domains resolved elsewhere. Seen in primenode's log: googleads.g.doubleclick.net from 2001:db8:4a00:1f82:... =
  Authoritative/Refused, 0 Blocked for any 2600: client, while v4/ULA clients were blocked normally. Blocking
  itself was healthy on both (enabled, 3 file blocklists, ~413k zones, no bypass list, test lookups NXDOMAIN).
  Fix (the admin approved): both servers Settings > Recursion = Use Specified Network ACL: 127.0.0.0/8, 10.0.0.0/8,
  172.16.0.0/12, 192.168.0.0/16, ::1, fc00::/7, fe80::/10, 2001:db8:4a00:1f80::/57 (internal = INTERNAL6),
  2001:db8:4a00:1f01::/64 (DMZ). Verified on primenode: GUA queries after the change = Recursive/NoError; self-test
  OK on both. buauth had no GUA clients in its last 1000 queries (internal v6 reaches it on the ULA only).
  Rollback: Recursion back to "Allow Only For Private Networks".
  ADD TO THE PREFIX-CHANGE LIST: the recursion ACL on primenodetls + buauth carries the GUA /57 and DMZ /64.
- 2026-11-08 ~20:55 iCloud Private Relay opted out network-wide (the admin's request; the phone kept relaying with
  Limit IP Address Tracking off). Blocked zones mask.icloud.com + mask-h2.icloud.com added on primenodetls AND
  buauth (blocking type NXDOMAIN = Apple's documented network opt-out); caches flushed on both; both names verified
  NXDOMAIN. Apple devices on any VLAN now show "Private Relay is unavailable" and resolve through local DNS.
  Rollback: Blocked Zones -> delete the two entries. Note: buauth's Query Logs (PostgreSQL) app stopped writing
  2026-11-05 15:25 UTC (dashboard stats still count) -- fix pending.
- 2026-11-08 ~21:05 DoT leaking across the public handoff: primenodetls's unbound-health-check probed secnodetls/
  tertnodetls every 30 s at their RETIRED GUAs (2001:db8:4a00:4802:...), so the probes went RB5009 -> handoff ->
  OPNsense -> WAN into the ISP space (always failing). Not client traffic and not OPNsense's Unbound (that one
  forwards only to Cloudflare/Quad9 DoT, ACL refuse-non-local, no client states to it). Fix (the admin ran it):
  /etc/unbound-health-check/config 4802 -> sec/tert ULAs fd12:3456:789a:15:be24:11ff:fe4d:4c62 / :fe15:71fa
  (backup config.pre-ula). The script then added the ULAs as forwarders: primenode now = sec/tert DoT on v4 + ULA.
  Verified: 0 OPNsense states to 4802; cache flushed, public names + AD SRV resolve. Workspace config/READMEs updated.
  ULAs chosen so the health check survives the next the ISP prefix change.
- 2026-11-08 ~21:07 buauth zone bauth.example.com had only the GUA AAAA; added the ULA AAAA
  fd12:3456:789a:10:216:3eff:fe0e:c59 (TTL 3600) with its PTR in buauth's existing fd9a:...:10 reverse zone (the admin's
  request). Now matches primenodetls's copy (A 10.20.0.9 + ULA + GUA). Verified: AAAA returns both, PTR resolves.
- 2026-11-08 ~21:12 AAAA parity for primenodetls.example.com + bauth.example.com on both servers (the admin's
  request). Addresses confirmed on the hosts (primenodetls `ip -6 addr`: 1f85:be24:11ff:fe6a:93b0 + fd9a:...:15:
  be24:11ff:fe6a:93b0; bauth per radvd RDNSS). Added: primenodetls server -> primenodetls zone ULA AAAA
  fd12:3456:789a:15:be24:11ff:fe6a:93b0 (+PTR in the fd9a:...:15 reverse zone); buauth server -> primenodetls zone
  GUA AAAA 2001:db8:4a00:1f85:be24:11ff:fe6a:93b0 (no 1f85 reverse zone on buauth, so no PTR there; primenode
  holds that PTR). bauth zone was already complete on primenode and fixed on buauth at ~21:07. Result: both
  zones return A + ULA + GUA identically on both servers. The *.home.arpa zones (A 10.20.0.7 = Caddy) are
  A-only by design and were left alone.
- 2026-11-08 ~21:40 Upload halved for everyone: the admin workstation (192.168.5.9) had an SMB session to pibox's
  DMZ address 10.20.0.2:445 (SMB multichannel -- smbd child named after the PC's 1f84 GUA session; ~11 GB in 65 min at
  ~30 Mbps). LAN->DMZ goes RB5009 -> vlan100-public-handoff -> OPNsense, so the RB5009 qos-up mangle (match =
  out-interface vlan100-public-handoff + admin MAC) put it in up-game (prio 1) and it filled the 35M cake-upload.
  pibox had NO 445/139 rule loaded (iptables/nft grep empty) despite the intended DMZ block. Fix (the admin, OMV SMB
  extra options): `interfaces = lo eth1` + `bind interfaces only = yes`. NOTE the VLAN 5 NIC is now named eth1
  (not enp1s0u1). Verified: smbd listens only on 192.168.5.5, eth1's 1f84/fd9a:..:5 addrs and loopback; the DMZ SMB
  states went to TIME_WAIT. Follow-ups: (1) RB5009 mangle (v4+v6) should skip traffic to 10.20.0.0/24 and the DMZ v6
  prefixes so LAN<->DMZ is never shaped as WAN upload; (2) check /etc/netplan/70-pibox-dns.yaml still names
  enp1s0u1; (3) OMV firewall rule for 445/139 on br1 missing/unapplied.
  Identified via `smbstatus -L` on pibox: the writer was Windows File History (desktop-01 -> Share/Filehistory,
  run "Backup Files 2026-11-08 203326", 74+ zip chunks) -- started 20:33, i.e. right as VLAN 5 v6 came back. After
  the smbd bind it reconnected at 21:40 and continues over VLAN 5 (eth1), off the handoff and out of CAKE.
- 2026-11-08 ~21:47 RB5009 QoS DMZ exclusion applied (the admin's go; record: MikroTik & Service Configs/
  qos-dmz-exclusion.rsc). Forward-chain mangle accepts for out-interface handoff -> dst 10.20.0.0/24 and in-interface
  handoff <- src 10.20.0.0/24, plus v6 equivalents on address-list qos-dmz6 (DMZ ULA fd12:3456:789a:10::/64 + GUA
  2001:db8:4a00:1f01::/64), placed after the dmz-dns-hairpin rules and before the WAN download marks. Verified order
  in print stats; v4 accepts matched 173 packets each within seconds; v6 at 0 (internal v6 -> DMZ is DNS-only by
  design). LAN<->DMZ traffic no longer enters cake-download/cake-upload. ADD TO THE PREFIX-CHANGE LIST: qos-dmz6 GUA.
- 2026-11-08 ~22:00 Cockpit "Software updates" failed with "Cannot refresh cache whilst offline" on primenodetls and
  the Unbound nodes. Cause: Ubuntu 26.04 LXCs run eth0 under systemd-networkd (PVE-written
  /etc/systemd/network/eth0.network + netplan 10-lxc.yaml); NetworkManager only sees it "connected (externally)" and
  reports STATE "connected (local only)" / CONNECTIVITY "limited", which PackageKit treats as offline. Real egress
  was fine (connectivity-check.ubuntu.com 204 on v4 and v6). Fix (the admin ran it on every node):
  `sudo systemctl disable --now NetworkManager && sudo systemctl mask NetworkManager && sudo systemctl restart
  packagekit && pkcon refresh`. PackageKit now uses the kernel/netlink monitor -> online; updates load. Trade-off:
  Cockpit's Network tab shows NM not running (container networking is managed from PVE). Don't use the NM "dummy
  connection" workaround (bogus gateway on a resolver) or netplan renderer NetworkManager (PVE rewrites networkd).
  Apply the same on any new Ubuntu LXC that gets Cockpit.
- 2026-11-08 ~22:22 Considered and DECLINED (the admin): joining buauth (DMZ) to home.arpa via Cockpit/realmd.
  `realm discover` resolves the DC SRV records but LDAP fails by design (OPNsense 1060/1061 + RB5009 port-53-only
  buauth exception). A join would need 88/389/636/445/464/3268-3269/RPC from the DMZ to both DCs. DMZ hosts stay
  off the domain (local accounts + SSH keys); don't re-propose without a specific need that justifies it.
- 2026-11-08 ~22:35 Wazuh CT 100 (siem) swap pinned at its 2 GB cap with RAM at ~4 of 8 GB. Cause: host-level
  reclaim (pve 41-46/62 GB used + ARC; fw-edge 7.9/8 GB, llm 9.3 GB) swaps cold pages across all cgroups, and the
  OpenSearch heap is mostly cold between GCs; swapped pages stay out until touched. Fix (the admin ran it):
  `pct set 100 --swap 0` (CT can no longer swap) and pve `vm.swappiness=10` (/etc/sysctl.d/90-swappiness.conf).
  Verified: CT 100 cfg swap=0, maxswap 0; residual 1.82 GB in swap returns only as pages are touched -- clear it with
  a wazuh-indexer restart or pve `swapoff -a && swapon -a` (host had ~21 GB free). Next: check `arc_summary` and
  cap zfs_arc_max if ARC is the pressure source.
  ~22:39 the admin ran `swapoff -a && swapon -a` on pve. Verified: CT 100 swap 0.00 GB, RAM 5.72/8 GB; host swap
  0.06/8 GB, host RAM 43.2/62 GB.
