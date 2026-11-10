output "contedores" {
  description = "Contedores creados: nodo => IP"
  value       = { for nodo, ct in var.contedores : "ct-demo-${nodo}" => ct.ip }
}

output "contrasinal_root" {
  description = "Contrasinal de root dos contedores (ver con: terraform output -raw contrasinal_root)"
  value       = random_password.root.result
  sensitive   = true
}
