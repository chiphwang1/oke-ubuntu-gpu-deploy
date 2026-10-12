locals {
  subnet_cidrs = { endpoint = cidrsubnet(var.vcn_cidr, 4, 0), workers = cidrsubnet(var.vcn_cidr, 4, 1), lb = cidrsubnet(var.vcn_cidr, 4, 2)
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
    for_each = setproduct([local.subnet_cidrs.workers], [6443, 12250])
    content {
      protocol = "6"
      source   = ingress_security_rules.value[0]
      tcp_options {
        min = ingress_security_rules.value[1]
        max = ingress_security_rules.value[1]
      }

    }

  }
  dynamic "ingress_security_rules" {
    for_each = toset(var.api_access_cidrs)
    content {
      protocol = "6"
      source   = ingress_security_rules.value
      tcp_options {
        min = 6443
        max = 6443
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
  # Intra-pool overlay and pod traffic; API webhook/kubelet and private LB traffic.
  dynamic "ingress_security_rules" {
    for_each = local.subnet_cidrs
    content {
      protocol = "all"
      source   = ingress_security_rules.value
    }

  }
  dynamic "ingress_security_rules" {
    for_each = toset(var.ssh_access_cidrs)
    content {
      protocol = "6"
      source   = ingress_security_rules.value
      tcp_options {
        min = 22
        max = 22
      }
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
  egress_security_rules {
    protocol    = "all"
    destination = local.subnet_cidrs.workers
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
  security_list_ids          = [each.key == "endpoint" ? oci_core_security_list.endpoint[0].id : (each.key == "workers" ? oci_core_security_list.workers[0].id : oci_core_security_list.lb[0].id)]
  freeform_tags              = var.freeform_tags
}
