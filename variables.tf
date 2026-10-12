variable "tenancy_ocid" {
  type        = string
  description = "Tenancy OCID."
}

variable "compartment_ocid" {
  type        = string
  description = "Compartment for new resources."
}

variable "region" {
  type        = string
  description = "OCI deployment region."
  default     = "us-ashburn-1"
}

variable "auth" {
  type        = string
  description = "InstancePrincipal for ORM; SecurityToken or APIKey for local CLI. ResourcePrincipal is supported where supplied."
  default     = "InstancePrincipal"
  validation {
    condition     = contains(["ResourcePrincipal", "SecurityToken", "APIKey", "InstancePrincipal"], var.auth)
    error_message = "Choose one of: ResourcePrincipal, SecurityToken, APIKey, InstancePrincipal."
  }
}

variable "config_file_profile" {
  type        = string
  description = "OCI CLI/profile name for local execution."
  default     = "DEFAULT"
}

variable "deployment_mode" {
  type        = string
  description = "Create everything, use an existing VCN, or join an existing OKE cluster."
  default     = "new_infrastructure"
  validation {
    condition     = contains(["new_infrastructure", "existing_vcn", "existing_cluster"], var.deployment_mode)
    error_message = "Choose one of: new_infrastructure, existing_vcn, existing_cluster."
  }
}

variable "cluster_name" {
  type        = string
  description = "Name prefix for new resources."
  default     = "oke-ubuntu-gpu"
}

variable "existing_cluster_id" {
  type        = string
  description = "Existing Enhanced OKE cluster OCID (existing_cluster mode)."
  default     = ""
}

variable "existing_vcn_id" {
  type        = string
  description = "Existing VCN OCID (existing_vcn mode)."
  default     = ""
}

variable "existing_worker_subnet_id" {
  type        = string
  description = "Existing private regional worker subnet in the selected VCN."
  default     = ""
}

variable "existing_endpoint_subnet_id" {
  type        = string
  description = "Endpoint subnet for a new cluster in an existing VCN."
  default     = ""
}

variable "existing_lb_subnet_id" {
  type        = string
  description = "Load-balancer subnet for a new cluster in an existing VCN."
  default     = ""
}

variable "kubernetes_version" {
  type        = string
  description = "Exact regional OKE version; for reuse, must equal existing cluster version."
  default     = "v1.36.4"
}

variable "public_api_endpoint" {
  type        = bool
  description = "Give a NEW cluster a public API IP. TCP 6443 permits all IPv4 sources; Kubernetes authentication is required."
  default     = true
}


variable "vcn_cidr" {
  type        = string
  description = "New /16 VCN; /24 API, LB and worker subnets and a /22 native pod subnet are derived."
  default     = "10.16.0.0/16"
  validation {
    condition     = can(cidrnetmask(var.vcn_cidr)) && try(tonumber(split("/", var.vcn_cidr)[1]) == 16, false)
    error_message = "Specify a valid IPv4 /16 VCN CIDR."
  }
}

variable "pods_cidr" {
  type        = string
  description = "Flannel overlay pod CIDR for new clusters."
  default     = "10.244.0.0/16"
  validation {
    condition     = can(cidrnetmask(var.pods_cidr))
    error_message = "Specify a valid IPv4 CIDR."
  }
}

variable "services_cidr" {
  type        = string
  description = "Kubernetes service CIDR for new clusters."
  default     = "10.96.0.0/16"
  validation {
    condition     = can(cidrnetmask(var.services_cidr))
    error_message = "Specify a valid IPv4 CIDR."
  }
}

variable "ubuntu_version" {
  type        = string
  description = "Ubuntu release; selects the matching Oracle Ubuntu bootstrap repository."
  default     = "24.04"
  validation {
    condition     = contains(["22.04", "24.04"], var.ubuntu_version)
    error_message = "Choose one of: 22.04, 24.04."
  }
}

variable "image_mode" {
  type        = string
  description = "Build a clean custom image, or use an existing clean custom Ubuntu image."
  default     = "create"
  validation {
    condition     = contains(["create", "existing"], var.image_mode)
    error_message = "Choose one of: create, existing."
  }
}

variable "ubuntu_image_id" {
  type        = string
  description = "Custom Ubuntu image OCID when image_mode is existing."
  default     = ""
}

variable "source_ubuntu_image_id" {
  type        = string
  description = "Optional standard x86 Ubuntu source image; empty discovers newest matching image."
  default     = ""
}

variable "node_shape" {
  type        = string
  description = "NVIDIA GPU shape available in the chosen AD; no RDMA/HPC configuration is deployed."
  validation {
    condition     = can(regex("^(VM|BM)\\.GPU", var.node_shape)) && !strcontains(var.node_shape, "MI300") && !strcontains(var.node_shape, "MI355")
    error_message = "Select an NVIDIA VM.GPU or BM.GPU shape; AMD and HPC shapes are excluded."
  }
}

variable "node_count" {
  type        = number
  description = "Fixed worker-node count."
  default     = 1
  validation {
    condition     = var.node_count >= 1 && floor(var.node_count) == var.node_count
    error_message = "Must be an integer of at least 1."
  }
}

variable "availability_domain" {
  type        = string
  description = "Legacy single worker AD; use availability_domains for multiple placements."
  default     = ""
}

variable "availability_domains" {
  type        = list(string)
  default     = []
  description = "Worker ADs in selection order; the first is the automatic image-builder and CPU-pool AD."
  validation {
    condition     = alltrue([for ad in var.availability_domains : trimspace(ad) != ""]) && length(distinct(var.availability_domains)) == length(var.availability_domains)
    error_message = "Availability domains must be non-empty and unique."
  }
}

variable "network_compartment_ocid" {
  type        = string
  default     = ""
  description = "ORM discovery compartment for existing VCN and subnets; resource OCIDs remain authoritative."
}

variable "fault_domains" {
  type        = list(string)
  description = "Fault domains applied to every selected worker AD; empty lets OKE choose."
  default     = []
  validation {
    condition     = alltrue([for fd in var.fault_domains : contains(["FAULT-DOMAIN-1", "FAULT-DOMAIN-2", "FAULT-DOMAIN-3"], fd)]) && length(distinct(var.fault_domains)) == length(var.fault_domains)
    error_message = "Select distinct FAULT-DOMAIN-1, FAULT-DOMAIN-2 or FAULT-DOMAIN-3 values."
  }
}

variable "boot_volume_size_gbs" {
  type        = number
  description = "Worker boot volume size in GB, at least 50 and at least image minimum."
  default     = 100
  validation {
    condition     = var.boot_volume_size_gbs >= 50 && floor(var.boot_volume_size_gbs) == var.boot_volume_size_gbs
    error_message = "Must be an integer of at least 50."
  }
}

variable "ssh_public_key" {
  type        = string
  description = "Optional SSH public key; never supply a private key."
  default     = ""
}

variable "node_labels" {
  type        = map(string)
  description = "Additional Kubernetes labels applied to the Ubuntu workers."
  default     = {}
}

variable "node_ocpus" {
  type        = number
  description = "OCPU count only for a selectable flexible GPU shape; null otherwise."
  default     = null
}

variable "node_memory_gbs" {
  type        = number
  description = "Memory GB only for a selectable flexible GPU shape; null otherwise."
  default     = null
}

variable "builder_shape" {
  type        = string
  description = "Non-GPU x86 Flex shape for the temporary image-source instance."
  default     = "VM.Standard.E4.Flex"
}

variable "builder_ocpus" {
  type        = number
  description = "Image-builder OCPUs."
  default     = 1
}

variable "builder_memory_gbs" {
  type        = number
  description = "Image-builder memory in GB."
  default     = 8
}

variable "freeform_tags" {
  type        = map(string)
  description = "OCI freeform tags on resources created by this stack."
  default     = { "purpose" : "nvidia-gpu-operator-certification" }
}

variable "cni_type" {
  type        = string
  default     = "OCI_VCN_IP_NATIVE"
  description = "Flannel overlay or OCI VCN-native networking; must match a reused cluster."
  validation {
    condition     = contains(["FLANNEL_OVERLAY", "OCI_VCN_IP_NATIVE"], var.cni_type)
    error_message = "Select FLANNEL_OVERLAY or OCI_VCN_IP_NATIVE."
  }
}
variable "max_pods_per_node" {
  type        = number
  default     = 31
  description = "Maximum pods per worker for OCI VCN-native networking; fit subnet and shape limits."
  validation {
    condition     = var.max_pods_per_node >= 1 && var.max_pods_per_node <= 110 && floor(var.max_pods_per_node) == var.max_pods_per_node
    error_message = "Choose an integer from 1 to 110 supported by the shape."
  }
}

variable "node_pool_name" {
  type        = string
  default     = ""
  description = "Optional worker pool name (maximum 32 characters); empty derives a length-safe name from cluster_name."
  validation {
    condition     = length(var.node_pool_name) <= 32 && (var.node_pool_name == "" || trimspace(var.node_pool_name) != "")
    error_message = "Node pool name must be empty for automatic naming or contain 1 through 32 characters."
  }
}

variable "builder_availability_domain" {
  type        = string
  default     = ""
  description = "Image-source VM AD; empty uses the first selected worker AD. Pin this when changing worker placement to retain the existing source VM."
}

variable "create_public_cpu_pool" {
  type        = bool
  default     = false
  description = "Add a separate SSH-accessible public Ubuntu CPU diagnostic pool; retain the private GPU pool."
}
variable "cpu_node_shape" {
  type        = string
  default     = "VM.Standard.E4.Flex"
  description = "x86 non-GPU flexible shape for the optional public CPU pool."
  validation {
    condition     = can(regex("^VM\\.Standard\\.(E[3-9]|3)\\.Flex$", var.cpu_node_shape))
    error_message = "Select a supported x86 Standard Flex shape; ARM/GPU/HPC shapes are excluded."
  }
}
variable "cpu_node_ocpus" {
  type    = number
  default = 2
}
variable "cpu_node_memory_gbs" {
  type    = number
  default = 16
}
variable "cpu_node_count" {
  type    = number
  default = 1
  validation {
    condition     = var.cpu_node_count >= 1 && floor(var.cpu_node_count) == var.cpu_node_count
    error_message = "CPU worker count must be a positive integer."
  }
}
variable "cpu_availability_domain" {
  type        = string
  default     = ""
  description = "CPU worker AD; empty uses the main worker AD."
}
variable "cpu_subnet_cidr" {
  type        = string
  default     = "10.16.3.0/24"
  description = "Unused CIDR within the selected VCN for the public CPU subnet."
  validation {
    condition     = can(cidrnetmask(var.cpu_subnet_cidr))
    error_message = "Provide an IPv4 subnet CIDR."
  }
}
variable "cpu_internet_gateway_id" {
  type        = string
  default     = ""
  description = "Existing VCN internet gateway used by the CPU public subnet. Not needed with new infrastructure."
}
variable "cpu_ssh_public_key" {
  type        = string
  default     = ""
  description = "SSH public key for the additional CPU diagnostic pool."
}
variable "cpu_ssh_access_cidrs" {
  type        = list(string)
  default     = []
  description = "Restricted source CIDRs allowed to SSH to public CPU workers."
  validation {
    condition     = alltrue([for c in var.cpu_ssh_access_cidrs : can(cidrnetmask(c)) && try(tonumber(split("/", c)[1]) >= 24, false)])
    error_message = "Use valid IPv4 source CIDRs of /24 or narrower; prefer your workstation /32."
  }
}

variable "existing_pod_subnet_id" {
  type        = string
  default     = ""
  description = "Existing private regional VCN-native pod subnet. Empty retains the worker subnet for legacy CLI configurations."
}
variable "customize_node_labels" {
  type        = bool
  default     = false
  description = "Show the optional node label editor in ORM."
}

variable "generate_ssh_key" {
  type        = bool
  default     = false
  description = "Generate an RSA worker SSH key pair during Apply. The private key is stored in Terraform state."
}
variable "generate_cpu_ssh_key" {
  type        = bool
  default     = false
  description = "Generate a separate RSA CPU-worker SSH key pair during Apply. The private key is stored in Terraform state."
}
