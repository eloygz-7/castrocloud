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
  description = "Plantilla oficial de Proxmox para os contedores LXC (Debian 13)"
  type = object({
    url    = string
    sha512 = string
  })
  default = {
    url    = "http://download.proxmox.com/images/system/debian-13-standard_13.6-1_amd64.tar.zst"
    sha512 = "4c0c27ca6ceab5ef0b84db57825a00f26157ef1854bafe97297813e1cbe8ecb8cc9c453cab6b3b0efe1ba193a50c47ece1e41d950e411b8730b835b71e9e754b"
  }
}
