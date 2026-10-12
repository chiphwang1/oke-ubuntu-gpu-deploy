# Ubuntu GPU certification on OKE

[![Deploy to Oracle Cloud](https://oci-resourcemanager-plugin.plugins.oci.oraclecloud.com/latest/deploy-to-oracle-cloud.svg)](https://cloud.oracle.com/resourcemanager/stacks/create?region=us-ashburn-1&zipUrl=https%3A%2F%2Fgithub.com%2Fchiphwang1%2Foke-ubuntu-gpu-deploy%2Freleases%2Fdownload%2Fv1.0.2%2Foke-ubuntu-gpu.zip)

The button loads the release ZIP into OCI Resource Manager. The package includes Terraform files and `schema.yaml` at its root. After accepting the configuration and selecting **Next**, Resource Manager displays the schema-driven configuration form.

Select your compartment, region, Ubuntu version, GPU shape, node count and deployment mode. The stack can create infrastructure, reuse existing VCN/subnets, or add workers to an existing Enhanced OKE cluster. VCN-native CNI is the default. An optional public CPU diagnostic pool is available with a supplied SSH public key and restricted source CIDRs.

Use Terraform **1.5.x** in Resource Manager and retain `InstancePrincipal` authentication. The deploying identity must already have OCI permissions for the selected resources. On Review, clear **Run apply** to create the stack first, then run Plan and review before Apply. Clicking the button alone does not provision infrastructure.

The stack disables and removes OKE-managed GPU device-plugin, GPU Operator and related GPU add-ons. On an existing cluster this affects other GPU workers, so use a dedicated certification cluster. GPU cloud-init installs Oracle's Ubuntu node package and configures NVIDIA's signed APT repository before `oke bootstrap`. Driver compatibility and GPU Operator certification require separate validation.

New infrastructure includes networking and an Enhanced OKE cluster. By default, a clean Ubuntu custom image is captured from a CPU builder VM; its stopped VM and boot volume are retained. GPU workers use private addresses. An existing custom image can also be selected.

No Terraform state, credentials, customer-specific variables, or live test records are included in this deployment package. Keep deployed resources and state after testing; cleanup is a separate explicit operation.
