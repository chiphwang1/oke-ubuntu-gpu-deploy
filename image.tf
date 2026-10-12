data "oci_core_images" "ubuntu" {
  count                    = var.image_mode == "create" && var.source_ubuntu_image_id == "" ? 1 : 0
  compartment_id           = var.compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = var.ubuntu_version
  shape                    = var.builder_shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
  filter {
    name   = "display_name"
    values = ["^Canonical-Ubuntu-${replace(var.ubuntu_version, ".", "\\.")}-[0-9]{4}\\.[0-9]{2}\\.[0-9]{2}-[0-9]+$"]
    regex  = true

  }
}
resource "oci_core_instance" "image_source" {
  count               = var.image_mode == "create" ? 1 : 0
  compartment_id      = var.compartment_ocid
  availability_domain = var.builder_availability_domain != "" ? var.builder_availability_domain : local.primary_worker_ad
  display_name        = "${var.cluster_name}-image-source"
  shape               = var.builder_shape
  state               = "STOPPED"
  instance_options {
    are_legacy_imds_endpoints_disabled = true
  }
  shape_config {
    ocpus         = var.builder_ocpus
    memory_in_gbs = var.builder_memory_gbs
  }
  create_vnic_details {
    subnet_id        = local.worker_subnet_id
    assign_public_ip = false

  }
  source_details {
    source_type             = "image"
    source_id               = var.source_ubuntu_image_id != "" ? var.source_ubuntu_image_id : data.oci_core_images.ubuntu[0].images[0].id
    boot_volume_size_in_gbs = 50

  }
  freeform_tags = var.freeform_tags
  depends_on    = [terraform_data.validate]
}
resource "oci_core_image" "ubuntu" {
  count          = var.image_mode == "create" ? 1 : 0
  compartment_id = var.compartment_ocid
  instance_id    = oci_core_instance.image_source[0].id
  display_name   = "${var.cluster_name}-ubuntu-${var.ubuntu_version}-clean"
  freeform_tags  = var.freeform_tags
}
data "oci_core_image" "selected" {
  image_id = local.image_id
}
resource "terraform_data" "validate_image" {
  input = local.image_id
  lifecycle {
    precondition {
      condition     = strcontains(lower(data.oci_core_image.selected.operating_system), "ubuntu") && data.oci_core_image.selected.operating_system_version == var.ubuntu_version
      error_message = "Selected image must be Ubuntu and match ubuntu_version exactly."
    }
    precondition {
      condition     = contains([for s in data.oci_core_image_shapes.selected.image_shape_compatibilities : s.shape], var.node_shape)
      error_message = "The selected Ubuntu image does not list node_shape as compatible. Choose a supported image/shape combination."

    }

  }
}

data "oci_core_image_shapes" "selected" {
  image_id = local.image_id
}
