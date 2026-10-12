output "cluster_id" { value = local.cluster_id }
output "node_pool_id" { value = oci_containerengine_node_pool.ubuntu.id }
output "vcn_id" { value = local.vcn_id }
output "worker_subnet_id" { value = local.worker_subnet_id }
output "ubuntu_image_id" { value = local.image_id }
output "image_source_instance_id" { value = try(oci_core_instance.image_source[0].id, null) }
output "kubeconfig_command" {
  value = "oci ce cluster create-kubeconfig --cluster-id ${local.cluster_id} --region ${var.region} --token-version 2.0.0 --kube-endpoint ${local.create_cluster && var.public_api_endpoint ? "PUBLIC_ENDPOINT" : "PRIVATE_ENDPOINT"} --file ./kubeconfig"
}
output "gpu_addon_policy" {
  value      = "OKE GPU Plugin, GPU Operator, GPU health/metrics and Node Feature Discovery add-ons removed and verified at apply time. NVIDIA installs its certification operator separately."
  depends_on = [terraform_data.verify_gpu_disabled]
}
