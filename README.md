# Ubuntu GPU certification on OKE

[![Deploy to Oracle Cloud](https://oci-resourcemanager-plugin.plugins.oci.oraclecloud.com/latest/deploy-to-oracle-cloud.svg)](https://cloud.oracle.com/resourcemanager/stacks/create?region=us-ashburn-1&zipUrl=https%3A%2F%2Fgithub.com%2Fchiphwang1%2Foke-ubuntu-gpu-deploy%2Freleases%2Fdownload%2Fv1.0.3%2Foke-ubuntu-gpu.zip)

The button loads the release ZIP into OCI Resource Manager. The package includes Terraform files and `schema.yaml` at its root. After accepting the configuration and selecting **Next**, Resource Manager displays the schema-driven configuration form.

Select your compartment, region, Ubuntu version, GPU shape, node count and deployment mode. The stack can create infrastructure, reuse existing VCN/subnets, or add workers to an existing Enhanced OKE cluster. VCN-native CNI is configured automatically. An optional public CPU diagnostic pool is available with a supplied SSH public key and restricted source CIDRs.

Use Terraform **1.5.x** in Resource Manager and retain `InstancePrincipal` authentication. The deploying identity must already have OCI permissions for the selected resources. On Review, clear **Run apply** to create the stack first, then run Plan and review before Apply. Clicking the button alone does not provision infrastructure.

The stack disables and removes OKE-managed GPU device-plugin, GPU Operator and related GPU add-ons. On an existing cluster this affects other GPU workers, so use a dedicated certification cluster. GPU cloud-init installs Oracle's Ubuntu node package and configures NVIDIA's signed APT repository before `oke bootstrap`. Driver compatibility and GPU Operator certification require separate validation.

New infrastructure includes an Enhanced OKE cluster with a public API endpoint. By default, a clean Ubuntu custom image is captured from a CPU builder VM; its stopped VM and boot volume are retained. GPU workers use private addresses. An existing custom image can also be selected.

No Terraform state, credentials, customer-specific variables, or live test records are included in this deployment package. Keep deployed resources and state after testing; cleanup is a separate explicit operation.

The node shape is required. Add availability domains using the dropdown list; select multiple fault domains if needed. Custom node labels are optional and their editor is disabled by default. The automatic image builder uses VM.Standard.E4.Flex, 1 OCPU and 8 GB RAM in the first selected worker AD, without customer configuration fields.

For existing networking, choose Network compartment, VCN, and subnets in that order. Use regional worker subnets for multiple ADs. Resource discovery uses the current Console region.

Workers permit SSH from every IPv4 subnet in their VCN, with a supplied public key. Public CPU external SSH retains its restricted allowlist. New cluster endpoints allow TCP 6443 from 0.0.0.0/0; public endpoints remain subject to Kubernetes authentication. Existing-cluster mode retains that cluster's endpoint rules.

The automatic network layout is VCN 10.16.0.0/16, public API 10.16.0.0/24, private load balancers 10.16.1.0/24, private nodes 10.16.2.0/24, and private native pods 10.16.4.0/22. The optional public CPU subnet is 10.16.3.0/24. CIDR fields are hidden in ORM. Existing-network mode provides separate worker and pod subnet dropdowns.

These defaults apply to new deployments. Review Terraform Plan before updating an older stack: changing subnet CIDRs can replace networking and nodes. Existing deployed resources are not modified merely by publishing this package.
