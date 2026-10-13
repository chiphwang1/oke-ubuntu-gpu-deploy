# Optional diagnostic pool: a public primary VNIC, with native pods retained in
# the dedicated private pod subnet. The original GPU pool is not replaced.
resource "terraform_data" "validate_public_cpu" {
  lifecycle {
    precondition {
      condition     = !var.create_public_cpu_pool || contains([for s in data.oci_core_image_shapes.selected.image_shape_compatibilities : s.shape], var.cpu_node_shape)
      error_message = "The Ubuntu image must support the selected CPU worker shape."
    }
    precondition {
      condition     = !var.create_public_cpu_pool || (local.create_cluster && var.cni_type == "OCI_VCN_IP_NATIVE")
      error_message = "Public CPU diagnostics requires a cluster managed by this stack and VCN-native CNI."
    }
    precondition {
      condition     = !var.create_public_cpu_pool || local.worker_ssh_public_key != ""
      error_message = "Generate a shared SSH key pair or upload/paste a public key for both node pools."
    }
    precondition {
      condition     = !var.create_public_cpu_pool || local.create_network || var.cpu_internet_gateway_id != ""
      error_message = "For an existing VCN, provide its internet gateway OCID for the public CPU subnet."
    }
  }
}
resource "oci_core_route_table" "public_cpu" {
  count          = var.create_public_cpu_pool ? 1 : 0
  compartment_id = var.compartment_ocid
  vcn_id         = local.vcn_id
  display_name   = "${var.cluster_name}-cpu-public"
  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = local.create_network ? oci_core_internet_gateway.this[0].id : var.cpu_internet_gateway_id
  }
  depends_on = [terraform_data.validate_public_cpu]
}
resource "oci_core_security_list" "public_cpu" {
  count          = var.create_public_cpu_pool ? 1 : 0
  compartment_id = var.compartment_ocid
  vcn_id         = local.vcn_id
  display_name   = "${var.cluster_name}-cpu-public"
  dynamic "ingress_security_rules" {
    for_each = toset([var.cpu_subnet_cidr, local.create_network ? local.subnet_cidrs.workers : data.oci_core_subnet.workers[0].cidr_block, local.create_network ? local.subnet_cidrs.endpoint : data.oci_core_subnet.endpoint[0].cidr_block, local.create_network ? local.subnet_cidrs.pods : (var.existing_pod_subnet_id != "" ? data.oci_core_subnet.pods[0].cidr_block : data.oci_core_subnet.workers[0].cidr_block)])
    content {
      protocol = "all"
      source   = ingress_security_rules.value
    }
  }
  ingress_security_rules {
    protocol    = "6"
    source      = "0.0.0.0/0"
    source_type = "CIDR_BLOCK"
    stateless   = false
    tcp_options {
      min = 22
      max = 22
    }
  }
  ingress_security_rules {
    protocol = "1"
    source   = "0.0.0.0/0"
    icmp_options {
      type = 3
      code = 4
    }
  }
  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }
  depends_on = [terraform_data.validate_public_cpu]
}
resource "oci_core_subnet" "public_cpu" {
  count                      = var.create_public_cpu_pool ? 1 : 0
  compartment_id             = var.compartment_ocid
  vcn_id                     = local.vcn_id
  display_name               = "${var.cluster_name}-cpu-public"
  dns_label                  = "cpudebug"
  cidr_block                 = var.cpu_subnet_cidr
  prohibit_public_ip_on_vnic = false
  route_table_id             = oci_core_route_table.public_cpu[0].id
  security_list_ids          = [oci_core_security_list.public_cpu[0].id, oci_core_security_list.private_access.id]
  freeform_tags              = local.freeform_tags
}
resource "oci_core_network_security_group" "cpu_endpoint" {
  count          = var.create_public_cpu_pool ? 1 : 0
  compartment_id = var.compartment_ocid
  vcn_id         = local.vcn_id
  display_name   = "${var.cluster_name}-cpu-to-api"
}
resource "oci_core_network_security_group_security_rule" "cpu_endpoint" {
  for_each                  = var.create_public_cpu_pool ? toset(["6443", "12250"]) : toset([])
  network_security_group_id = oci_core_network_security_group.cpu_endpoint[0].id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = var.cpu_subnet_cidr
  source_type               = "CIDR_BLOCK"
  tcp_options {
    destination_port_range {
      min = tonumber(each.value)
      max = tonumber(each.value)
    }
  }
}
resource "oci_containerengine_node_pool" "public_cpu" {
  count              = var.create_public_cpu_pool ? 1 : 0
  compartment_id     = var.compartment_ocid
  cluster_id         = local.cluster_id
  name               = "${substr(var.cluster_name, 0, 21)}-public-cpu"
  kubernetes_version = var.kubernetes_version
  node_shape         = var.cpu_node_shape
  ssh_public_key     = local.worker_ssh_public_key
  freeform_tags      = local.freeform_tags
  node_metadata = {
    user_data                      = base64encode(local.cloud_init)
    areLegacyImdsEndpointsDisabled = "true"
  }
  node_shape_config {
    ocpus         = var.cpu_node_ocpus
    memory_in_gbs = var.cpu_node_memory_gbs
  }
  node_config_details {
    nsg_ids = [oci_core_network_security_group.worker_ssh.id]
    size    = var.cpu_node_count
    placement_configs {
      availability_domain = var.cpu_availability_domain != "" ? var.cpu_availability_domain : local.primary_worker_ad
      subnet_id           = oci_core_subnet.public_cpu[0].id
    }
    node_pool_pod_network_option_details {
      cni_type          = "OCI_VCN_IP_NATIVE"
      pod_subnet_ids    = [local.pod_subnet_id]
      max_pods_per_node = var.max_pods_per_node
    }
  }
  node_source_details {
    source_type             = "IMAGE"
    image_id                = local.image_id
    boot_volume_size_in_gbs = var.boot_volume_size_gbs
  }
  initial_node_labels {
    key   = "certification.oci/pool-purpose"
    value = "cpu-diagnostics"
  }
  depends_on = [terraform_data.validate_public_cpu, terraform_data.disable_gpu_before_nodes, oci_core_network_security_group_security_rule.cpu_endpoint, terraform_data.reused_subnet_access]
}
output "public_cpu_node_pool_id" { value = try(oci_containerengine_node_pool.public_cpu[0].id, null) }
output "public_cpu_subnet_id" { value = try(oci_core_subnet.public_cpu[0].id, null) }
