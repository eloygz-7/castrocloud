# Demostración: un contedor LXC en cada nodo do clúster.
# Os contedores LXC non necesitan virtualización aniñada, así que funcionan
# tamén no nodo de Windows.

# 1. Descargar a plantilla de Debian 13 en cada nodo (o almacenamento "local" é propio de cada nodo)
resource "proxmox_download_file" "plantilla_debian" {
  for_each = var.contedores

  node_name          = each.key
  datastore_id       = "local"
  content_type       = "vztmpl"
  url                = var.plantilla_lxc.url
  checksum           = var.plantilla_lxc.sha512
  checksum_algorithm = "sha512"
  # O nodo de Windows (pve2) baixa máis lento pola wifi: os 10 min por defecto non chegan
  upload_timeout = 3600
}

# 2. Contrasinal aleatorio para o usuario root dos contedores
resource "random_password" "root" {
  length  = 20
  special = false
}

# 3. Os contedores
resource "proxmox_virtual_environment_container" "demo" {
  for_each = var.contedores

  node_name   = each.key
  vm_id       = each.value.vm_id
  description = "CastroCloud: contedor de demostración creado con Terraform"
  tags        = ["castrocloud", "terraform"]

  unprivileged  = true
  start_on_boot = true
  features {
    nesting = true
  }

  cpu {
    cores = 1
  }

  memory {
    dedicated = 512
  }

  disk {
    datastore_id = var.almacen_discos
    size         = 4
  }

  network_interface {
    name   = "eth0"
    bridge = "vmbr0"
  }

  operating_system {
    template_file_id = proxmox_download_file.plantilla_debian[each.key].id
    type             = "debian"
  }

  initialization {
    hostname = "ct-demo-${each.key}"

    ip_config {
      ipv4 {
        address = "${each.value.ip}/24"
        gateway = var.pasarela
      }
    }

    dns {
      servers = var.dns
    }

    user_account {
      password = random_password.root.result
    }
  }
}
