#!/usr/bin/env bash
# CastroCloud · Converte este equipo no router da rede do laboratorio.
#
# PLAN B: a demo vai pola wifi e este script NON se usa. Só fai falta se a wifi
# do instituto non deixa que os equipos se vexan e hai que unilos cun cable.
#
# Uso:   sudo ./rede-laboratorio.sh            (activar)
#        sudo ./rede-laboratorio.sh --quitar   (desfacer)
#
# Rede do laboratorio: 10.20.0.0/24, polo cable Ethernet (IFACE, por defecto eno1).
#   10.20.0.1      este equipo (pasarela dos nodos e dos contedores)
#   10.20.0.2      o PC con Windows (opcional, só para abrir a web de Proxmox)
#   10.20.0.11-13  nodos de Proxmox pve1, pve2 e pve3
#   10.20.0.101+   contedores creados con Terraform
#
# Como a rede é propia e vai polo cable, o clúster funciona igual na casa
# que no instituto: non depende da wifi nin do seu rango de enderezos.
# A saída a Internet faise por NAT a través da conexión que teña o equipo (wifi).

set -euo pipefail

IFACE="${IFACE:-eno1}"
REDE="10.20.0.0/24"
IP_EQUIPO="10.20.0.1/24"
CONEXION="castrocloud-lab"
TABOA="castrocloud"

[[ $EUID -eq 0 ]] || { echo "ERRO: executar con sudo" >&2; exit 1; }

if [[ "${1:-}" == "--quitar" ]]; then
    nft delete table ip "$TABOA" 2>/dev/null || true
    nmcli connection delete "$CONEXION" 2>/dev/null || true
    echo "==> Rede do laboratorio quitada (o reenvío IPv4 vólvese desactivar ao reiniciar)"
    exit 0
fi

# 1. IP fixa no cable, cun perfil propio de NetworkManager (sen pasarela: Internet segue pola wifi)
if ! nmcli -t -f NAME connection show | grep -qx "$CONEXION"; then
    nmcli connection add type ethernet ifname "$IFACE" con-name "$CONEXION" \
        ipv4.method manual ipv4.addresses "$IP_EQUIPO" ipv4.never-default yes \
        ipv6.method disabled connection.autoconnect yes >/dev/null
    echo "==> Creado o perfil $CONEXION ($IP_EQUIPO en $IFACE)"
fi
if ! nmcli connection up "$CONEXION" >/dev/null 2>&1; then
    echo "AVISO: o perfil non se puido activar. Está o cable conectado en $IFACE?"
    echo "       Activarase só ao conectar o cable."
fi

# 2. Reenvío de paquetes entre interfaces
sysctl -qw net.ipv4.ip_forward=1

# 3. NAT: o tráfico da rede do laboratorio sae a Internet coa IP deste equipo
nft delete table ip "$TABOA" 2>/dev/null || true
nft -f - <<EOF
table ip $TABOA {
    chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        ip saddr $REDE oifname != "$IFACE" masquerade
    }
}
EOF

echo "==> Listo: $REDE con saída a Internet a través deste equipo"
ip -br address show "$IFACE"
