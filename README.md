# 🚀 EKS Terraform Deployment

A production-ready Infrastructure as Code (IaC) setup to deploy an Amazon EKS cluster on AWS using Terraform, including a custom VPC, managed node groups, IAM roles, and remote state management.

---

## 📋 Table of Contents

- [Architecture Overview](#architecture-overview)
- [Prerequisites](#prerequisites)
- [Project Structure](#project-structure)
- [Modules](#modules)
- [Remote State](#remote-state)
- [Getting Started](#getting-started)
- [Configuration](#configuration)
- [Outputs](#outputs)
- [Connecting to the Cluster](#connecting-to-the-cluster)
- [Tear Down](#tear-down)
- [Security Considerations](#security-considerations)
- [Troubleshooting](#troubleshooting)

---

## 🏗️ Architecture Overview

```
                        AWS Cloud
┌──────────────────────────────────────────────────────────┐
│                        VPC (10.0.0.0/16)                 │
│                                                          │
│  ┌─────────────────────────────────────────────────────┐ │
│  │              3 Availability Zones                   │ │
│  │                                                     │ │
│  │  Public Subnets          Private Subnets            │ │
│  │  ┌─────────────┐         ┌─────────────┐            │ │
│  │  │ NAT Gateway │────────►│ EKS Nodes   │            │ │
│  │  │ (per AZ)    │         │ (Node Group)│            │ │
│  │  └──────┬──────┘         └─────────────┘            │ │
│  │         │                                           │ │
│  └─────────┼───────────────────────────────────────────┘ │
│            │                                             │
│  ┌─────────▼──────┐    ┌──────────────────────────────┐  │
│  │Internet Gateway│    │     EKS Control Plane        │  │
│  └────────────────┘    │   (AWS Managed)              │  │
│                        └──────────────────────────────┘  │
└──────────────────────────────────────────────────────────┘

Remote State:
┌─────────────────┐     ┌──────────────────────┐
│   S3 Bucket     │     │  DynamoDB Table       │
│  (tfstate)      │     │  (State Locking)      │
└─────────────────┘     └──────────────────────┘
```

### What Gets Deployed

| Resource | Details |
|---|---|
| VPC | Custom VPC with DNS hostnames and DNS support enabled |
| Subnets | 3 public + 3 private subnets across 3 Availability Zones |
| Internet Gateway | Allows public subnet internet access |
| NAT Gateways | One per AZ for high availability egress from private subnets |
| EKS Cluster | Managed Kubernetes control plane with control plane logging |
| Managed Node Group | Auto-scaling EC2 worker nodes in private subnets |
| IAM Roles | Cluster service role + Node group role with required AWS policies |
| OIDC Provider | Enables IAM Roles for Service Accounts (IRSA) |
| S3 Bucket | Encrypted, versioned remote state storage |
| DynamoDB Table | Terraform state locking to prevent concurrent modifications |

---

## ✅ Prerequisites

Ensure the following tools are installed and configured before deploying:

| Tool | Version | Install |
|---|---|---|
| [Terraform](https://developer.hashicorp.com/terraform/install) | >= 1.5.0 | `choco install terraform` / `brew install terraform` |
| [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) | >= 2.0 | `choco install awscli` / `brew install awscli` |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | >= 1.29 | `choco install kubernetes-cli` / `brew install kubectl` |
| [Git](https://git-scm.com/) | Any | `choco install git` / `brew install git` |

### AWS Credentials

Configure your AWS credentials before running any Terraform commands:

```bash
aws configure
# AWS Access Key ID: <your-access-key>
# AWS Secret Access Key: <your-secret-key>
# Default region name: us-east-1
# Default output format: json
```

Your IAM user/role will need the following permissions:
- `AmazonEKSClusterPolicy`
- `AmazonVPCFullAccess`
- `IAMFullAccess`
- `AmazonS3FullAccess`
- `AmazonDynamoDBFullAccess`
- `AmazonEC2FullAccess`

---

## 📁 Project Structure

```
eks-terraform/
├── main.tf                  # Root module — wires VPC + EKS modules together
├── variables.tf             # Root input variables
├── outputs.tf               # Root outputs (cluster name, endpoint, etc.)
├── versions.tf              # Provider and Terraform version constraints
├── backend.tf               # Remote state backend configuration (S3 + DynamoDB)
├── terraform.tfvars         # Your variable values (do not commit secrets!)
├── .gitignore               # Excludes .terraform/, *.tfstate, *.tfvars
├── README.md                # This file
│
├── bootstrap/               # One-time setup for remote state infrastructure
│   └── main.tf              # Creates S3 bucket + DynamoDB table
│
└── modules/
    ├── vpc/
    │   ├── main.tf          # VPC, subnets, IGW, NAT gateways, route tables
    │   ├── variables.tf     # VPC module input variables
    │   └── outputs.tf       # VPC module outputs (vpc_id, subnet IDs)
    └── eks/
        ├── main.tf          # EKS cluster, node group, IAM roles, OIDC provider
        ├── variables.tf     # EKS module input variables
        └── outputs.tf       # EKS module outputs (endpoint, CA cert, OIDC ARN)
```

---

## 🧩 Modules

### VPC Module (`modules/vpc`)

Creates a fully configured network for EKS including subnet tagging required for Kubernetes load balancer discovery.

| Input | Type | Default | Description |
|---|---|---|---|
| `vpc_cidr` | string | — | CIDR block for the VPC |
| `cluster_name` | string | — | Used for resource naming and subnet tags |
| `environment` | string | — | Environment label (e.g. dev, prod) |

| Output | Description |
|---|---|
| `vpc_id` | The VPC ID |
| `private_subnets` | List of private subnet IDs |
| `public_subnets` | List of public subnet IDs |

---

### EKS Module (`modules/eks`)

Creates the EKS cluster, IAM service roles, managed node group, and OIDC provider.

| Input | Type | Default | Description |
|---|---|---|---|
| `cluster_name` | string | — | Name of the EKS cluster |
| `cluster_version` | string | — | Kubernetes version (e.g. `1.29`) |
| `vpc_id` | string | — | VPC to deploy the cluster into |
| `private_subnet_ids` | list(string) | — | Subnets for worker nodes |
| `node_instance_types` | list(string) | `["t3.medium"]` | EC2 instance types for nodes |
| `node_desired_size` | number | `2` | Desired number of worker nodes |
| `node_min_size` | number | `1` | Minimum number of worker nodes |
| `node_max_size` | number | `4` | Maximum number of worker nodes |

| Output | Description |
|---|---|
| `cluster_name` | EKS cluster name |
| `cluster_endpoint` | API server endpoint URL |
| `cluster_ca_certificate` | Base64 encoded cluster CA certificate |
| `oidc_provider_arn` | ARN of the OIDC provider for IRSA |
| `node_role_arn` | ARN of the node group IAM role |

---

## 🗄️ Remote State

State is stored remotely in S3 with DynamoDB locking to support team collaboration and prevent state corruption.

### Bootstrap (run once)

```bash
cd bootstrap
terraform init
terraform apply
cd ..
```

This creates:
- **S3 bucket** — encrypted, versioned, private, with `prevent_destroy`
- **DynamoDB table** — `PAY_PER_REQUEST` billing with `LockID` hash key

### How Locking Works

```
Developer A: terraform apply → acquires DynamoDB lock → writes state to S3 → releases lock
Developer B: terraform apply → lock exists → ❌ blocked until Developer A finishes
```

---

## 🚀 Getting Started

### 1. Clone the repository

```bash
git clone https://github.com/your-org/payday-infra-eks.git
cd payday-infra-eks
```

### 2. Bootstrap remote state (first time only)

```bash
cd bootstrap
terraform init
terraform apply
cd ..
```

### 3. Initialize the main project

```bash
terraform init
```

### 4. Review the execution plan

```bash
terraform plan -var-file="terraform.tfvars"
```

### 5. Deploy the infrastructure

```bash
terraform apply -var-file="terraform.tfvars"
```

Type `yes` when prompted. Deployment typically takes **10–15 minutes**.

---

## ⚙️ Configuration

Edit `terraform.tfvars` to customize your deployment:

```hcl
region          = "us-east-1"
cluster_name    = "my-eks-cluster"
cluster_version = "1.29"
vpc_cidr        = "10.0.0.0/16"
environment     = "dev"
```

> ⚠️ **Never commit `terraform.tfvars`** if it contains sensitive values. It is excluded by `.gitignore` by default.

### Multi-Environment Setup

Use separate state keys per environment in `backend.tf`:

```hcl
# dev
key = "dev/eks/terraform.tfstate"

# staging
key = "staging/eks/terraform.tfstate"

# prod
key = "prod/eks/terraform.tfstate"
```

---

## 📤 Outputs

After a successful `terraform apply`, the following values are displayed:

| Output | Description |
|---|---|
| `vpc_id` | The ID of the created VPC |
| `cluster_name` | The EKS cluster name |
| `cluster_endpoint` | The Kubernetes API server URL |
| `oidc_provider_arn` | ARN for IRSA configuration |

To view outputs at any time:

```bash
terraform output
```

---

## 🔌 Connecting to the Cluster

After deployment, configure `kubectl` to talk to your new cluster:

```bash
aws eks update-kubeconfig \
  --region us-east-1 \
  --name my-eks-cluster
```

Verify the nodes are ready:

```bash
kubectl get nodes
```

Expected output:

```
NAME                          STATUS   ROLES    AGE   VERSION
ip-10-0-10-x.ec2.internal     Ready    <none>   2m    v1.29.x
ip-10-0-11-x.ec2.internal     Ready    <none>   2m    v1.29.x
```

---

## 💣 Tear Down

To destroy all infrastructure:

```bash
terraform destroy -var-file="terraform.tfvars"
```

> ⚠️ The S3 bucket and DynamoDB table have `prevent_destroy = true`. To delete them you must first remove that lifecycle rule from `bootstrap/main.tf`, then run `terraform destroy` inside the `bootstrap/` folder separately.

---

## 🔒 Security Considerations

- **Private nodes** — Worker nodes live in private subnets and are not directly internet-accessible
- **NAT Gateways** — Nodes can pull images and updates outbound without inbound exposure
- **Encrypted state** — S3 state bucket uses AES256 server-side encryption
- **State versioning** — S3 versioning allows rollback to any previous state
- **Public access blocked** — S3 bucket blocks all public access policies and ACLs
- **Control plane logging** — API, audit, authenticator, controller, and scheduler logs sent to CloudWatch
- **OIDC / IRSA** — Use IAM Roles for Service Accounts instead of node-level IAM permissions for pods
- **Endpoint access** — Set `endpoint_public_access = false` in the EKS module for fully private clusters (requires VPN or bastion host)

---

## 🛠️ Troubleshooting

### Provider version mismatch
```
Error: locked provider does not match configured version constraint
```
**Fix:** Run `terraform init -upgrade`

---

### Large files blocked by GitHub
```
Error: File .terraform/providers/... exceeds GitHub's file size limit
```
**Fix:** The `.terraform/` directory should never be committed. Run:
```bash
git filter-repo --path .terraform/ --invert-paths --force
git push origin main --force
```

---

### State lock not released
```
Error: Error acquiring the state lock
```
**Fix:** If a previous run was interrupted, manually release the lock:
```bash
terraform force-unlock <LOCK_ID>
```

---

### Nodes not joining the cluster
Ensure the node group IAM role has these three policies attached:
- `AmazonEKSWorkerNodePolicy`
- `AmazonEKS_CNI_Policy`
- `AmazonEC2ContainerRegistryReadOnly`

---


