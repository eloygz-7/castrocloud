variable "proxmox_endpoint" {
  description = "URL da API de Proxmox (calquera nodo do clúster)"
  type        = string
  default     = "https://192.168.0.211:8006/"
}

variable "proxmox_api_token" {
  description = "Token da API no formato usuario@realm!id=segredo. Vai en terraform.tfvars, que non se sube a git."
  type        = string
  sensitive   = true
}

variable "nodos_servizos" {
  description = <<-EOT
    Nodos que executan os servizos. pve2 (o PC con Windows) queda fóra por falta
    de recursos: só achega o quórum do clúster e a copia secundaria do PBS.
  EOT
  type        = list(string)
  default     = ["pve1", "pve3"]
}

variable "contedores" {
  description = "Servidores dos servizos: nome => nodo preferido, ID, VLAN, IP, RAM (MB), disco (GB) e núcleos"
  type = map(object({
    nodo    = string
    vm_id   = number
    vlan    = string
    ip      = string
    ram     = number
    disco   = number
    nucleos = number
  }))
  default = {
    ct-nextcloud = { nodo = "pve1", vm_id = 211, vlan = "servizos", ip = "10.10.10.11", ram = 1536, disco = 10, nucleos = 2 } # Nextcloud e o seu MySQL
    ct-web       = { nodo = "pve3", vm_id = 212, vlan = "servizos", ip = "10.10.10.12", ram = 512, disco = 4, nucleos = 1 }   # WordPress con Nginx e MySQL
    ct-servizos  = { nodo = "pve3", vm_id = 213, vlan = "servizos", ip = "10.10.10.13", ram = 512, disco = 2, nucleos = 1 }   # lldap e Bind9
    ct-zabbix    = { nodo = "pve3", vm_id = 214, vlan = "xestion", ip = "10.10.20.11", ram = 1024, disco = 4, nucleos = 1 }   # Zabbix e o seu MySQL
  }
}

variable "ssh_clave_publica" {
  description = "Clave pública SSH coa que Ansible entra como root nos servidores (crear con: ssh-keygen -t ed25519)"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "ip_nodos" {
  description = <<-EOT
    IP de cada nodo na wifi. Os servidores xa non os usan como pasarela: saen
    a Internet por OPNsense (ver rede.tf e opnsense.tf).
  EOT
  type        = map(string)
  default = {
    pve1 = "192.168.0.211"
    pve2 = "192.168.0.212"
    pve3 = "192.168.0.213"
  }
}

variable "pasarela" {
  description = "Pasarela da wifi (o router); non a usan os servidores dos servizos (ver ip_nodos)"
  type        = string
  default     = "192.168.0.1"
}

variable "dns" {
  description = "Servidores DNS dos contedores"
  type        = list(string)
  default     = ["1.1.1.1", "9.9.9.9"]
}

variable "disco_zfs" {
  description = "Disco de cada nodo para o pool ZFS «datos» (o segundo disco da MV, baleiro)"
  type        = string
  default     = "/dev/sdb"
}

variable "replicacion_cada" {
  description = "Cada canto se replican os contedores ao outro nodo de servizos (formato de calendario de systemd)"
  type        = string
  default     = "*/5"
}

# Un Proxmox Backup Server en cada nodo (ver configurar-pbs.sh). Os datos de cada
# un móstraos o script e van en terraform.tfvars. Un PBS sen datos non se crea.
variable "pbs" {
  description = "PBS de cada nodo: nome do nodo => IP e pegada (fingerprint) do certificado"
  type = map(object({
    servidor = string
    pegada   = string
  }))
  default = {}
}

variable "pbs_segredos" {
  description = "Segredo do token castrocloud@pbs!pve de cada PBS (en terraform.tfvars, que non se sube a git)"
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "pbs_principal" {
  description = "Nodo cuxo PBS recibe a copia diaria; os outros tráena del cada noite"
  type        = string
  default     = "pve1"
}

variable "pbs_almacen" {
  description = "Almacén (datastore) do PBS onde se gardan as copias"
  type        = string
  default     = "copias"
}

variable "pbs_token_id" {
  description = "Token do PBS con permiso só para facer copias"
  type        = string
  default     = "castrocloud@pbs!pve"
}

variable "copia_hora" {
  description = "Hora da copia diaria de todo o clúster"
  type        = string
  default     = "02:00"
}

variable "plantilla_lxc" {
  description = "Plantilla oficial de Proxmox para os contedores LXC (Debian 13: Docker e Ansible funcionan sen axustes)"
  type = object({
    url    = string
    sha512 = string
  })
  default = {
    url    = "http://download.proxmox.com/images/system/debian-13-standard_13.6-1_amd64.tar.zst"
    sha512 = "4c0c27ca6ceab5ef0b84db57825a00f26157ef1854bafe97297813e1cbe8ecb8cc9c453cab6b3b0efe1ba193a50c47ece1e41d950e411b8730b835b71e9e754b"
  }
}

# --- Rede: OPNsense e VLANs (rede.tf e opnsense.tf) ---

variable "interface_troncal" {
  description = "Tarxeta de cada nodo conectada á troncal (a segunda tarxeta da MV, a rede «só anfitrión» de VirtualBox)"
  type        = string
  default     = "enp0s8"
}

variable "vlans" {
  description = "VLANs da troncal: nome => etiqueta e rede /24 (OPNsense é a .1 de cada unha)"
  type = map(object({
    id   = number
    rede = string
  }))
  default = {
    servizos = { id = 10, rede = "10.10.10" } # Nextcloud, web, lldap e DNS
    xestion  = { id = 20, rede = "10.10.20" } # Zabbix
    iaas     = { id = 30, rede = "10.10.30" } # Servidores dos clientes, illados
  }
}

variable "saida_opnsense" {
  description = <<-EOT
    Rede interna de cada nodo pola que OPNsense sae a Internet (o nodo é a .1 e
    fai NAT, ver scripts/configurar-nat.sh). É igual nos dous nodos, así que
    OPNsense segue con Internet se a alta dispoñibilidade o move.
  EOT
  type        = string
  default     = "10.99.0.1/30"
}

variable "opnsense" {
  description = "Máquina virtual de OPNsense (cortalumes e enrutador das VLANs)"
  type = object({
    nodo  = string
    vm_id = number
    ram   = number
    disco = number
  })
  default = { nodo = "pve1", vm_id = 200, ram = 1536, disco = 10 }
}

variable "opnsense_iso" {
  description = "Imaxe de instalación de OPNsense (comprimida con bzip2) e a súa suma SHA-256"
  type = object({
    url    = string
    sha256 = string
  })
  default = {
    url    = "https://pkg.opnsense.org/releases/26.7/OPNsense-26.7-dvd-amd64.iso.bz2"
    sha256 = "95cafedda6d5b22ce832e249dc2309110fbee19f813ad78cf28bb3d387186bfb"
  }
}

variable "opnsense_instalado" {
  description = "Poñer a true despois de instalar OPNsense no disco: quítase o DVD de instalación"
  type        = bool
  default     = false
}
