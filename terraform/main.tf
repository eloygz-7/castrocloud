# Demostración: 8 contedores LXC lixeiros repartidos polo clúster
# (3 en pve1, 2 en pve2, que é o PC con Windows e ten menos recursos, e 3 en pve3).
# Os contedores LXC non necesitan virtualización aniñada, así que funcionan
# tamén no nodo de Windows.

# 1. Descargar a plantilla de Alpine Linux en cada nodo (3,5 MB fronte aos 130 MB de Debian:
#    o PC con Windows (pve2) ten poucos recursos e baixa lento pola wifi).
#    Descárgase unha vez por nodo, porque o almacenamento "local" é propio de cada nodo.
resource "proxmox_download_file" "plantilla_lxc" {
  for_each = toset([for ct in var.contedores : ct.nodo])

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

  node_name   = each.value.nodo
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
    dedicated = 128
    swap      = 0
  }

  disk {
    datastore_id = var.almacen_discos
    size         = 1
  }

  network_interface {
    name   = "eth0"
    bridge = "vmbr0"
  }

  operating_system {
    template_file_id = proxmox_download_file.plantilla_lxc[each.value.nodo].id
    type             = "alpine"
  }

  initialization {
    hostname = each.key

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
