# FortiGate VPN Infrastructure with Terraform

Multi-VPC AWS infrastructure with FortiGate Next-Generation Firewalls connected via IPSec VPN tunnel, plus an AI-powered documentation agent using Amazon Bedrock.

## Architecture Overview

```
┌────────────────────────────────────┐         ┌─────────────────────────────────────┐
│         VPC 1 (10.0.0.0/16)        │         │       VPC 2 (10.100.0.0/16)         │
│                                    │         │                                     │
│  ┌──────────────────────────────┐  │         │  ┌───────────────────────────────┐  │
│  │   Public Subnet (10.0.0.0/24)│  │         │  │ Public Subnet (10.100.0.0/24) │  │
│  │                              │  │         │  │                               │  │
│  │      ┌──────────────┐        │  │  IPSec  │  │       ┌──────────────┐        │  │
│  │      │ FortiGate-1  │◄───────┼──┼─────────┼──┼──────►│ FortiGate-2  │        │  │
│  │      └──────┬───────┘        │  │   VPN   │  │       └──────┬───────┘        │  │
│  └─────────────┼────────────────┘  │  Tunnel │  └──────────────┼────────────────┘  │
│                │                   │         │                 │                   │
│  ┌─────────────┼────────────────┐  │         │  ┌──────────────┼────────────────┐  │
│  │  Private Subnet (10.0.1.0/24)│  │         │  │Private Subnet (10.100.1.0/24) │  │
│  │             │                │  │         │  │              │                │  │
│  │      ┌──────┴───────┐        │  │         │  │      ┌───────┴───────┐        │  │
│  │      │ Ubuntu-VM-1  │        │  │         │  │      │ Ubuntu-VM-2   │        │  │
│  │      │  10.0.1.10   │        │  │         │  │      │ 10.100.1.10   │        │  │
│  │      └──────────────┘        │  │         │  │      └───────────────┘        │  │
│  └──────────────────────────────┘  │         │  └───────────────────────────────┘  │
└────────────────────────────────────┘         └─────────────────────────────────────┘
```

## Dependencies

### Required Software

| Dependency | Version | Purpose |
|------------|---------|---------|
| [Terraform](https://www.terraform.io/downloads) | >= 1.0 | Infrastructure as Code |
| [AWS CLI](https://aws.amazon.com/cli/) | >= 2.0 | AWS authentication & S3 operations |
| [Python](https://www.python.org/) | >= 3.8 | Bedrock agent scripts (Phase 2) |
| [boto3](https://boto3.amazonaws.com/v1/documentation/api/latest/index.html) | >= 1.28 | AWS SDK for Python (Phase 2) |

### AWS Dependencies

| Service | Purpose | Required Actions |
|---------|---------|------------------|
| **EC2** | VMs, VPCs, Security Groups | Full access |
| **IAM** | Roles for EC2 instances | CreateRole, AttachPolicy |
| **S3** | Terraform state (optional), Bedrock input | GetObject, PutObject |
| **Bedrock** | AI documentation agent (Phase 2) | InvokeModel |

### AWS Marketplace Subscription

**FortiGate-VM PAYG (Pay-As-You-Go)** must be subscribed before deployment:

1. Go to [AWS Marketplace](https://aws.amazon.com/marketplace)
2. Search for "FortiGate-VM"
3. Select "Fortinet FortiGate Next-Generation Firewall (PAYG)"
4. Click "Continue to Subscribe"
5. Accept terms and conditions

> **Product Code:** `2wqkpek696qhdeo7lbbjncqli`

### Terraform Providers

| Provider | Version | Source |
|----------|---------|--------|
| `hashicorp/aws` | ~> 5.0 | registry.terraform.io |

### Credentials (Pre-configured)

The following credentials have been generated for this deployment:

| Item | Value |
|------|-------|
| **FortiGate Admin Username** | `admin` |
| **FortiGate Admin Password** | `****************` |
| **VPN Pre-Shared Key** | `****************` |
| **SSH Private Key** | `****************` |

> **Note:** These credentials are stored in `terraform.tfvars` (gitignored). Change them for production use.

---

## Project Structure

```
terraform/
├── main.tf                     # Root module - orchestrates all child modules
├── variables.tf                # Input variables
├── outputs.tf                  # Output values
├── providers.tf                # AWS provider configuration
├── Makefile                    # Convenience commands for setup/teardown
├── terraform.tfvars            # Variable values (gitignored)
├── terraform.tfvars.example    # Example configuration
├── fortigate-demo-key.pem      # SSH private key (gitignored)
├── .gitignore                  # Excludes sensitive files
│
├── modules/
│   ├── vpc/                    # VPC module (reusable)
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   ├── fortigate/              # FortiGate module (reusable)
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── templates/
│   │       └── fortigate_config.tpl
│   │
│   ├── ubuntu/                 # Ubuntu module (reusable)
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   ├── bedrock-agent/          # Phase 2: AI Documentation Agent
│   │   ├── main.tf             # S3, Bedrock Agent, Action Groups
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── iam.tf              # IAM roles (Bedrock, Lambda, CodeBuild)
│   │   ├── lambda.tf           # 9 Lambda functions
│   │   ├── codebuild.tf        # CodeBuild for Terraform execution
│   │   ├── openapi-schema.yaml # Action group API schema
│   │   └── lambda-code/        # Python source files
│   │
│   └── chat-ui/                # Phase 3: Web Chat Interface
│       ├── main.tf             # S3, CloudFront, API Gateway
│       ├── variables.tf
│       ├── outputs.tf
│       ├── iam.tf              # Lambda execution role
│       └── lambda-code/
│           └── chat_handler.py # API handler for Bedrock Agent
│
├── chat-ui/                    # React Chat Application
│   ├── src/
│   │   ├── App.jsx             # Main chat component
│   │   ├── main.jsx            # React entry point
│   │   └── index.css           # Tailwind styles
│   ├── package.json
│   └── vite.config.js
│
├── docs/
│   ├── PHASE1_INFRASTRUCTURE.md      # Detailed infrastructure documentation
│   ├── PHASE2_BEDROCK_AGENT.md       # AI agent implementation details
│   ├── PHASE2_IMPLEMENTATION_TASKS.md # Step-by-step task list
│   ├── PRESENTATION.md               # Presentation content
│   └── slides.html                   # Interactive HTML slides
│
├── scripts/
│   ├── test-infrastructure.sh     # Automated infrastructure tests
│   └── generate-report.sh         # Deployment report generator
│
└── requirements/               # Assignment requirements (PDFs)
```

---

## Quick Start

### 1. Clone and Configure

```bash
# Navigate to project
cd terraform

# Copy example configuration
cp terraform.tfvars.example terraform.tfvars

# Edit configuration (set passwords, etc.)
vim terraform.tfvars
```

### 2. Set AWS Profile

```bash
export AWS_PROFILE=personal
export AWS_REGION=us-east-2
```

### 3. Initialize and Deploy

**Option A: Using Make (Recommended)**

```bash
# Full deployment pipeline (init, validate, plan, apply)
make deploy

# Or step by step
make init
make plan
make apply
```

**Option B: Using Terraform Directly**

```bash
terraform init
terraform plan
terraform apply
```

### 4. Verify Deployment

```bash
# View outputs
terraform output

# SSH to FortiGate
ssh -i fortigate-demo-key.pem admin@$(terraform output -raw fortigate1_public_ip)
```

---

## Configuration

### terraform.tfvars

```hcl
# AWS Configuration
aws_region = "us-east-2"

# SSH Key Pair (created automatically or specify existing)
key_name = "fortigate-demo-key"

# Admin access CIDR (restrict for security)
admin_cidr = "0.0.0.0/0"  # Change to your IP: "x.x.x.x/32"

# VPC 1 Configuration
vpc1_cidr                = "10.0.0.0/16"
vpc1_public_subnet_cidr  = "10.0.0.0/24"
vpc1_private_subnet_cidr = "10.0.1.0/24"

# VPC 2 Configuration
vpc2_cidr                = "10.100.0.0/16"
vpc2_public_subnet_cidr  = "10.100.0.0/24"
vpc2_private_subnet_cidr = "10.100.1.0/24"

# FortiGate Configuration
fortigate_instance_type  = "t3.small"
fortigate_admin_password = "YourSecurePassword123!"  # Change this!

# Ubuntu Configuration
ubuntu_instance_type = "t3.micro"

# VPN Configuration
vpn_psk = "YourSecurePreSharedKey456!"  # Change this!
```

### Variables Reference

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `aws_region` | string | `us-east-2` | AWS region for deployment |
| `key_name` | string | - | SSH key pair name |
| `admin_cidr` | string | `0.0.0.0/0` | CIDR for management access |
| `vpc1_cidr` | string | `10.0.0.0/16` | VPC 1 CIDR block |
| `vpc2_cidr` | string | `10.100.0.0/16` | VPC 2 CIDR block |
| `fortigate_instance_type` | string | `t3.small` | FortiGate EC2 instance type |
| `fortigate_admin_password` | string | - | FortiGate admin password |
| `ubuntu_instance_type` | string | `t3.micro` | Ubuntu EC2 instance type |
| `vpn_psk` | string | - | IPSec VPN pre-shared key |
| `enable_bedrock_agent` | bool | `false` | Deploy Phase 2 Bedrock AI Agent |
| `enable_chat_ui` | bool | `false` | Deploy Phase 3 Chat UI (requires agent) |

---

## Module Documentation

### VPC Module

Creates a complete VPC with public/private subnets.

```hcl
module "vpc1" {
  source = "./modules/vpc"

  name                = "vpc1"
  vpc_cidr            = "10.0.0.0/16"
  public_subnet_cidr  = "10.0.0.0/24"
  private_subnet_cidr = "10.0.1.0/24"
  availability_zone   = "us-east-2a"
}
```

**Resources Created:**
- VPC with DNS support
- Internet Gateway
- Public subnet (auto-assign public IP)
- Private subnet
- Route tables and associations

### FortiGate Module

Deploys FortiGate NGFW with VPN configuration.

```hcl
module "fortigate1" {
  source = "./modules/fortigate"

  name                       = "FortiGate-1"
  instance_type              = "t3.small"
  key_name                   = "my-key"
  vpc_id                     = module.vpc1.vpc_id
  public_subnet_id           = module.vpc1.public_subnet_id
  private_subnet_id          = module.vpc1.private_subnet_id
  private_subnet_cidr        = module.vpc1.private_subnet_cidr
  remote_private_subnet_cidr = "10.100.1.0/24"
  admin_password             = var.fortigate_admin_password
  vpn_psk                    = var.vpn_psk
  vpn_peer_ip                = aws_eip.fortigate2.public_ip
  vpn_name                   = "vpn-to-vpc2"
  eip_allocation_id          = aws_eip.fortigate1.id
  eip_public_ip              = aws_eip.fortigate1.public_ip
}
```

**Resources Created:**
- FortiGate EC2 instance (from Marketplace AMI)
- Public and private network interfaces
- Security groups (management, VPN, internal)
- EIP association
- Bootstrap configuration with VPN settings

### Ubuntu Module

Deploys Ubuntu VM for connectivity testing.

```hcl
module "ubuntu1" {
  source = "./modules/ubuntu"

  name               = "Ubuntu-VM-1"
  instance_type      = "t3.micro"
  key_name           = "my-key"
  vpc_id             = module.vpc1.vpc_id
  subnet_id          = module.vpc1.private_subnet_id
  private_ip         = "10.0.1.10"
  remote_subnet_cidr = "10.100.1.0/24"
}
```

**Resources Created:**
- Ubuntu 22.04 EC2 instance
- Security group (SSH, ICMP, cross-VPC traffic)

---

## Outputs

After deployment, the following outputs are available:

| Output | Description |
|--------|-------------|
| `vpc1_id` | VPC 1 ID |
| `vpc2_id` | VPC 2 ID |
| `fortigate1_public_ip` | FortiGate 1 public IP |
| `fortigate1_private_ip` | FortiGate 1 private IP |
| `fortigate1_management_url` | FortiGate 1 HTTPS URL |
| `fortigate2_public_ip` | FortiGate 2 public IP |
| `fortigate2_private_ip` | FortiGate 2 private IP |
| `fortigate2_management_url` | FortiGate 2 HTTPS URL |
| `ubuntu1_private_ip` | Ubuntu VM 1 IP (10.0.1.10) |
| `ubuntu2_private_ip` | Ubuntu VM 2 IP (10.100.1.10) |
| `ssh_to_fortigate1` | SSH command for FortiGate 1 |
| `ssh_to_fortigate2` | SSH command for FortiGate 2 |
| `connectivity_test_command` | Ping command to test VPN |
| `bedrock_agent_id` | Bedrock Agent ID (Phase 2) |
| `bedrock_agent_alias_id` | Bedrock Agent alias ID (Phase 2) |
| `bedrock_terraform_bucket` | S3 bucket for Terraform files (Phase 2) |
| `bedrock_agent_usage` | Usage instructions (Phase 2) |
| `chat_ui_url` | Chat UI website URL (Phase 3) |
| `chat_ui_api_endpoint` | Chat UI API endpoint (Phase 3) |

```bash
# View all outputs
terraform output

# Get specific output
terraform output fortigate1_management_url
```

---

## Testing Infrastructure

### Automated Testing

An automated test script is provided to validate the infrastructure:

```bash
# Run all tests
make test

# Or run directly
./scripts/test-infrastructure.sh
```

**Tests Performed:**

| Test | Description |
|------|-------------|
| FortiGate HTTPS | Verifies web console is accessible on port 443 |
| FortiGate SSH | Verifies SSH is accessible on port 22 |
| VPN Ports | Checks IKE (UDP 500) and NAT-T (UDP 4500) ports |
| VPN Tunnel Status | Connects via SSH to verify tunnel is UP |
| Cross-VPC Ping | Pings Ubuntu VMs across the VPN tunnel |

**Example Output:**

```
FortiGate VPN Infrastructure Test Suite
========================================

Retrieving Terraform Outputs
  FortiGate 1 Public IP: 3.14.xxx.xxx
  FortiGate 2 Public IP: 3.15.xxx.xxx

Testing FortiGate Web Console Access
  Testing: FortiGate 1 HTTPS (port 443)... PASS
  Testing: FortiGate 2 HTTPS (port 443)... PASS

Testing VPN Tunnel Status
  Testing: VPN tunnel on FortiGate 1... PASS
    Info: Tunnel is UP

Test Summary
  Passed: 10
  Failed: 0

All tests passed!
```

### Manual Testing

#### 1. Verify VPN Tunnel Status

```bash
# SSH to FortiGate 1
ssh -i fortigate-demo-key.pem admin@$(terraform output -raw fortigate1_public_ip)

# Check VPN status
get vpn ipsec tunnel summary

# Expected output:
# 'vpn-to-vpc2' ...  up
```

#### 2. Test Cross-VPC Connectivity

To test ping between Ubuntu VMs, you need to access them through the FortiGate (since they're in private subnets).

**Option A: Test from FortiGate CLI**
```bash
# From FortiGate 1
execute ping 10.100.1.10
```

**Option B: SSH via FortiGate (ProxyJump)**
```bash
# Configure SSH config
cat >> ~/.ssh/config << EOF
Host fortigate1
  HostName $(terraform output -raw fortigate1_public_ip)
  User admin
  IdentityFile ~/Projects/terraform/fortigate-demo-key.pem

Host ubuntu1
  HostName 10.0.1.10
  User ubuntu
  IdentityFile ~/Projects/terraform/fortigate-demo-key.pem
  ProxyJump fortigate1
EOF

# SSH to Ubuntu 1
ssh ubuntu1

# Ping Ubuntu 2
ping 10.100.1.10
```

#### 3. Verify Routing Path

```bash
# From Ubuntu 1, trace the path to Ubuntu 2
traceroute 10.100.1.10

# Expected: traffic routes through FortiGate private interface
```

---

## Security Considerations

### Network Security

| Security Group | Ingress Rules |
|---------------|---------------|
| FortiGate Public | HTTPS (443), SSH (22), IKE (500/udp), NAT-T (4500/udp) |
| FortiGate Private | All traffic from local and remote private subnets |
| Ubuntu | SSH (22), ICMP, All from remote private subnet |

### Sensitive Data

Files excluded from version control (`.gitignore`):
- `terraform.tfvars` - Contains passwords
- `*.pem` - SSH private keys
- `*.tfstate*` - State files with sensitive data
- `.terraform/` - Provider binaries

### Recommendations

1. **Restrict `admin_cidr`** to your IP address
2. **Use strong passwords** for FortiGate admin and VPN PSK
3. **Enable S3 backend** for state file encryption
4. **Rotate credentials** after demo/presentation

---

## Makefile Commands

A `Makefile` is provided for convenient infrastructure management.

### Available Commands

#### Initialization
| Command | Description |
|---------|-------------|
| `make init` | Initialize Terraform and download providers |
| `make validate` | Validate configuration syntax |
| `make fmt` | Format Terraform files recursively |
| `make fmt-check` | Check formatting without changes |

#### Planning
| Command | Description |
|---------|-------------|
| `make plan` | Plan base infrastructure |
| `make plan-agent` | Plan with Bedrock Agent enabled |
| `make plan-full` | Plan full stack (agent + chat UI) |

#### Deployment
| Command | Description |
|---------|-------------|
| `make apply` | Apply saved plan (generates report) |
| `make apply-auto` | Apply without confirmation |
| `make apply-agent` | Deploy with Bedrock Agent (syncs files to S3) |
| `make apply-full` | Deploy full stack (builds UI, syncs files) |
| `make deploy` | Full pipeline: init → validate → plan → apply |
| `make deploy-agent` | Full pipeline with Bedrock Agent |
| `make deploy-full` | Full pipeline: infrastructure + agent + chat UI |

#### Destruction
| Command | Description |
|---------|-------------|
| `make destroy` | Destroy base infrastructure |
| `make destroy-agent` | Destroy with Bedrock Agent |
| `make destroy-full` | Destroy full stack |
| `make destroy-auto` | Destroy without confirmation |
| `make destroy-agent-auto` | Destroy agent without confirmation |
| `make destroy-full-auto` | Destroy full stack without confirmation |

#### Chat UI
| Command | Description |
|---------|-------------|
| `make build-ui` | Build React chat application |
| `make dev-ui` | Start local dev server (mock mode) |
| `make clean-ui` | Remove UI build artifacts |

#### Utilities
| Command | Description |
|---------|-------------|
| `make output` | Show current outputs |
| `make refresh` | Refresh state from actual infrastructure |
| `make state` | List resources in state |
| `make report` | Generate deployment report |
| `make sync-terraform` | Sync Terraform files to S3 for agent |
| `make test` | Run infrastructure tests |
| `make clean` | Remove plan file and provider cache |
| `make clean-all` | Remove all Terraform local files |
| `make help` | Show all available commands |

### Common Workflows

```bash
# Deploy everything (infrastructure + agent + chat UI)
make deploy-full

# Run infrastructure tests
make test

# Generate deployment report (IPs, URLs, credentials)
make report

# View chat UI locally (mock mode)
make dev-ui

# Make changes and redeploy
make plan-full
make apply

# Check what's deployed
make output
make state

# Tear down everything
make destroy-full

# Clean local files (keep state)
make clean
```

### Deployment Report

After any `apply` command, a deployment report is automatically generated with:
- All IP addresses (public and private)
- Management URLs
- SSH commands
- Credentials reference
- Chat UI URL (if enabled)
- Total resource count

The report is saved to `deployment-report.txt` and displayed in the terminal.

---

## Cleanup

To destroy all resources:

```bash
# Using Make (recommended)
make destroy

# Or using Terraform directly
terraform destroy
```

To remove specific resources:
```bash
terraform destroy -target=module.ubuntu1
```

---

## Phase 2: AI Documentation Agent

The project includes a complete AI agent built with Amazon Bedrock that can:

1. **Analyze Terraform code** and generate documentation
2. **Answer questions** about infrastructure in natural language
3. **Show deployed resources** with real-time AWS data (instance IPs, VPCs, states)
4. **Generate architecture diagrams** as Mermaid code for visualization
5. **Execute Terraform operations** (plan, apply, destroy)
6. **Check deployment status** and report infrastructure state
7. **Modify Terraform code** based on suggestions
8. **Run infrastructure tests** after deployment

### Architecture

```
┌───────────────────────────────────────────────────────────────────────────────────┐
│                              Amazon Bedrock Agent                                   │
│  ┌───────┐┌───────┐┌───────┐┌───────┐┌───────┐┌───────┐┌───────┐┌───────┐┌───────┐│
│  │Read   ││Analyze││Generate││Diagram││Deployed││TF Ops ││Status ││Modify ││Tests  ││
│  │Files  ││       ││Docs   ││       ││Resources│       ││       ││Code   ││       ││
│  └───┬───┘└───┬───┘└───┬───┘└───┬───┘└───┬───┘└───┬───┘└───┬───┘└───┬───┘└───┬───┘│
└──────┼────────┼────────┼────────┼────────┼────────┼────────┼────────┼────────┼─────┘
       │        │        │        │        │        │        │        │        │
       ▼        ▼        ▼        ▼        ▼        ▼        ▼        ▼        ▼
┌───────────────────────────────────────────────────────────────────────────────────┐
│                               9 Lambda Functions                                    │
└─────────────────────────────────────┬─────────────────────────────────────────────┘
                                      │
          ┌───────────────────────────┼───────────────────────────┐
          ▼                           ▼                           ▼
   ┌─────────────┐            ┌─────────────┐            ┌─────────────┐
   │  S3 Bucket  │            │  CodeBuild  │            │   AWS EC2   │
   │  Terraform  │            │  Terraform  │            │   (Live     │
   │    Files    │            │  Executor   │            │   Queries)  │
   └─────────────┘            └─────────────┘            └─────────────┘
```

### Deploy Phase 2

```bash
# Using Make (Recommended) - automatically syncs files to S3
make deploy-agent

# Or using Terraform directly
terraform apply -var="enable_bedrock_agent=true"
make sync-terraform  # Upload files to S3
```

### Terraform Files S3 Sync

The `make sync-terraform` command (run automatically with `apply-agent` and `apply-full`) uploads your Terraform files to S3 for the agent to analyze. It excludes sensitive files:

```bash
# Manual sync
make sync-terraform

# Files excluded from sync:
# - .terraform/*, *.tfstate*, *.pem, *.key
# - .env*, .secrets, deployment-report.txt
# - node_modules/, .git/, tfplan
```

### Using the Agent

```bash
# Get agent details
AGENT_ID=$(terraform output -raw bedrock_agent_id)
ALIAS_ID=$(terraform output -raw bedrock_agent_alias_id)

# Invoke the agent
aws bedrock-agent-runtime invoke-agent \
  --agent-id $AGENT_ID \
  --agent-alias-id $ALIAS_ID \
  --session-id my-session \
  --input-text "Analyze the Terraform files and explain what infrastructure they create"
```

### Example Prompts

| Prompt | What it does |
|--------|--------------|
| "Read and analyze all Terraform files" | Lists all resources, modules, variables |
| "What does the FortiGate module create?" | Explains FortiGate resources |
| "Show deployed resources" | Queries live AWS for instance IPs, VPCs, states |
| "What is deployed?" | Returns real-time infrastructure details |
| "Show architecture diagram" | Generates Mermaid diagram from Terraform |
| "Generate documentation" | Creates markdown documentation |
| "Run terraform plan" | Triggers CodeBuild to run plan |
| "Run connectivity tests" | Tests deployed infrastructure |
| "Add a description tag to the VPC" | Modifies Terraform code (dry run first) |

### Documentation

- [PHASE2_BEDROCK_AGENT.md](docs/PHASE2_BEDROCK_AGENT.md) - Full implementation details
- [PHASE2_IMPLEMENTATION_TASKS.md](docs/PHASE2_IMPLEMENTATION_TASKS.md) - Step-by-step task list

### Agent Capabilities

| Capability | Lambda Function | Description |
|------------|-----------------|-------------|
| Read Files | `terraform-docs-read-files` | Read .tf files from S3 |
| Analyze | `terraform-docs-analyze` | Parse and extract resources |
| Generate Docs | `terraform-docs-generate` | Generate markdown documentation |
| Generate Diagram | `terraform-docs-diagram` | Create Mermaid architecture diagrams |
| Get Deployed Resources | `terraform-docs-deployed` | Query live AWS for deployed infrastructure |
| Terraform Ops | `terraform-docs-operations` | Plan/apply/destroy via CodeBuild |
| Get Status | `terraform-docs-status` | Check build/infrastructure state |
| Modify Code | `terraform-docs-modify-code` | Update Terraform files |
| Run Tests | `terraform-docs-run-tests` | Validate deployed infrastructure |

---

## Phase 3: Chat UI

A web-based chat interface for interacting with the Bedrock Agent.

### Architecture

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Browser   │────►│ CloudFront  │────►│  S3 Bucket  │     │             │
│  (React UI) │     │    CDN      │     │ Static Site │     │   Bedrock   │
└─────────────┘     └─────────────┘     └─────────────┘     │    Agent    │
       │                                                     │             │
       │            ┌─────────────┐     ┌─────────────┐     └─────────────┘
       └───────────►│ API Gateway │────►│   Lambda    │────────────┘
                    │  HTTP API   │     │   Handler   │
                    └─────────────┘     └─────────────┘
```

### Deploy Chat UI

```bash
# Deploy everything (infrastructure + agent + chat UI)
make deploy-full

# Or step by step
make build-ui                    # Build React app
terraform apply -var="enable_bedrock_agent=true" -var="enable_chat_ui=true"
```

### Local Development

Run the chat UI locally in mock mode (no backend required):

```bash
make dev-ui
# Opens at http://localhost:5173
```

### Features

- Real-time chat with Bedrock Agent
- Markdown rendering for responses
- Code syntax highlighting
- Session persistence
- Loading states and error handling
- Responsive design

### Chat UI Outputs

| Output | Description |
|--------|-------------|
| `chat_ui_url` | CloudFront URL for the chat interface |
| `chat_ui_api_endpoint` | API Gateway endpoint |
| `chat_ui_bucket` | S3 bucket for static files |
| `chat_ui_cloudfront_id` | CloudFront distribution ID |

---

## Troubleshooting

### FortiGate AMI Not Found

```
Error: Your query returned no results
```

**Solution:** Subscribe to FortiGate PAYG in AWS Marketplace.

### VPN Tunnel Not Up

1. Check security groups allow UDP 500/4500
2. Verify EIPs are correctly associated
3. Check FortiGate logs: `diagnose vpn ike log filter name vpn-to-vpc2`

### Cannot SSH to Ubuntu VMs

Ubuntu VMs are in private subnets. Use SSH ProxyJump through FortiGate or create a bastion host.

### Terraform State Lock

```
Error: Error acquiring the state lock
```

**Solution:**
```bash
terraform force-unlock LOCK_ID
```

---

## Resources

- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [FortiGate AWS Deployment Guide](https://docs.fortinet.com/document/fortigate-public-cloud/7.4.0/aws-administration-guide)
- [Amazon Bedrock Developer Guide](https://docs.aws.amazon.com/bedrock/latest/userguide/)
- [FortiOS CLI Reference](https://docs.fortinet.com/document/fortigate/7.4.0/cli-reference)

---

## License

This project is for demonstration purposes as part of a technical evaluation.

## Author

Andrei Pop (popand@gmail.com)
