# opnsense-edge-firewall

Moving the home lab's internet edge from a MikroTik RB5009 to an OPNsense VM on Proxmox (Suricata IPS, DMZ), with the RB5009 kept as the internal router. Includes the phased runbook, the phase-0 record of the pre-cutover state, the cutover write-up, and the RouterOS scripts used on cutover day, each with its rollback.

| Path | What it is |
|---|---|
| `docs/opnsense-edge-firewall-dmz-runbook.md` | phased runbook and running change log |
| `docs/phase0-record-2026-11-01.md`, `docs/phase0-runtime.txt` | pre-cutover state capture |
| `docs/cutover-2026-11-01.md` | cutover write-up |
| `mikrotik/edge-fw-*.rsc` | RB5009 cutover and IPv6 changes, each with a rollback script |
| `mikrotik/pre-edge-fw.rsc` | RB5009 export before the cutover (sensitive values hidden by RouterOS, identifiers sanitized) |
| `mikrotik/qos-dmz-exclusion.rsc` | CAKE QoS exclusion for DMZ traffic |
| `scripts/` | nightly OPNsense config push to the audit agent; USB-NIC bridge install for the WAN leg |

The raw OPNsense `config.xml` backups are deliberately not published (they hold password hashes and keys).

---

*Published from a home lab. Site identifiers are sanitized: public IPv4 uses the documentation ranges (203.0.113.0/24, 198.51.100.0/24), the delegated IPv6 prefix is `2001:db8::/32`, the ULA prefix is `fd12:3456:789a::/48`, domains are `example.com` / `home.arpa`, MAC addresses, Wi-Fi SSIDs, serials, keys and names are replaced. RFC 1918 addresses are left as they are so the layouts still read. Credentials are never in these files; scripts read them from `agent.env` or similar files that are not published.*
