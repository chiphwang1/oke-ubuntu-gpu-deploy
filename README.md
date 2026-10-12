# Ubuntu GPU certification on OKE

[![Deploy to Oracle Cloud](https://oci-resourcemanager-plugin.plugins.oci.oraclecloud.com/latest/deploy-to-oracle-cloud.svg)](https://cloud.oracle.com/resourcemanager/stacks/create?zipUrl=https%3A%2F%2Fgithub.com%2Fchiphwang1%2Foke-ubuntu-gpu-deploy%2Freleases%2Fdownload%2Fv1.0.5%2Foke-ubuntu-gpu.zip)

The button loads the release ZIP into OCI Resource Manager. The package includes Terraform files and `schema.yaml` at its root. After accepting the configuration and selecting **Next**, Resource Manager displays the schema-driven configuration form.

Select your compartment, region, Ubuntu version, GPU shape, node count and deployment mode. The stack can create infrastructure, reuse existing VCN/subnets, or add workers to an existing Enhanced OKE cluster. VCN-native CNI is configured automatically. An optional public CPU diagnostic pool is available with the same generated or supplied SSH key as the GPU pool and TCP 22 open to `0.0.0.0/0`.

Use Terraform **1.5.x** in Resource Manager and retain `InstancePrincipal` authentication. The deploying identity must already have OCI permissions for the selected resources. On Review, clear **Run apply** to create the stack first, then run Plan and review before Apply. Clicking the button alone does not provision infrastructure.

The stack disables and removes OKE-managed GPU device-plugin, GPU Operator and related GPU add-ons. On an existing cluster this affects other GPU workers, so use a dedicated certification cluster. GPU cloud-init installs Oracle's Ubuntu node package and configures NVIDIA's signed APT repository before `oke bootstrap`. Driver compatibility and GPU Operator certification require separate validation.

New infrastructure includes an Enhanced OKE cluster with a public API endpoint. By default, a clean Ubuntu custom image is captured from a CPU builder VM; its stopped VM and boot volume are retained. GPU workers use private addresses. An existing custom image can also be selected.

No Terraform state, credentials, customer-specific variables, or live test records are included in this deployment package. Keep deployed resources and state after testing; cleanup is a separate explicit operation.

The node shape is required. Select one or more availability domains in the multi-select dropdown, like fault domains. Custom node labels are optional and their editor is disabled by default. The automatic image builder uses VM.Standard.E4.Flex, 1 OCPU and 8 GB RAM in the first selected worker AD, without customer configuration fields.

For existing networking, choose Network compartment, VCN, and subnets in that order. Use regional worker subnets for multiple ADs. Resource discovery uses the current Console region.

Workers permit SSH from every IPv4 subnet in their VCN, with a supplied public key. All selected stack subnets also allow all inbound protocols from 10.0.0.0/8. Public CPU SSH allows TCP 22 from `0.0.0.0/0`; no source-CIDR field is required. New cluster endpoints allow TCP 6443 from 0.0.0.0/0; public endpoints remain subject to Kubernetes authentication. Existing-cluster mode retains that cluster's endpoint rules.

The automatic network layout is VCN 10.16.0.0/16, public API 10.16.0.0/24, private load balancers 10.16.1.0/24, private nodes 10.16.2.0/24, and private native pods 10.16.4.0/22. The optional public CPU subnet is 10.16.3.0/24. CIDR fields are hidden in ORM. Existing-network mode provides separate worker and pod subnet dropdowns.

These defaults apply to new deployments. Review Terraform Plan before updating an older stack: changing subnet CIDRs can replace networking and nodes. Existing deployed resources are not modified merely by publishing this package.

### SSH key options

In **SSH access — GPU and CPU workers**, choose **generate** for one RSA-4096 pair created during Apply, or **existing** to upload a `.pub` file with **Choose SSH key file** or use **Paste SSH key**. This section is always visible. Both GPU and CPU workers use this same key; keep the corresponding private key on your computer.

Generated private keys are stored in Terraform state and exposed as sensitive outputs in **Application information**. They become available after Apply. ORM supports copying the output; it does not provide a browser-side key-generation/download widget. Save the copied key to a file with mode 600, or use the included download helper:

```bash
python3 scripts/download_ssh_key.py --job-id <apply-job-ocid> --region <region> --pool gpu --output ~/.ssh/oke_gpu
```

The downloaded key connects to both GPU and CPU workers. `--pool cpu` remains a compatibility alias when the CPU pool is enabled. Optional `--profile` and `--auth` select OCI CLI authentication. The helper downloads job state into a private temporary directory, saves only the requested key with mode 600, removes temporary state and refuses to overwrite existing files. Users with Terraform-state access can retrieve generated keys; supplied-key mode stores only a public key.

The existing internet gateway field appears only when adding the public CPU pool to an **existing VCN**. New infrastructure automatically creates its internet gateway. For reused subnets, the stack adds a shared 10/8 security list while preserving their existing list associations. This affects all resources in the selected API, worker, pod and LB subnets; unrelated VCN subnets are untouched. A free security-list association slot is required. Explicit future cleanup detaches only this stack's shared list.

The Deploy button no longer forces Ashburn. Region defaults to the current Console region and remains an editable dropdown. ORM does not resolve a tenancy-home-region schema default; open the Console in the home region before launching the button to use that default. Use the intended region in the Console before selecting regional resources.

Upgrading from v1.0.4: replace `generate_ssh_key` / `generate_cpu_ssh_key` with `ssh_key_source = "generate"` or `"existing"`, and use `ssh_public_key` for both pools. To retain an existing generated worker key, select `generate`. Separate CPU-key inputs and `cpu_ssh_access_cidrs` were removed; CPU workers now share the worker key. Review Plan before Apply because changing a node pool SSH key can replace nodes.
