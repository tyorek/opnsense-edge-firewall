#!/bin/bash
# fw-edge-config-push-install.sh -- run ONCE on pve as root (2026-11-02).
#
# Lets OPNsense (VM 109, fw-edge) push /conf/config.xml nightly to the agents box
# (CT 107) for mikrotik-audit, which diffs it and keeps restorable snapshots.
# The key OPNsense uses can do exactly one thing on the agents box: run
# receive-fw-config (forced command), only from 172.16.255.1, no tty/forwarding.
#
# Before running: add the RB5009 rule (winbox terminal):
#   /ip firewall filter add chain=forward action=accept protocol=tcp src-address=172.16.255.1 dst-address=192.168.99.3 dst-port=22 comment="agent: fw-edge config push in (forced-command key)" place-before=[find comment="agent: drop all other ingress"]
# After running: OPNsense GUI > System > Settings > Cron > + : minute 5, hour 2,
#   command "Push config.xml to agents box (mikrotik-audit)" (runs before mikrotik-audit at 02:15).
set -euo pipefail
VM=109
CT=107
D=/home/agent/agents/mikrotik-audit

# 1. OPNsense's public key (key pair generated 2026-11-02 at /root/.ssh/fw-config-push)
PUB=$(qm guest exec $VM -- cat /root/.ssh/fw-config-push.pub | python3 -c 'import json,sys; print(json.load(sys.stdin)["out-data"].strip())')
[[ "$PUB" == ssh-ed25519* ]] || { echo "could not read the key from OPNsense"; exit 1; }

# 2. Agents box: forced-command receiver + restricted authorized_keys entry
cat > /tmp/receive-fw-config <<'EOF'
#!/bin/sh
# Forced command for the fw-edge config-push key (see ~/.ssh/authorized_keys).
# OPNsense pipes /conf/config.xml on stdin nightly; mikrotik-audit picks it up from incoming/.
set -eu
D=/home/agent/agents/mikrotik-audit/incoming
umask 077
mkdir -p "$D"
tmp="$D/.fw-edge-config.xml.$$"
head -c 20000000 > "$tmp"
if [ -s "$tmp" ] && grep -q "<opnsense>" "$tmp"; then
    mv "$tmp" "$D/fw-edge-config.xml"
    echo ok
else
    rm -f "$tmp"
    echo rejected >&2
    exit 1
fi
EOF
printf 'restrict,from="172.16.255.1",command="%s/bin/receive-fw-config" %s\n' "$D" "$PUB" > /tmp/fw_authkey
pct push $CT /tmp/receive-fw-config /tmp/receive-fw-config
pct push $CT /tmp/fw_authkey /tmp/fw_authkey
pct exec $CT -- sh -c "
  install -d -o agent -g agent -m 755 $D/bin
  install -d -o agent -g agent -m 700 $D/incoming
  install -o agent -g agent -m 755 /tmp/receive-fw-config $D/bin/receive-fw-config
  install -d -o agent -g agent -m 700 /home/agent/.ssh
  touch /home/agent/.ssh/authorized_keys
  grep -q fw-edge-config-push /home/agent/.ssh/authorized_keys || cat /tmp/fw_authkey >> /home/agent/.ssh/authorized_keys
  chown agent:agent /home/agent/.ssh/authorized_keys
  chmod 600 /home/agent/.ssh/authorized_keys
  rm -f /tmp/fw_authkey /tmp/receive-fw-config"
rm -f /tmp/fw_authkey /tmp/receive-fw-config

# 3. OPNsense: push script + configd action (the action shows up as a Cron command).
#    OPNsense ssh is /usr/local/bin/ssh (fixed 2026-11-02 00:11; first run used /usr/bin/ssh and failed).
qm guest exec $VM -- sh -c "printf '%s\n' '#!/bin/sh' \
 '# Push config.xml to the agents box for mikrotik-audit (forced-command key there). 2026-11-02' \
 'exec /usr/local/bin/ssh -i /root/.ssh/fw-config-push -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 agent@192.168.99.3 < /conf/config.xml' \
 > /usr/local/sbin/fw-config-push && chmod 700 /usr/local/sbin/fw-config-push" >/dev/null
qm guest exec $VM -- sh -c "printf '%s\n' '[push]' 'command:/usr/local/sbin/fw-config-push' 'parameters:' 'type:script_output' \
 'message:pushing config.xml to the agents box' 'description:Push config.xml to agents box (mikrotik-audit)' \
 > /usr/local/opnsense/service/conf/actions.d/actions_fwconfigpush.conf && service configd restart" >/dev/null

# 4. Test push (needs the RB5009 rule above)
sleep 3
qm guest exec $VM --timeout 40 -- configctl fwconfigpush push | python3 -c 'import json,sys; d=json.load(sys.stdin); print("push test:", (d.get("out-data") or d.get("err-data") or "").strip())'
pct exec $CT -- ls -l $D/incoming/fw-edge-config.xml
echo "Done. Now add the Cron job in the OPNsense GUI (see header)."
