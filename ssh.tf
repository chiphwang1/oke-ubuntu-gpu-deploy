resource "tls_private_key" "workers" {
  count     = var.ssh_key_source == "generate" ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}
locals {
  worker_ssh_public_key = var.ssh_key_source == "generate" ? tls_private_key.workers[0].public_key_openssh : trimspace(var.ssh_public_key)
  cpu_ssh_public_key    = local.worker_ssh_public_key
}
output "generated_worker_ssh_private_key" {
  value       = var.ssh_key_source == "generate" ? tls_private_key.workers[0].private_key_pem : ""
  sensitive   = true
  description = "Generated worker private key. Save to a file and chmod 600; also stored in Terraform state."
}
output "generated_cpu_ssh_private_key" {
  value       = var.create_public_cpu_pool && var.ssh_key_source == "generate" ? tls_private_key.workers[0].private_key_pem : ""
  sensitive   = true
  description = "Alias of the shared worker private key. Save to a file and chmod 600; also stored in Terraform state."
}
output "worker_ssh_public_key" { value = local.worker_ssh_public_key }
output "cpu_ssh_public_key" { value = var.create_public_cpu_pool ? local.cpu_ssh_public_key : "" }
