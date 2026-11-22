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

variable "contedores" {
  description = "Contedores de demostración: nome => nodo, ID e IP (3 en pve1, 2 en pve2 e 3 en pve3)"
  type = map(object({
    nodo  = string
    vm_id = number
    ip    = string
  }))
  default = {
    ct-pve1-1 = { nodo = "pve1", vm_id = 201, ip = "192.168.0.221" }
    ct-pve1-2 = { nodo = "pve1", vm_id = 202, ip = "192.168.0.222" }
    ct-pve1-3 = { nodo = "pve1", vm_id = 203, ip = "192.168.0.223" }
    ct-pve2-1 = { nodo = "pve2", vm_id = 204, ip = "192.168.0.224" }
    ct-pve2-2 = { nodo = "pve2", vm_id = 205, ip = "192.168.0.225" }
    ct-pve3-1 = { nodo = "pve3", vm_id = 206, ip = "192.168.0.226" }
    ct-pve3-2 = { nodo = "pve3", vm_id = 207, ip = "192.168.0.227" }
    ct-pve3-3 = { nodo = "pve3", vm_id = 208, ip = "192.168.0.228" }
  }
}

variable "pasarela" {
  description = "Pasarela da wifi (o router)"
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
  description = "Cada canto se replican os contedores aos outros nodos (formato de calendario de systemd)"
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
  description = "Plantilla oficial de Proxmox para os contedores LXC (Alpine Linux 3.24, lixeira para o nodo de Windows)"
  type = object({
    url    = string
    sha512 = string
  })
  default = {
    url    = "http://download.proxmox.com/images/system/alpine-3.24-default_20261105_amd64.tar.xz"
    sha512 = "5f2ab800b1cf9b9eed768b0cd4b4c395d5bc00a7eda7a185c89111067a25e7ce28d86ffb6d1b3f3181d43d9935e708c713f6b3937f39a5f2839cb56214889c8b"
  }
}
