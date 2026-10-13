# Non HPC Ubuntu Image on OKE

[![Deploy to Oracle Cloud](https://oci-resourcemanager-plugin.plugins.oci.oraclecloud.com/latest/deploy-to-oracle-cloud.svg)](https://cloud.oracle.com/resourcemanager/stacks/create?zipUrl=https%3A%2F%2Fgithub.com%2Fchiphwang1%2Foke-ubuntu-gpu-deploy%2Freleases%2Fdownload%2Fv1.0.10%2Foke-ubuntu-gpu.zip)

Deploy Ubuntu GPU workers on Enhanced OKE with VCN-native pod networking. The stack creates no HPC/RDMA configuration. Create a cluster and network, reuse a VCN, or add workers to an existing cluster. Include CPU workers for CoreDNS and other system pods unless another pool or matching GPU tolerations already allow them to run.

The stack removes only the OKE-managed NVIDIA GPU Plugin (`NvidiaGpuPlugin`). It leaves GPU Operator, health/metrics, discovery, and core add-ons at their existing or OKE-default settings. Driver compatibility and GPU Operator certification still need separate testing.

[Download ZIP](https://github.com/chiphwang1/oke-ubuntu-gpu-deploy/releases/download/v1.0.10/oke-ubuntu-gpu.zip) · [Release notes](https://github.com/chiphwang1/oke-ubuntu-gpu-deploy/releases/tag/v1.0.10) · [Stack options](#stack-options) · [Deploy](#deploy) · [SSH and cluster access](#ssh-and-cluster-access)

## Deployment modes

| `deployment_mode` | Creates | Required existing resources |
| --- | --- | --- |
| `new_infrastructure` (default) | VCN, gateways, subnets, cluster, GPU pool | None |
| `existing_vcn` | Cluster and GPU pool; public CPU subnet/pool if enabled | VCN; worker, pod, API endpoint, and load-balancer subnets |
| `existing_cluster` | GPU pool | Enhanced cluster with matching Kubernetes version and CNI; private worker and pod subnets in its VCN |

To reuse networking in ORM, select **Network compartment → VCN → subnets**. For an existing cluster, select its VCN. Use regional worker and pod subnets when placing nodes in multiple ADs. Reused subnets need OKE connectivity, outbound bootstrap access, and a free security-list association slot. The stack keeps existing security-list associations and adds a list allowing all protocols from `10.0.0.0/8`. That rule also applies to other resources in the selected subnets.

## Stack options

| Option / Terraform input | Default | Selection or requirement |
| --- | --- | --- |
| Compartment / `compartment_ocid` | Select | Required; deployer needs existing OCI permissions. The stack creates no IAM policies. |
| Region / `region` | Current Console region in ORM | Editable dropdown; open the Console in the intended region before resource selection. Local Terraform must supply it. |
| Cluster name / `cluster_name` | `oke-ubuntu-gpu` | Prefix for new resources |
| Cluster type and CNI | Enhanced; VCN-native | ORM keeps these fixed. Enhanced is required to disable the GPU Plugin through OKE add-on management. |
| Kubernetes / `kubernetes_version` | `v1.36.4` | Must be available regionally and have a mapped Ubuntu node package; must match a reused cluster |
| GPU shape / `node_shape` | Select | Required NVIDIA `VM.GPU` or `BM.GPU` shape; image compatibility, AD capacity, and quota still apply |
| GPU placement / `availability_domains`, `fault_domains` | Select ADs; OKE chooses FDs | One or more ADs required; optional multiple FDs. Use only `AD-1` in single-AD regions. CLI also accepts full AD names. |
| GPU count / `node_count` | `1` | At least one node |
| Ubuntu / `ubuntu_version` | `24.04` | `22.04` or `24.04` |
| Image / `image_mode` | `create` | Capture a clean custom image, or select `existing` and supply `ubuntu_image_id` |
| Boot volume / `boot_volume_size_gbs` | `100` GB | At least 50 GB and the image minimum |
| Native pods / `max_pods_per_node` | `31` | Must fit shape and subnet limits |
| SSH / `ssh_key_source` | `existing` | Upload/paste a public key, or choose `generate`; both pools share it |
| Public CPU pool / `create_public_cpu_pool` | `false` | Enable for a new cluster unless you provide another eligible pool or configure matching system-pod tolerations; available only when this stack creates the cluster |
| CPU sizing | E4.Flex; 2 OCPUs; 16 GB; 1 node | Configurable shape, size, count, and AD; AD defaults to the first GPU AD |
| Labels and tags | Custom labels off; purpose tag on | Optional maps; turn off **Add resource tags** for no freeform tags |

See [variables.tf](variables.tf) for all CLI inputs and [schema.yaml](schema.yaml) for ORM visibility. GPU and CPU shape dropdowns query OCI for the selected compartment and region; they do not guarantee capacity in the selected ADs.

The image builder uses `VM.Standard.E4.Flex`, 1 OCPU, and 8 GB RAM in the first selected GPU AD. The stopped builder VM and boot volume remain after image capture. Cloud-init installs Oracle's Ubuntu OKE node package and configures NVIDIA's signed APT repository before GPU bootstrap.

### NVIDIA toolkit cleanup

After successful `oke bootstrap`, GPU cloud-init removes `nvidia-container-toolkit`, `nvidia-container-toolkit-base`, `libnvidia-container1`, and `libnvidia-container-tools` so NVIDIA GPU Operator can manage the toolkit. It waits for CRI-O and kubelet, checks for NVIDIA runtime/hook references, simulates the purge, and refuses to remove any other package. It verifies that all four packages are absent and both services remain active. CPU bootstrap is unchanged.

The cleanup targets CRI-O with `runc`. The corrected sequence passed when rerun on an Ubuntu 24.04 / Kubernetes 1.36.4 / VM.GPU.A10.1 test node. A fresh boot with the corrected script, other versions/shapes, reboot persistence, and GPU Operator workloads still need testing. GPU Operator's toolkit container does not necessarily reinstall these as host APT packages.

Updating pool user data does not run cleanup on existing nodes. Review the Terraform plan and arrange node replacement separately when upgrading. The stack does not remove GPU drivers or install NVIDIA GPU Operator.

### CPU capacity for system workloads

The CPU pool remains optional (`create_public_cpu_pool = false`), including for new clusters. For a new cluster, enable **Add public CPU pool** unless you will provide another eligible worker pool or configure GPU tolerations for system workloads. Without either, CoreDNS and its autoscaler can remain Pending even when GPU nodes are Ready.

OKE GPU nodes carry the taint `nvidia.com/gpu=present:NoSchedule`. The default CoreDNS and `kube-dns-autoscaler` workloads do not tolerate it, so they cannot schedule on those GPU nodes. Disabling `NvidiaGpuPlugin` does not remove the taint. Other components, such as CNI, kube-proxy, and CSI node agents, have tolerations and can run on GPU nodes. [Oracle documents the CoreDNS requirement for GPU-only clusters](https://docs.oracle.com/en/learn/deploy-vllm-production-stack-oke/).

The CPU option is available in `new_infrastructure` and `existing_vcn` modes. In `existing_cluster` mode, arrange system-worker capacity separately; the stack cannot add its CPU pool. The stack adds no DNS tolerations.

A private CPU pool can host system workloads. This stack creates a public CPU pool so you can also use it for SSH access and diagnostics.

### Network defaults

ORM hides CIDR fields. New infrastructure uses VCN `10.16.0.0/16` and Kubernetes services `10.96.0.0/16`.

| Subnet | CIDR | Visibility |
| --- | --- | --- |
| API endpoint | `10.16.0.0/24` | Public; TCP 6443 from `0.0.0.0/0` |
| Load balancers | `10.16.1.0/24` | Private |
| GPU workers | `10.16.2.0/24` | Private; SSH from VCN CIDRs |
| CPU workers (when enabled) | `10.16.3.0/24` | Public; TCP 22 from `0.0.0.0/0` |
| Native pods | `10.16.4.0/22` | Private |

All selected subnets also allow all protocols from `10.0.0.0/8`; routes and host firewalls still apply. The API requires Kubernetes authentication. An existing cluster keeps its endpoint rules. To add the CPU pool to an existing VCN, supply `cpu_internet_gateway_id` and reserve an unused CPU CIDR inside that VCN. CLI users can change `cpu_subnet_cidr`. New infrastructure includes an internet gateway.

## Deploy

Use one Terraform state per deployment.

### 1. Deploy to Oracle button

1. Sign in to OCI and select the intended region, then click **Deploy to Oracle Cloud** above.
2. Confirm the configuration source, stack name, and compartment. Use Terraform **1.5.x** in Resource Manager, then select **Next**.
3. Complete the form with the GPU shape, ADs, and shared SSH-key option. Keep ORM's `InstancePrincipal` authentication. Enable **Add public CPU pool** for a new cluster unless you have provided another way to schedule system pods.
4. On Review, clear **Run apply** and create the stack.
5. Run **Plan**, review the job's changes, then run **Apply** using that plan. Check the job log and outputs when it finishes.

### 2. Download ZIP and upload through the Console

1. Open the [v1.0.10 release](https://github.com/chiphwang1/oke-ubuntu-gpu-deploy/releases/tag/v1.0.10). Under **Assets**, download **oke-ubuntu-gpu.zip**. Choose this asset rather than GitHub's source-code archives.
2. In the OCI Console, open **Resource Manager → Stacks**, choose the region and compartment, and select **Create stack**.
3. Select **My configuration → .Zip file**, then **Browse** and upload the ZIP without extracting it. Terraform files and `schema.yaml` are at the ZIP root.
4. Choose Terraform **1.5.x**, select **Next**, and complete the same configuration, Review, Plan, and Apply steps above.

See Oracle's [ZIP upload instructions](https://docs.oracle.com/en-us/iaas/Content/ResourceManager/Tasks/create-stack-local.htm). Existing stacks keep their uploaded configuration: use **Edit stack** to upload the new ZIP, review variables, and run a fresh Plan before Apply.

### 3. Local Terraform

Install Terraform **>= 1.5, < 2.0**, OCI CLI, Python 3, and `unzip`; install `kubectl` for cluster access. The deploying identity needs permissions for OKE, selected networking, Compute/images, and add-on management.

Download and extract the same release:

```bash
curl -fL -o oke-ubuntu-gpu.zip \
  https://github.com/chiphwang1/oke-ubuntu-gpu-deploy/releases/download/v1.0.10/oke-ubuntu-gpu.zip
unzip oke-ubuntu-gpu.zip -d oke-ubuntu-gpu
cd oke-ubuntu-gpu
```

For browser-based [OCI session authentication](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/session/authenticate.html), create a profile and use it for CLI commands:

```bash
oci session authenticate --region us-ashburn-1 --profile-name oke-local
export OCI_CLI_PROFILE=oke-local
export OCI_CLI_AUTH=security_token
```

Create `terraform.tfvars`, replacing the OCIDs and choosing a region/AD with capacity for your shape:

```hcl
tenancy_ocid        = "ocid1.tenancy.oc1..REPLACE_ME"
compartment_ocid    = "ocid1.compartment.oc1..REPLACE_ME"
region              = "us-ashburn-1"
auth                = "SecurityToken"
config_file_profile = "oke-local"

deployment_mode        = "new_infrastructure"
availability_domains   = ["AD-1"]
node_shape             = "VM.GPU.A10.1"
node_count             = 1
ubuntu_version         = "24.04"
kubernetes_version     = "v1.36.4"
ssh_key_source         = "generate"
create_public_cpu_pool = true
```

To supply your own key, set `ssh_key_source = "existing"` and `ssh_public_key = "ssh-ed25519 ..."` with the full contents of your `.pub` file. For API-key authentication, configure an OCI profile and use `auth = "APIKey"`, its `config_file_profile`, and `OCI_CLI_AUTH=api_key` instead. Renew an expired session before continuing.

```bash
terraform init
terraform validate
terraform plan -out=tfplan
terraform show tfplan
terraform apply tfplan
terraform output
```

Keep `terraform.tfvars`, plans, state, and private keys out of Git. Apply leaves the resources running. To manage an ORM deployment locally, use its existing state; do not start a second state for the same resources.

## SSH and cluster access

**Existing key:** upload a `.pub` file or use **Paste SSH key** in ORM. A nonblank key is required when `existing` is selected. Keep its matching private key locally.

**Generated key:** one RSA-4096 pair is created during Apply for both pools. After a successful Apply, copy `generated_worker_ssh_private_key` from ORM's **Application information**, or extract the ZIP locally and run:

```bash
python3 scripts/download_ssh_key.py \
  --job-id '<successful-apply-job-ocid>' --region us-ashburn-1 \
  --profile oke-local --auth security_token \
  --pool gpu --output ~/.ssh/oke_workers
```

The helper uses your OCI profile, saves the key with mode 600, removes temporary state, and refuses to overwrite a file. For local Terraform, save it to a new file:

```bash
(umask 077; set -C; terraform output -raw generated_worker_ssh_private_key > ~/.ssh/oke_workers)
```

Anyone with Terraform-state access can retrieve generated private keys. ORM creates keys during Apply; use the output or download helper to save them.

Use `ubuntu` as the SSH user. Find CPU public and GPU private IPs in **OKE → Cluster → Node pools → Nodes**. GPU workers require a route into the VCN; a public CPU worker can also be a jump host using the same key:

```bash
CPU_PUBLIC_IP='<cpu-public-ip>'
GPU_PRIVATE_IP='<gpu-private-ip>'
ssh -i ~/.ssh/oke_workers ubuntu@"$CPU_PUBLIC_IP"
ssh -i ~/.ssh/oke_workers \
  -o "ProxyCommand=ssh -i ~/.ssh/oke_workers -W %h:%p ubuntu@$CPU_PUBLIC_IP" \
  ubuntu@"$GPU_PRIVATE_IP"
```

Authenticate OCI CLI with your profile, then run the stack's `kubeconfig_command` output to write `./kubeconfig`. For a reused cluster, the command defaults to its private endpoint. Change the endpoint argument to `PUBLIC_ENDPOINT` if you need its public endpoint.

```bash
kubectl --kubeconfig ./kubeconfig get nodes
```

The explicit `--kubeconfig` flag takes precedence over `KUBECONFIG`. To use `~/.kube/config` by default, unset any obsolete `KUBECONFIG` export and remove it from your shell startup file.

## GPU Plugin behavior and upgrades

On the first Apply, the stack waits for the cluster, removes `NvidiaGpuPlugin`, and waits for removal before creating either node pool. It checks again after pool creation and at the end of every later Apply. It does not monitor add-ons between Applies. API errors or failed removal stop Apply. Removal affects the whole cluster, including other GPU pools.

Enhanced OKE is required because Basic clusters cannot disable specific add-ons through [OKE add-on management](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengcomparingenhancedwithbasicclusters_topic.htm).

Before upgrading, review Plan for replacements, particularly when changing CIDRs or worker SSH keys. Releases before v1.0.7 removed additional GPU add-ons; newer releases leave them alone but do not reinstall them. When upgrading from v1.0.4, replace `generate_ssh_key` / `generate_cpu_ssh_key` with `ssh_key_source` and share `ssh_public_key` across both pools. Keep `generate` selected to retain a generated worker key. Separate CPU-key and CPU SSH-CIDR inputs were removed.
