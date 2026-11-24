# Paste this whole block into the pve shell (as root). Installs a udev rule that re-attaches the
# OPNsense USB-trial NICs to their bridges after they re-enumerate (seen 2026-11-01: the AX88179B
# drops off the USB bus on link changes and comes back outside vmbr2).
cat > /usr/local/sbin/fw-edge-usb-attach <<'EOF'
#!/bin/sh
# Re-attach a hot-plugged USB NIC (matched by MAC) to its Proxmox bridge. Called from udev via systemd-run.
mac="$1"; br="$2"; ifc=""
for n in 1 2 3 4 5 6 7 8 9 10; do
  ifc=$(ip -o link | awk -v m="$mac" 'tolower($0) ~ m { n=$2; sub(":$","",n); sub("@.*","",n); if (n ~ /^enx/) { print n; exit } }')
  [ -n "$ifc" ] && break
  sleep 1
done
[ -n "$ifc" ] || { logger -t fw-edge-usb "no enx interface for $mac"; exit 0; }
ip link set dev "$ifc" master "$br" && ip link set dev "$ifc" up
logger -t fw-edge-usb "attached $ifc ($mac) to $br"
EOF
chmod 755 /usr/local/sbin/fw-edge-usb-attach
cat > /etc/udev/rules.d/90-fw-edge-usb-bridge.rules <<'EOF'
# OPNsense USB trial: USB NICs re-enumerate on link changes and drop out of their bridge. Re-attach them.
ACTION=="add|move", SUBSYSTEM=="net", ATTR{address}=="02:00:5e:8f:d5:c6", RUN+="/usr/bin/systemd-run --no-block /usr/local/sbin/fw-edge-usb-attach 02:00:5e:8f:d5:c6 vmbr2"
ACTION=="add|move", SUBSYSTEM=="net", ATTR{address}=="02:00:5e:5a:ee:62", RUN+="/usr/bin/systemd-run --no-block /usr/local/sbin/fw-edge-usb-attach 02:00:5e:5a:ee:62 vmbr3"
EOF
udevadm control --reload && echo RULES-LOADED
# To remove later (e.g. after moving to the i226 card):
#   rm /etc/udev/rules.d/90-fw-edge-usb-bridge.rules /usr/local/sbin/fw-edge-usb-attach && udevadm control --reload
