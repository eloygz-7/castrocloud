# OPNsense: cortalumes e VLANs de CastroCloud

OPNsense enruta as VLANs da troncal e aplica as regras do cortalumes. Terraform
crea a máquina virtual (`terraform/opnsense.tf`); a instalación e a
configuración fanse unha vez, a man, seguindo estes pasos.

## Rede

| Interface OPNsense | Tarxeta | Rede | IP de OPNsense | Que hai |
|---|---|---|---|---|
| WAN | vtnet0 (vmbr2) | 10.99.0.0/30 | 10.99.0.2, pasarela 10.99.0.1 (o nodo) | Saída a Internet co NAT do nodo |
| LAN (ADMIN) | vtnet1 sen etiqueta | 192.168.56.0/24 | 192.168.56.2 | Equipo de administración (192.168.56.1) |
| SERVIZOS | vtnet1, VLAN 10 | 10.10.10.0/24 | 10.10.10.1 | ct-nextcloud .11, ct-web .12, ct-servizos .13 |
| XESTION | vtnet1, VLAN 20 | 10.10.20.0/24 | 10.10.20.1 | ct-zabbix .11 |
| IAAS | vtnet1, VLAN 30 | 10.10.30.0/24 | 10.10.30.1 | Servidores dos clientes (.100–.199) |

## 1. Crear a MV e a rede (Terraform)

Primeiro só a rede e OPNsense, para que os servidores non perdan a conexión
antes de ter OPNsense listo:

```bash
cd terraform
terraform apply -target=proxmox_network_linux_bridge.troncal -target=proxmox_network_linux_bridge.saida -target=proxmox_virtual_environment_vm.opnsense
```

E o NAT da saída de OPNsense en pve1 e pve3:

```bash
ssh root@192.168.0.211 'bash -s' < scripts/configurar-nat.sh
ssh root@192.168.0.213 'bash -s' < scripts/configurar-nat.sh
```

## 2. Instalar (consola da MV 200 na web de Proxmox)

1. Entrar como `installer`, contrasinal `opnsense`.
2. Instalar en UFS no disco `da0`, poñer o contrasinal de root e reiniciar.
3. En `terraform.tfvars`, `opnsense_instalado = true` e `terraform apply -target=proxmox_virtual_environment_vm.opnsense` (quita o DVD).

## 3. Interfaces (consola, opcións 1 e 2)

1. Opción **1) Assign interfaces**: LAGG non; VLANs si, sobre `vtnet1`, etiquetas 10, 20 e 30.
   WAN = `vtnet0`; LAN = `vtnet1`; OPT1 = `vlan010`; OPT2 = `vlan020`; OPT3 = `vlan030`.
2. Opción **2) Set interface IP address**, con IP fixas e sen DHCP:
   WAN `10.99.0.2/30` con pasarela `10.99.0.1`; LAN `192.168.56.2/24`;
   OPT1 `10.10.10.1/24`; OPT2 `10.10.20.1/24`; OPT3 `10.10.30.1/24`.

## 4. Web (https://192.168.56.2)

O equipo de administración chega ás VLANs por OPNsense (a ruta pide sudo e
pérdese ao reiniciar):

```bash
sudo ip route add 10.10.0.0/16 via 192.168.56.2
```

1. Asistente: nome `opnsense`, dominio `castrocloud.lan`, DNS `1.1.1.1` e `9.9.9.9`.
   Na WAN, **desmarcar «Block private networks» e «Block bogon networks»**: a
   WAN é unha rede privada (10.99.0.0/30).
2. Interfaces: renomear OPT1, OPT2 e OPT3 a SERVIZOS, XESTION e IAAS, e
   activalas.
3. Firewall → Aliases: `REDES_INTERNAS` = `10.10.0.0/16`, `192.168.56.0/24`.
4. Firewall → Rules (en orde, a primeira que coincide gaña):

| Interface | Acción | Orixe | Destino | Para que |
|---|---|---|---|---|
| LAN | permitir | LAN net | calquera | Administración: chega a todo (xa vén creada) |
| SERVIZOS | bloquear | SERVIZOS net | IAAS net | Os servizos non entran nos servidores dos clientes |
| SERVIZOS | permitir | SERVIZOS net | calquera | Internet e o resto de servizos |
| XESTION | permitir | XESTION net | calquera | Zabbix chega aos axentes de todos os servidores |
| IAAS | permitir | IAAS net | 10.10.10.13, porto 53 | DNS de CastroCloud |
| IAAS | bloquear | IAAS net | REDES_INTERNAS | Os clientes do IaaS quedan illados |
| IAAS | permitir | IAAS net | calquera | Só Internet |

O NAT de saída (Firewall → NAT → Outbound) queda en automático: OPNsense
traduce as redes internas á IP da WAN.

## 5. Mover os servidores ás VLANs

```bash
cd terraform && terraform apply                       # novas IP e VLAN
terraform output -raw inventario_ansible > ../ansible/inventario.ini
cd ../ansible && ansible-playbook sitio.yml          # DNS, LDAP, Zabbix, web...
```

## 6. Copia da configuración

System → Configuration → Backups → Download. Gárdase en
`ansible/segredos/opnsense-config.xml`, fóra de git, porque leva os
contrasinais cifrados. Ademais, a MV entra na copia diaria do PBS.
