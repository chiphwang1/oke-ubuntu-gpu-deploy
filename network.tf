locals {
  subnet_cidrs = { endpoint = cidrsubnet(var.vcn_cidr, 8, 0), lb = cidrsubnet(var.vcn_cidr, 8, 1), workers = cidrsubnet(var.vcn_cidr, 8, 2), pods = cidrsubnet(var.vcn_cidr, 6, 1)
  }
}
resource "oci_core_vcn" "this" {
  count          = local.create_network ? 1 : 0
  compartment_id = var.compartment_ocid
  cidr_blocks    = [var.vcn_cidr]
  display_name   = "${var.cluster_name}-vcn"
  dns_label      = "okegpu"
  freeform_tags  = var.freeform_tags
}
resource "oci_core_nat_gateway" "this" {
  count          = local.create_network ? 1 : 0
  compartment_id = var.compartment_ocid
  vcn_id         = local.vcn_id
  display_name   = "${var.cluster_name}-nat"
  freeform_tags  = var.freeform_tags
}
resource "oci_core_internet_gateway" "this" {
  count          = local.create_network && (var.public_api_endpoint || var.create_public_cpu_pool) ? 1 : 0
  compartment_id = var.compartment_ocid
  vcn_id         = local.vcn_id
  display_name   = "${var.cluster_name}-igw"
  freeform_tags  = var.freeform_tags
}
data "oci_core_services" "all" {
  count = local.create_network ? 1 : 0
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}
resource "oci_core_service_gateway" "this" {
  count          = local.create_network ? 1 : 0
  compartment_id = var.compartment_ocid
  vcn_id         = local.vcn_id
  display_name   = "${var.cluster_name}-services"
  services {
    service_id = data.oci_core_services.all[0].services[0].id
  }
  freeform_tags = var.freeform_tags
}
resource "oci_core_route_table" "private" {
  count          = local.create_network ? 1 : 0
  compartment_id = var.compartment_ocid
  vcn_id         = local.vcn_id
  display_name   = "${var.cluster_name}-private"
  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_nat_gateway.this[0].id

  }
  route_rules {
    destination       = data.oci_core_services.all[0].services[0].cidr_block
    destination_type  = "SERVICE_CIDR_BLOCK"
    network_entity_id = oci_core_service_gateway.this[0].id

  }
}
resource "oci_core_route_table" "public" {
  count          = local.create_network && (var.public_api_endpoint || var.create_public_cpu_pool) ? 1 : 0
  compartment_id = var.compartment_ocid
  vcn_id         = local.vcn_id
  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_internet_gateway.this[0].id

  }
}
resource "oci_core_security_list" "endpoint" {
  count          = local.create_network ? 1 : 0
  compartment_id = var.compartment_ocid
  vcn_id         = local.vcn_id
  display_name   = "${var.cluster_name}-api"
  dynamic "ingress_security_rules" {
    for_each = setproduct([local.subnet_cidrs.workers, local.subnet_cidrs.pods], [6443, 12250])
    content {
      protocol = "6"
      source   = ingress_security_rules.value[0]
      tcp_options {
        min = ingress_security_rules.value[1]
        max = ingress_security_rules.value[1]
      }

    }

  }
  ingress_security_rules {
    protocol = "1"
    source   = local.subnet_cidrs.workers
    icmp_options {
      type = 3
      code = 4
    }
  }
  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }
}
resource "oci_core_security_list" "workers" {
  count          = local.create_network ? 1 : 0
  compartment_id = var.compartment_ocid
  vcn_id         = local.vcn_id
  display_name   = "${var.cluster_name}-workers"
  # Node/pod traffic, API webhook/kubelet, private LB and optional CPU traffic.
  dynamic "ingress_security_rules" {
    for_each = merge(local.subnet_cidrs, var.create_public_cpu_pool ? { cpu = var.cpu_subnet_cidr } : {})
    content {
      protocol = "all"
      source   = ingress_security_rules.value
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
}
resource "oci_core_security_list" "lb" {
  count          = local.create_network ? 1 : 0
  compartment_id = var.compartment_ocid
  vcn_id         = local.vcn_id
  display_name   = "${var.cluster_name}-lb"
  ingress_security_rules {
    protocol = "6"
    source   = var.vcn_cidr
  }
  dynamic "egress_security_rules" {
    for_each = toset([local.subnet_cidrs.workers, local.subnet_cidrs.pods])
    content {
      protocol    = "all"
      destination = egress_security_rules.value
    }
  }
}
resource "oci_core_subnet" "this" {
  for_each                   = local.create_network ? local.subnet_cidrs : {}
  compartment_id             = var.compartment_ocid
  vcn_id                     = local.vcn_id
  display_name               = "${var.cluster_name}-${each.key}"
  dns_label                  = each.key
  cidr_block                 = each.value
  prohibit_public_ip_on_vnic = !(each.key == "endpoint" && var.public_api_endpoint)
  route_table_id             = each.key == "endpoint" && var.public_api_endpoint ? oci_core_route_table.public[0].id : oci_core_route_table.private[0].id
  security_list_ids          = [each.key == "endpoint" ? oci_core_security_list.endpoint[0].id : (contains(["workers", "pods"], each.key) ? oci_core_security_list.workers[0].id : oci_core_security_list.lb[0].id)]
  freeform_tags              = var.freeform_tags
}

# Allow SSH from any IPv4 subnet of the selected VCN, including reused VCNs.
data "oci_core_vcn" "existing" {
  count  = local.create_network ? 0 : 1
  vcn_id = local.vcn_id
}
locals {
  worker_ssh_source_cidrs = local.create_network ? toset([var.vcn_cidr]) : toset(data.oci_core_vcn.existing[0].cidr_blocks)
}
resource "oci_core_network_security_group" "worker_ssh" {
  compartment_id = var.compartment_ocid
  vcn_id         = local.vcn_id
  display_name   = "${var.cluster_name}-worker-ssh"
  freeform_tags  = var.freeform_tags
}
resource "oci_core_network_security_group_security_rule" "worker_ssh" {
  for_each                  = local.worker_ssh_source_cidrs
  network_security_group_id = oci_core_network_security_group.worker_ssh.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = each.value
  source_type               = "CIDR_BLOCK"
  stateless                 = false
  tcp_options {
    destination_port_range {
      min = 22
      max = 22
    }
  }
}

# Applies to new clusters in either a new or reused VCN. Existing clusters retain
# their endpoint configuration because this stack only adds their worker pool.
resource "oci_core_network_security_group" "api_access" {
  count          = local.create_cluster ? 1 : 0
  compartment_id = var.compartment_ocid
  vcn_id         = local.vcn_id
  display_name   = "${var.cluster_name}-api-access"
  freeform_tags  = var.freeform_tags
}
resource "oci_core_network_security_group_security_rule" "api_access" {
  count                     = local.create_cluster ? 1 : 0
  network_security_group_id = oci_core_network_security_group.api_access[0].id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
  stateless                 = false
  tcp_options {
    destination_port_range {
      min = 6443
      max = 6443
    }
  }
}
