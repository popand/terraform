# FortiGate VPN Infrastructure with AI-Powered Automation

## Technical Presentation

**Author:** Andrei Pop
**Date:** January 2025
**AWS Account:** 684039303210 (us-east-2)

---

## Executive Summary

This project demonstrates enterprise-grade Infrastructure as Code (IaC) practices combined with AI-powered automation using Amazon Bedrock. The solution deploys a multi-VPC network with FortiGate firewalls connected via IPSec VPN, all managed through modular Terraform code and an intelligent AI agent.

### Key Achievements
- **80 AWS resources** deployed automatically
- **4 reusable Terraform modules** with clean separation of concerns
- **7 Lambda functions** powering an AI agent for infrastructure management
- **End-to-end VPN connectivity** verified between isolated VPCs

---

## Architecture Overview

```
                              ┌─────────────────────────────────────────────────────────┐
                              │                    AWS Cloud (us-east-2)                 │
                              └─────────────────────────────────────────────────────────┘
                                                        │
                    ┌───────────────────────────────────┴───────────────────────────────────┐
                    │                                                                       │
        ┌───────────┴───────────┐                                           ┌───────────────┴───────────┐
        │      VPC 1            │                                           │         VPC 2             │
        │   10.0.0.0/16         │                                           │     10.100.0.0/16         │
        │                       │                                           │                           │
        │  ┌─────────────────┐  │         IPSec VPN Tunnel                  │  ┌─────────────────┐      │
        │  │ Public Subnet   │  │         (AES256-SHA256)                   │  │ Public Subnet   │      │
        │  │  10.0.0.0/24    │  │  ════════════════════════════════════════ │  │ 10.100.0.0/24   │      │
        │  │                 │  │                                           │  │                 │      │
        │  │ ┌─────────────┐ │  │                                           │  │ ┌─────────────┐ │      │
        │  │ │ FortiGate-1 │ │  │                                           │  │ │ FortiGate-2 │ │      │
        │  │ │ 3.19.233.255│ │◄─┼───────────────────────────────────────────┼──►│3.135.21.14  │ │      │
        │  │ └──────┬──────┘ │  │                                           │  │ └──────┬──────┘ │      │
        │  └────────┼────────┘  │                                           │  └────────┼────────┘      │
        │           │           │                                           │           │               │
        │  ┌────────┼────────┐  │                                           │  ┌────────┼────────┐      │
        │  │ Private Subnet  │  │                                           │  │ Private Subnet  │      │
        │  │  10.0.1.0/24    │  │                                           │  │ 10.100.1.0/24   │      │
        │  │        │        │  │                                           │  │        │        │      │
        │  │ ┌──────┴──────┐ │  │                                           │  │ ┌──────┴──────┐ │      │
        │  │ │  Ubuntu-1   │ │  │                                           │  │ │  Ubuntu-2   │ │      │
        │  │ │  10.0.1.10  │ │◄─┼───────────── Secure Traffic ──────────────┼──►│ 10.100.1.10 │ │      │
        │  │ └─────────────┘ │  │                                           │  │ └─────────────┘ │      │
        │  └─────────────────┘  │                                           │  └─────────────────┘      │
        └───────────────────────┘                                           └───────────────────────────┘
```

---

## Terraform Module Architecture

### Module Hierarchy

```
terraform/
├── main.tf                 # Root orchestration
├── variables.tf            # Input variables
├── outputs.tf              # Output values
│
└── modules/
    ├── vpc/                # Network foundation
    │   ├── main.tf         # VPC, subnets, IGW, route tables
    │   ├── variables.tf    # CIDR blocks, AZ config
    │   └── outputs.tf      # VPC ID, subnet IDs, route table IDs
    │
    ├── fortigate/          # Security appliance
    │   ├── main.tf         # EC2, ENIs, security groups
    │   ├── variables.tf    # Instance config, VPN params
    │   ├── outputs.tf      # IPs, ENI IDs
    │   └── templates/
    │       └── fortigate_config.tpl  # Bootstrap config
    │
    ├── ubuntu/             # Workload VMs
    │   ├── main.tf         # EC2, security groups
    │   ├── variables.tf    # Instance config
    │   └── outputs.tf      # Private IPs
    │
    └── bedrock-agent/      # AI automation (Phase 2)
        ├── main.tf         # S3, Bedrock Agent
        ├── iam.tf          # IAM roles & policies
        ├── lambda.tf       # 7 Lambda functions
        ├── codebuild.tf    # Terraform executor
        ├── openapi-schema.yaml
        └── lambda-code/    # Python handlers
```

### Module Reusability

Each module is designed for reuse:

| Module | Instances | Purpose |
|--------|-----------|---------|
| `vpc` | 2 | Creates identical VPC structures |
| `fortigate` | 2 | Deploys FortiGate with different VPN peers |
| `ubuntu` | 2 | Places workloads in each VPC |
| `bedrock-agent` | 1 | Optional AI automation layer |

---

## How Terraform Orchestrates the Infrastructure

### 1. Dependency Resolution

Terraform automatically determines the deployment order:

```
1. VPCs (vpc1, vpc2)           → Foundation
2. Elastic IPs                  → Required for VPN peer addressing
3. FortiGates                   → Reference EIPs for VPN config
4. Ubuntu VMs                   → Deployed in private subnets
5. Route Tables                 → Point traffic to FortiGate ENIs
6. Bedrock Agent (optional)     → References Phase 1 outputs
```

### 2. Cross-Module References

```hcl
# Root main.tf - Modules reference each other
module "fortigate1" {
  source = "./modules/fortigate"

  vpc_id            = module.vpc1.vpc_id           # From VPC module
  public_subnet_id  = module.vpc1.public_subnet_id
  vpn_peer_ip       = aws_eip.fortigate2.public_ip # From EIP resource
}

# Routes reference FortiGate ENI
resource "aws_route" "vpc1_to_vpc2" {
  route_table_id         = module.vpc1.private_route_table_id
  destination_cidr_block = var.vpc2_private_subnet_cidr
  network_interface_id   = module.fortigate1.private_eni_id
}
```

### 3. FortiGate Bootstrap Configuration

The FortiGate module uses a template to generate day-0 configuration:

```hcl
# modules/fortigate/main.tf
user_data = base64encode(templatefile("${path.module}/templates/fortigate_config.tpl", {
  hostname        = var.name
  admin_password  = var.admin_password
  private_ip      = local.private_ip
  private_netmask = "255.255.255.0"
  vpn_name        = var.vpn_name
  vpn_peer_ip     = var.vpn_peer_ip
  vpn_psk         = var.vpn_psk
  local_subnet    = var.private_subnet_cidr
  remote_subnet   = var.remote_private_subnet_cidr
}))
```

This automatically configures:
- System hostname and admin credentials
- Interface IP addresses
- IPSec Phase 1 & Phase 2 parameters
- Firewall policies for VPN traffic
- Static routes for remote subnets

---

## VPN Configuration Deep Dive

### IPSec Parameters

| Parameter | Value |
|-----------|-------|
| IKE Version | 1 |
| Phase 1 Encryption | AES-256 |
| Phase 1 Hash | SHA-256 |
| Phase 2 Encryption | AES-256 |
| Phase 2 Hash | SHA-256 |
| Authentication | Pre-Shared Key |
| NAT Traversal | Enabled (UDP 4500) |

### Traffic Selectors

```
VPC1 Private Subnet: 10.0.1.0/24   ←→   VPC2 Private Subnet: 10.100.1.0/24
```

### Firewall Policies (Auto-Generated)

```
Policy 1: vpn-outbound
  Source: port2 (private) → Destination: vpn-tunnel
  Match: local-subnet → remote-subnet
  Action: ACCEPT

Policy 2: vpn-inbound
  Source: vpn-tunnel → Destination: port2 (private)
  Match: remote-subnet → local-subnet
  Action: ACCEPT

Policy 3: outbound-nat
  Source: port2 → Destination: port1 (public)
  Action: ACCEPT + NAT (for internet access)
```

---

## AI-Powered Infrastructure Agent (Phase 2)

### Amazon Bedrock Agent Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        Amazon Bedrock Agent                              │
│                     (Claude 3 Sonnet Foundation Model)                   │
│                                                                          │
│   "Analyze the Terraform files and explain the infrastructure"          │
│                                    │                                     │
│                                    ▼                                     │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │                      Action Groups                               │   │
│   │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐   │   │
│   │  │  Read   │ │ Analyze │ │Generate │ │  TF Ops │ │  Status │   │   │
│   │  │  Files  │ │         │ │  Docs   │ │         │ │         │   │   │
│   │  └────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘   │   │
│   │       │           │           │           │           │         │   │
│   │  ┌────┴────┐ ┌────┴────┐ ┌────┴────┐ ┌────┴────┐ ┌────┴────┐   │   │
│   │  │ Modify  │ │  Run    │ │         │ │         │ │         │   │   │
│   │  │  Code   │ │  Tests  │ │         │ │         │ │         │   │   │
│   │  └────┬────┘ └────┬────┘ └─────────┘ └─────────┘ └─────────┘   │   │
│   └───────┼───────────┼─────────────────────────────────────────────┘   │
└───────────┼───────────┼─────────────────────────────────────────────────┘
            │           │
            ▼           ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                        7 Lambda Functions                                │
│                                                                          │
│  read_files.py    - List and read .tf files from S3                     │
│  analyze.py       - Parse HCL and extract resources/variables           │
│  generate.py      - Create markdown documentation                        │
│  terraform_ops.py - Trigger CodeBuild for plan/apply/destroy            │
│  get_status.py    - Check build status and infrastructure state         │
│  modify_code.py   - Update Terraform files with dry-run support         │
│  run_tests.py     - Execute infrastructure validation tests             │
│                                                                          │
└──────────────────────────────────┬──────────────────────────────────────┘
                                   │
       ┌───────────────────────────┼───────────────────────────────────┐
       │                           │                                   │
       ▼                           ▼                                   ▼
┌─────────────┐            ┌─────────────┐                    ┌─────────────┐
│  S3 Bucket  │            │  CodeBuild  │                    │   Phase 1   │
│             │            │             │                    │   Infra     │
│ *.tf files  │            │  Terraform  │                    │             │
│ tfstate     │            │  Executor   │                    │ FortiGates  │
│ plan.json   │            │             │                    │ Ubuntu VMs  │
│ docs/       │            │ plan/apply/ │                    │ VPN Tunnel  │
│             │            │ destroy     │                    │             │
└─────────────┘            └─────────────┘                    └─────────────┘
```

### Agent Capabilities

| Capability | Lambda | Description |
|------------|--------|-------------|
| **Read Files** | `read_files.py` | List and retrieve .tf files from S3 |
| **Analyze** | `analyze.py` | Parse Terraform to extract resources, variables, outputs |
| **Generate Docs** | `generate.py` | Create markdown documentation and save to S3 |
| **Terraform Ops** | `terraform_ops.py` | Execute plan/apply/destroy via CodeBuild |
| **Get Status** | `get_status.py` | Check build status, view outputs |
| **Modify Code** | `modify_code.py` | Update Terraform files (with dry-run) |
| **Run Tests** | `run_tests.py` | Validate deployed infrastructure |

### Example Conversations

```
User: "Read the Terraform files and explain the infrastructure"

Agent: Let me read the files from S3...
       [Calls readTerraformFiles Lambda]

       I found 12 Terraform files across 4 modules. Here's what this
       infrastructure creates:

       1. Two VPCs (10.0.0.0/16 and 10.100.0.0/16)
       2. Two FortiGate firewalls connected via IPSec VPN
       3. Two Ubuntu VMs in private subnets
       4. Route tables directing cross-VPC traffic through FortiGates

       The VPN uses AES-256 encryption with SHA-256 hashing...
```

```
User: "Run terraform plan and show me what would change"

Agent: I'll trigger a Terraform plan operation...
       [Calls executeTerraformOperation Lambda]

       Build started: terraform-docs-executor:build-123

       [Calls getTerraformStatus Lambda]

       Plan complete. No changes detected - infrastructure is up to date.
```

```
User: "Run connectivity tests on the infrastructure"

Agent: Running infrastructure validation tests...
       [Calls runInfrastructureTests Lambda]

       Test Results:
       ✓ FortiGate 1 HTTPS accessible
       ✓ FortiGate 2 HTTPS accessible
       ✓ VPN tunnel status: UP
       ✓ Cross-VPC ping: 0% packet loss, 0.5ms latency

       All 4 tests passed.
```

---

## CodeBuild Terraform Executor

The agent uses CodeBuild to safely execute Terraform operations:

```yaml
phases:
  install:
    commands:
      - curl -LO terraform_${VERSION}_linux_amd64.zip
      - unzip && mv terraform /usr/local/bin/

  pre_build:
    commands:
      - aws s3 sync s3://$BUCKET/terraform/ ./terraform/
      - cd terraform && terraform init

  build:
    commands:
      - case "$TF_OPERATION" in
          "plan")   terraform plan -out=tfplan ;;
          "apply")  terraform apply -auto-approve ;;
          "destroy") terraform destroy -auto-approve ;;
        esac

  post_build:
    commands:
      - aws s3 cp plan.json s3://$STATE_BUCKET/
      - aws s3 cp outputs.json s3://$STATE_BUCKET/
```

### Safety Controls

- **Auto-approve required** for apply/destroy operations
- **Dry-run support** for code modifications
- **Audit trail** via CloudWatch logs
- **IAM least privilege** - CodeBuild role only has required permissions

---

## Deployment Summary

### Resources Created (80 total)

| Category | Count | Examples |
|----------|-------|----------|
| Networking | 18 | VPCs, subnets, route tables, IGWs |
| Compute | 4 | FortiGate instances, Ubuntu VMs |
| Security | 8 | Security groups, IAM roles |
| Storage | 2 | S3 buckets for Terraform files |
| Serverless | 7 | Lambda functions |
| AI/ML | 3 | Bedrock agent, action groups, alias |
| Other | 38 | ENIs, EIPs, CloudWatch logs, etc. |

### Deployment Commands

```bash
# Initialize Terraform
terraform init

# Deploy Phase 1 only (infrastructure)
terraform apply

# Deploy Phase 1 + Phase 2 (with AI agent)
terraform apply -var="enable_bedrock_agent=true"

# Destroy everything
terraform destroy -var="enable_bedrock_agent=true"
```

---

## Test Results

### VPN Connectivity Test (Verified)

| Test | Status | Details |
|------|--------|---------|
| FortiGate 1 HTTPS | ✓ PASS | https://3.19.233.255 |
| FortiGate 2 HTTPS | ✓ PASS | https://3.135.21.14 |
| FortiGate 1 SSH | ✓ PASS | Port 22 open |
| FortiGate 2 SSH | ✓ PASS | Port 22 open |
| VPN IKE (Phase 1) | ✓ PASS | Established |
| VPN IPsec (Phase 2) | ✓ PASS | Selectors 1/1 UP |
| FG1 → Ubuntu1 | ✓ PASS | 0% loss |
| FG2 → Ubuntu2 | ✓ PASS | 0% loss |
| FG1 → Ubuntu2 (VPN) | ✓ PASS | 0% loss, 0.5ms |
| FG2 → Ubuntu1 (VPN) | ✓ PASS | 0% loss, 0.5ms |

---

## Key Takeaways

### Terraform Best Practices Demonstrated

1. **Modular Design** - Reusable modules with clear interfaces
2. **Variable Abstraction** - Environment-agnostic configuration
3. **Output Chaining** - Modules reference each other cleanly
4. **Template Files** - Complex configurations generated dynamically
5. **Conditional Resources** - Phase 2 deployed only when enabled

### AI Agent Benefits

1. **Natural Language Interface** - Ask questions about infrastructure
2. **Automated Operations** - Execute Terraform without CLI access
3. **Documentation Generation** - Auto-generate and update docs
4. **Testing Integration** - Validate infrastructure automatically
5. **Audit Trail** - All operations logged in CloudWatch

---

## Quick Reference

### Connection Info

```bash
# FortiGate 1
ssh -i fortigate-demo-key.pem admin@3.19.233.255
https://3.19.233.255

# FortiGate 2
ssh -i fortigate-demo-key.pem admin@3.135.21.14
https://3.135.21.14

# Bedrock Agent
Agent ID: 4M1CH03HVV
Alias ID: VRCQE3YRBC
```

### Useful Commands

```bash
# View all outputs
terraform output

# Test VPN from FortiGate CLI
execute ping-options source 10.0.1.84
execute ping 10.100.1.10

# Invoke Bedrock Agent
aws bedrock-agent-runtime invoke-agent \
  --agent-id 4M1CH03HVV \
  --agent-alias-id VRCQE3YRBC \
  --session-id demo \
  --input-text "Analyze the infrastructure"
```

---

## Questions?

**Repository:** `/Users/andreipop/Projects/terraform`
**Author:** Andrei Pop (andrei.pop@alethiaintel.com)
**AWS Account:** 684039303210
