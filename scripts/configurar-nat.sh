#!/usr/bin/env bash
# CastroCloud · Saída a Internet de OPNsense a través do seu nodo.
#
# Por que: os nodos son MV de VirtualBox en ponte sobre a wifi. A wifi só
# deixa pasar o tráfico da propia MV, non o das máquinas que van dentro
# (outras MAC), así que OPNsense non chegaría ao router. Si chega ao nodo, e
# o nodo si chega ao router: OPNsense sae pola rede interna vmbr2
# (10.99.0.0/30, creada por Terraform en rede.tf) e o nodo fai NAT
# (masquerade). Os servidores das VLANs saen por OPNsense. Nun CPD con cable
# non faría falta: a WAN de OPNsense iría directa ao router.
#
# Execútase como root en pve1 e pve3 (os nodos con servizos), unha vez:
#   ssh root@192.168.0.211 'bash -s' < scripts/configurar-nat.sh
#   ssh root@192.168.0.213 'bash -s' < scripts/configurar-nat.sh
#
# Opción: REDE_SAIDA (rede interna de OPNsense, por defecto 10.99.0.0/30).

set -euo pipefail

REDE_SAIDA="${REDE_SAIDA:-10.99.0.0/30}"
PONTE="${PONTE:-vmbr0}"

[[ $EUID -eq 0 ]] || { echo "ERRO: hai que executalo como root" >&2; exit 1; }
command -v nft >/dev/null || apt-get install -y nftables

# 1. Reenviar paquetes e non mandar «redirects» ao router
cat > /etc/sysctl.d/90-castrocloud-nat.conf <<FIN
net.ipv4.ip_forward = 1
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.$PONTE.send_redirects = 0
FIN
sysctl -q --system

# 2. NAT: todo o que saia de OPNsense leva a IP do nodo
cat > /etc/castrocloud-nat.nft <<FIN
table ip castrocloud_nat
delete table ip castrocloud_nat
table ip castrocloud_nat {
    chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        ip saddr $REDE_SAIDA masquerade
    }
}
FIN
nft -f /etc/castrocloud-nat.nft

# 3. Que se aplique tamén despois de cada reinicio
cat > /etc/systemd/system/castrocloud-nat.service <<'FIN'
[Unit]
Description=CastroCloud: NAT para a saída a Internet de OPNsense
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/nft -f /etc/castrocloud-nat.nft
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
FIN
systemctl daemon-reload
systemctl enable -q castrocloud-nat.service

echo "==> NAT activo en $(hostname -s) para $REDE_SAIDA:"
nft list table ip castrocloud_nat
