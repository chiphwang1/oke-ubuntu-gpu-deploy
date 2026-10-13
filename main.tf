locals {
  selected_availability_domains = length(var.availability_domains) > 0 ? var.availability_domains : (var.availability_domain != "" ? [var.availability_domain] : [])
  regional_availability_domains = { for ad in data.oci_identity_availability_domains.workers.availability_domains : try(regex("AD-[0-9]+$", ad.name), ad.name) => ad.name }
  worker_availability_domains   = [for ad in local.selected_availability_domains : lookup(local.regional_availability_domains, ad, ad)]
  primary_worker_ad             = try(local.worker_availability_domains[0], "")
  create_cluster                = var.deployment_mode != "existing_cluster"
  create_network                = var.deployment_mode == "new_infrastructure"
  cluster_id                    = local.create_cluster ? oci_containerengine_cluster.this[0].id : var.existing_cluster_id
  vcn_id                        = local.create_network ? oci_core_vcn.this[0].id : (local.create_cluster ? var.existing_vcn_id : data.oci_containerengine_cluster.existing[0].vcn_id)
  worker_subnet_id              = local.create_network ? oci_core_subnet.this["workers"].id : var.existing_worker_subnet_id
  endpoint_subnet_id            = local.create_network ? oci_core_subnet.this["endpoint"].id : var.existing_endpoint_subnet_id
  lb_subnet_id                  = local.create_network ? oci_core_subnet.this["lb"].id : var.existing_lb_subnet_id
  pod_subnet_id                 = local.create_network ? oci_core_subnet.this["pods"].id : (var.existing_pod_subnet_id != "" ? var.existing_pod_subnet_id : var.existing_worker_subnet_id)
  ubuntu_codename               = { "22.04" = "jammy", "24.04" = "noble" }[var.ubuntu_version]
  kubernetes_minor              = join(".", slice(split(".", trimprefix(var.kubernetes_version, "v")), 0, 2))
  node_packages = { "1.32" = "1.32.10", "1.33" = "1.33.10", "1.34" = "1.34.10", "1.35" = "1.35.2", "1.36" = "1.36.4"
  }
  node_package = "oci-oke-node-all-${lookup(local.node_packages, local.kubernetes_minor, "unsupported")}"
  image_id     = var.image_mode == "create" ? oci_core_image.ubuntu[0].id : var.ubuntu_image_id
  cli_auth     = { ResourcePrincipal = "resource_principal", SecurityToken = "security_token", APIKey = "api_key", InstancePrincipal = "instance_principal" }[var.auth]
  ubuntu_cloud_config = {
    apt = { sources = { "oke-node" = { source = "deb [trusted=yes] https://objectstorage.us-sanjose-1.oraclecloud.com/n/odx-oke/b/okn-repositories/o/prod/ubuntu-${local.ubuntu_codename}/kubernetes-${local.kubernetes_minor} stable main" }
      }
    }
    packages = [local.node_package]
    runcmd   = [["bash", "-ec", ". /etc/os-release; test \"$VERSION_ID\" = '${var.ubuntu_version}'; oke bootstrap"]]
  }
  cloud_init = "#cloud-config\n${yamlencode(local.ubuntu_cloud_config)}"
  gpu_cloud_init = "#cloud-config\n${yamlencode(merge(local.ubuntu_cloud_config, {
    runcmd = concat([["bash", "-ec", file("${path.module}/scripts/configure_nvidia_repository.sh")]], local.ubuntu_cloud_config.runcmd)
  }))}"
}
data "oci_identity_availability_domains" "workers" {
  compartment_id = var.compartment_ocid
}
data "oci_containerengine_cluster" "existing" {
  count      = local.create_cluster ? 0 : 1
  cluster_id = var.existing_cluster_id
}
data "oci_containerengine_cluster_option" "available" {
  cluster_option_id = "all"
  compartment_id    = var.compartment_ocid
}
data "oci_core_subnet" "workers" {
  count     = local.create_network ? 0 : 1
  subnet_id = var.existing_worker_subnet_id
}
data "oci_core_subnet" "pods" {
  count     = !local.create_network && var.existing_pod_subnet_id != "" ? 1 : 0
  subnet_id = var.existing_pod_subnet_id
}
data "oci_core_subnet" "endpoint" {
  count     = !local.create_network && local.create_cluster ? 1 : 0
  subnet_id = var.existing_endpoint_subnet_id
}
data "oci_core_subnet" "lb" {
  count     = !local.create_network && local.create_cluster ? 1 : 0
  subnet_id = var.existing_lb_subnet_id
}
data "external" "network_validation" {
  program = ["python3", "${path.module}/scripts/validate_network.py"]
  query = { enabled = tostring(local.create_network), vcn = var.vcn_cidr, pods = var.pods_cidr, services = var.services_cidr
  }
}
resource "terraform_data" "validate" {
  lifecycle {
    precondition {
      condition     = alltrue([for ad in local.selected_availability_domains : !can(regex("^AD-[0-9]+$", ad)) || contains(keys(local.regional_availability_domains), ad)])
      error_message = "An availability domain is unavailable in this region. Choose AD-1 in single-AD regions; AD-2 and AD-3 require a three-AD region."
    }
    precondition {
      condition     = contains(data.oci_containerengine_cluster_option.available.kubernetes_versions, var.kubernetes_version) && contains(keys(local.node_packages), local.kubernetes_minor)
      error_message = "Choose a regional OKE Kubernetes version with an Oracle Ubuntu node package (1.32 through 1.36)."

    }
    precondition {
      condition     = local.create_cluster ? true : (try(data.oci_containerengine_cluster.existing[0].type, "") == "ENHANCED_CLUSTER" && try(data.oci_containerengine_cluster.existing[0].kubernetes_version, "") == var.kubernetes_version && try(data.oci_containerengine_cluster.existing[0].cluster_pod_network_options[0].cni_type, "") == var.cni_type)
      error_message = "Existing cluster must be Enhanced, match cni_type and kubernetes_version."

    }
    precondition {
      condition     = local.create_network ? true : (data.oci_core_subnet.workers[0].vcn_id == local.vcn_id && data.oci_core_subnet.workers[0].prohibit_public_ip_on_vnic)
      error_message = "Existing worker subnet must be private and belong to the cluster VCN."

    }
    precondition {
      condition     = !local.create_network && local.create_cluster ? (data.oci_core_subnet.endpoint[0].vcn_id == local.vcn_id && data.oci_core_subnet.lb[0].vcn_id == local.vcn_id && (!var.public_api_endpoint || !data.oci_core_subnet.endpoint[0].prohibit_public_ip_on_vnic)) : true
      error_message = "Existing endpoint and LB subnets must belong to the selected VCN; a public API needs a public endpoint subnet."

    }
    precondition {
      condition     = length(local.worker_availability_domains) > 0
      error_message = "Select at least one availability domain."

    }
    precondition {
      condition     = local.create_network ? true : (try(coalesce(data.oci_core_subnet.workers[0].availability_domain, "regional"), "regional") == "regional" || alltrue([for ad in local.worker_availability_domains : ad == data.oci_core_subnet.workers[0].availability_domain]))
      error_message = "Use a regional worker subnet for multiple ADs, or select the subnet's AD."
    }
    precondition {
      condition     = length(data.oci_core_subnet.pods) == 0 ? true : (data.oci_core_subnet.pods[0].vcn_id == local.vcn_id && data.oci_core_subnet.pods[0].prohibit_public_ip_on_vnic && (try(coalesce(data.oci_core_subnet.pods[0].availability_domain, "regional"), "regional") == "regional" || alltrue([for ad in local.worker_availability_domains : ad == data.oci_core_subnet.pods[0].availability_domain])))
      error_message = "Select a private pod subnet in the cluster VCN that supports every selected AD."
    }
    precondition {
      condition     = data.external.network_validation.result.valid == "true"
      error_message = "VCN, legacy overlay and service CIDRs must not overlap; new VCN prefix must be /16."

    }

  }
}
resource "oci_containerengine_cluster" "this" {
  count              = local.create_cluster ? 1 : 0
  compartment_id     = var.compartment_ocid
  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version
  type               = "ENHANCED_CLUSTER"
  vcn_id             = local.vcn_id
  freeform_tags      = var.freeform_tags
  cluster_pod_network_options {
    cni_type = var.cni_type
  }
  endpoint_config {
    nsg_ids              = concat([oci_core_network_security_group.api_access[0].id], var.create_public_cpu_pool ? [oci_core_network_security_group.cpu_endpoint[0].id] : [])
    subnet_id            = local.endpoint_subnet_id
    is_public_ip_enabled = var.public_api_endpoint

  }
  options {
    service_lb_subnet_ids = [local.lb_subnet_id]
    kubernetes_network_config {
      pods_cidr     = var.cni_type == "FLANNEL_OVERLAY" ? var.pods_cidr : null
      services_cidr = var.services_cidr

    }
    add_ons {
      is_kubernetes_dashboard_enabled = false
      is_tiller_enabled               = false

    }

  }
  depends_on = [terraform_data.validate, terraform_data.reused_subnet_access]
}
resource "oci_containerengine_node_pool" "ubuntu" {
  compartment_id     = var.compartment_ocid
  cluster_id         = local.cluster_id
  name               = var.node_pool_name != "" ? var.node_pool_name : "${substr(var.cluster_name, 0, 21)}-ubuntu-gpu"
  kubernetes_version = var.kubernetes_version
  node_shape         = var.node_shape
  ssh_public_key     = local.worker_ssh_public_key == "" ? null : local.worker_ssh_public_key
  freeform_tags      = var.freeform_tags
  node_metadata = {
    user_data                      = base64encode(local.gpu_cloud_init)
    areLegacyImdsEndpointsDisabled = "true"
  }
  node_config_details {
    nsg_ids = [oci_core_network_security_group.worker_ssh.id]
    size    = var.node_count
    dynamic "placement_configs" {
      for_each = toset(local.worker_availability_domains)
      content {
        availability_domain = placement_configs.value
        subnet_id           = local.worker_subnet_id
        fault_domains       = length(var.fault_domains) == 0 ? null : var.fault_domains
      }
    }
    node_pool_pod_network_option_details {
      cni_type          = var.cni_type
      pod_subnet_ids    = var.cni_type == "OCI_VCN_IP_NATIVE" ? [local.pod_subnet_id] : null
      max_pods_per_node = var.cni_type == "OCI_VCN_IP_NATIVE" ? var.max_pods_per_node : null
    }

  }
  node_source_details {
    source_type             = "IMAGE"
    image_id                = local.image_id
    boot_volume_size_in_gbs = var.boot_volume_size_gbs

  }
  dynamic "node_shape_config" {
    for_each = endswith(var.node_shape, ".Flex") ? [1] : []
    content {
      ocpus         = var.node_ocpus
      memory_in_gbs = var.node_memory_gbs

    }

  }
  dynamic "initial_node_labels" {
    for_each = merge(var.node_labels, { "certification.oci/ubuntu-version" = var.ubuntu_version })
    content {
      key   = initial_node_labels.key
      value = initial_node_labels.value
    }

  }
  depends_on = [terraform_data.validate, terraform_data.validate_image, terraform_data.disable_gpu_before_nodes, terraform_data.reused_subnet_access]
}
# No GPU add-on is installed by this stack. These guards remove managed add-ons
# that OKE may already have installed. Never use a fake "enabled=false" argument.
resource "terraform_data" "disable_gpu_before_nodes" {
  triggers_replace = [local.cluster_id, filesha256("${path.module}/scripts/gpu_addons.py")]
  provisioner "local-exec" {
    command = "python3 \"${path.module}/scripts/gpu_addons.py\" disable"
    environment = { OKE_CLUSTER_ID = local.cluster_id, OCI_CLI_REGION = var.region, OCI_CLI_AUTH = local.cli_auth, OCI_CLI_PROFILE = var.config_file_profile
    }

  }
}
resource "terraform_data" "verify_gpu_disabled" {
  # Intentionally runs at every apply to catch drift/reinstallation.
  triggers_replace = [timestamp()]
  provisioner "local-exec" {
    command = "python3 \"${path.module}/scripts/gpu_addons.py\" disable"
    environment = { OKE_CLUSTER_ID = local.cluster_id, OCI_CLI_REGION = var.region, OCI_CLI_AUTH = local.cli_auth, OCI_CLI_PROFILE = var.config_file_profile
    }

  }
  depends_on = [oci_containerengine_node_pool.ubuntu, oci_containerengine_node_pool.public_cpu]
}
