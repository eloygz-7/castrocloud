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
  description = "Un contedor de demostración por nodo: nome do nodo => ID e IP"
  type = map(object({
    vm_id = number
    ip    = string
  }))
  default = {
    pve1 = { vm_id = 201, ip = "192.168.0.221" }
    pve2 = { vm_id = 202, ip = "192.168.0.222" }
    pve3 = { vm_id = 203, ip = "192.168.0.223" }
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

variable "almacen_discos" {
  description = "Almacenamento de Proxmox para os discos dos contedores"
  type        = string
  default     = "local-lvm"
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
