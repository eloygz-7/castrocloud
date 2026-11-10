# Conexión coa API de Proxmox VE.
# Abonda con falar cun nodo: o clúster comparte a configuración e Terraform
# crea cada recurso no nodo que indique "node_name".
provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token

  # Os nodos usan o certificado autoasinado que xera Proxmox ao instalarse.
  # Só para o laboratorio: en produción, certificado válido e insecure = false.
  insecure = true
}
