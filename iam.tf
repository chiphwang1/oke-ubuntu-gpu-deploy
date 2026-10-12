locals {
  create_deployment_policy = var.create_iam_policy && var.existing_iam_policy_id == ""
  deployment_subject       = "group id ${var.deployment_group_id}"
  network_compartment_id   = var.iam_network_compartment_id == "" ? var.compartment_ocid : var.iam_network_compartment_id
  deployment_statements = concat(
    [for family in ["cluster-family", "instance-family", "volume-family", "orm-family"] :
      "Allow ${local.deployment_subject} to manage ${family} in compartment id ${var.compartment_ocid}"
    ],
    ["Allow ${local.deployment_subject} to manage virtual-network-family in compartment id ${var.compartment_ocid}",
    "Allow ${local.deployment_subject} to inspect compartments in tenancy"],
    local.network_compartment_id != var.compartment_ocid ? [
      "Allow ${local.deployment_subject} to use virtual-network-family in compartment id ${local.network_compartment_id}"
    ] : []
  )
}

# Creation depends only on explicit inputs, not a list of policies: discovery-based
# count would drop this resource from state and destroy it on the next apply.
resource "oci_identity_policy" "deployment" {
  provider       = oci.home
  count          = local.create_deployment_policy ? 1 : 0
  compartment_id = var.tenancy_ocid
  name           = var.iam_policy_name
  description    = "Deployment access for the Ubuntu GPU Enhanced OKE Terraform/ORM stack"
  statements     = local.deployment_statements
  freeform_tags  = var.freeform_tags

  lifecycle {
    precondition {
      condition     = can(regex("^ocid1\\.group\\.", var.deployment_group_id)) && var.iam_home_region != ""
      error_message = "Policy creation requires an existing deployment_group_id and iam_home_region. The applying identity must already be authorized to create policies."
    }
  }
}

# Existing policies can be attached at the tenancy root or deployment compartment.
data "oci_identity_policies" "existing" {
  provider       = oci.home
  for_each       = var.existing_iam_policy_id != "" ? toset([var.tenancy_ocid, var.compartment_ocid]) : toset([])
  compartment_id = each.value
  filter {
    name   = "id"
    values = [var.existing_iam_policy_id]
  }
}

resource "terraform_data" "validate_iam" {
  lifecycle {
    precondition {
      condition     = var.existing_iam_policy_id == "" ? true : (var.iam_home_region != "" && length(flatten([for p in data.oci_identity_policies.existing : p.policies])) == 1)
      error_message = "Set iam_home_region and supply a policy OCID attached to the tenancy root or deployment compartment."
    }
  }
}

output "deployment_iam_policy_id" {
  value = var.existing_iam_policy_id != "" ? var.existing_iam_policy_id : try(oci_identity_policy.deployment[0].id, null)
}
