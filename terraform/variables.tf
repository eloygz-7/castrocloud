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
  description = "Servidores dos servizos: nome => nodo preferido, ID, IP, RAM (MB), disco (GB) e núcleos"
  type = map(object({
    nodo    = string
    vm_id   = number
    ip      = string
    ram     = number
    disco   = number
    nucleos = number
  }))
  default = {
    ct-nextcloud = { nodo = "pve1", vm_id = 211, ip = "192.168.0.231", ram = 1536, disco = 10, nucleos = 2 } # Nextcloud e o seu MySQL
    ct-web       = { nodo = "pve3", vm_id = 212, ip = "192.168.0.232", ram = 512, disco = 4, nucleos = 1 }   # WordPress con Nginx e MySQL
    ct-servizos  = { nodo = "pve3", vm_id = 213, ip = "192.168.0.233", ram = 512, disco = 2, nucleos = 1 }   # lldap e Bind9
    ct-zabbix    = { nodo = "pve3", vm_id = 214, ip = "192.168.0.234", ram = 1024, disco = 4, nucleos = 1 }  # Zabbix e o seu MySQL
  }
}

variable "ssh_clave_publica" {
  description = "Clave pública SSH coa que Ansible entra como root nos servidores (crear con: ssh-keygen -t ed25519)"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "ip_nodos" {
  description = <<-EOT
    IP de cada nodo. Cada servidor usa o seu nodo preferido como pasarela (NAT,
    ver scripts/configurar-nat.sh): pola wifi os contedores non chegan ao router.
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
