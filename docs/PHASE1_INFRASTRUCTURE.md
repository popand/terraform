# Phase 1: Terraform Infrastructure Documentation

## Overview

This document describes the Terraform infrastructure that deploys a multi-VPC architecture on AWS with FortiGate Next-Generation Firewalls (NGFW) connected via an IPSec VPN tunnel. The infrastructure enables secure communication between workloads in separate VPCs.

## Architecture Summary

```
┌─────────────────────────────────────┐     ┌─────────────────────────────────────┐
│           VPC 1 (10.0.0.0/16)       │     │         VPC 2 (10.100.0.0/16)       │
│                                     │     │                                     │
│  ┌─────────────────────────────┐    │     │    ┌─────────────────────────────┐  │
│  │  Public Subnet (10.0.0.0/24)│    │     │    │Public Subnet (10.100.0.0/24)│  │
│  │                             │    │     │    │                             │  │
│  │     ┌─────────────────┐     │    │     │    │     ┌─────────────────┐     │  │
│  │     │  FortiGate-1    │     │    │     │    │     │  FortiGate-2    │     │  │
│  │     │  (Public ENI)   │◄────┼────┼─────┼────┼────►│  (Public ENI)   │     │  │
│  │     └────────┬────────┘     │    │ VPN │    │     └────────┬────────┘     │  │
│  └──────────────┼──────────────┘    │IPSec│    └──────────────┼──────────────┘  │
│                 │                   │Tunnel│                  │                  │
│  ┌──────────────┼──────────────┐    │     │    ┌──────────────┼──────────────┐  │
│  │  Private Subnet (10.0.1.0/24)   │     │    │Private Subnet (10.100.1.0/24)│  │
│  │              │              │    │     │    │              │              │  │
│  │     ┌────────┴────────┐     │    │     │    │     ┌────────┴────────┐     │  │
│  │     │  FortiGate-1    │     │    │     │    │     │  FortiGate-2    │     │  │
│  │     │  (Private ENI)  │     │    │     │    │     │  (Private ENI)  │     │  │
│  │     └─────────────────┘     │    │     │    │     └─────────────────┘     │  │
│  │                             │    │     │    │                             │  │
│  │     ┌─────────────────┐     │    │     │    │     ┌─────────────────┐     │  │
│  │     │   Ubuntu-VM-1   │     │    │     │    │     │   Ubuntu-VM-2   │     │  │
│  │     │   10.0.1.10     │     │    │     │    │     │   10.100.1.10   │     │  │
│  │     └─────────────────┘     │    │     │    │     └─────────────────┘     │  │
│  └─────────────────────────────┘    │     │    └─────────────────────────────┘  │
└─────────────────────────────────────┘     └─────────────────────────────────────┘
```

## Project Structure

```
terraform/
├── main.tf                              # Root module - orchestrates all child modules
├── variables.tf                         # Input variables for the root module
├── outputs.tf                           # Output values exposed after deployment
├── providers.tf                         # AWS provider configuration
├── terraform.tfvars                     # Variable values (contains sensitive data)
├── terraform.tfvars.example             # Example configuration template
├── fortigate-demo-key.pem               # SSH private key for EC2 access
├── .gitignore                           # Excludes sensitive files from version control
│
└── modules/
    ├── vpc/                             # VPC module (used twice: vpc1, vpc2)
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    │
    ├── fortigate/                       # FortiGate module (used twice: fortigate1, fortigate2)
    │   ├── main.tf
    │   ├── variables.tf
    │   ├── outputs.tf
    │   └── templates/
    │       └── fortigate_config.tpl     # FortiGate bootstrap configuration
    │
    └── ubuntu/                          # Ubuntu module (used twice: ubuntu1, ubuntu2)
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

---

## Module Documentation

### 1. VPC Module (`modules/vpc/`)

**Purpose:** Creates a complete VPC with public and private subnets, internet gateway, and route tables.

**Resources Created:**
| Resource | Description |
|----------|-------------|
| `aws_vpc` | Virtual Private Cloud with DNS support enabled |
| `aws_internet_gateway` | Enables internet access for public subnet |
| `aws_subnet.public` | Public subnet with auto-assign public IP |
| `aws_subnet.private` | Private subnet for internal workloads |
| `aws_route_table.public` | Routes 0.0.0.0/0 to Internet Gateway |
| `aws_route_table.private` | Private route table (routes added by root module) |
| `aws_route_table_association` | Associates subnets with route tables |

**Input Variables:**
| Variable | Type | Description |
|----------|------|-------------|
| `name` | string | Name prefix for all resources |
| `vpc_cidr` | string | CIDR block for the VPC (e.g., "10.0.0.0/16") |
| `public_subnet_cidr` | string | CIDR block for public subnet |
| `private_subnet_cidr` | string | CIDR block for private subnet |
| `availability_zone` | string | AZ for subnet placement |

**Outputs:**
| Output | Description |
|--------|-------------|
| `vpc_id` | ID of the created VPC |
| `vpc_cidr` | CIDR block of the VPC |
| `public_subnet_id` | ID of the public subnet |
| `private_subnet_id` | ID of the private subnet |
| `public_subnet_cidr` | CIDR of public subnet |
| `private_subnet_cidr` | CIDR of private subnet |
| `internet_gateway_id` | ID of the Internet Gateway |
| `private_route_table_id` | ID of private route table |

---

### 2. FortiGate Module (`modules/fortigate/`)

**Purpose:** Deploys a FortiGate Next-Generation Firewall VM with dual network interfaces, security groups, and automated VPN configuration.

**Resources Created:**
| Resource | Description |
|----------|-------------|
| `data.aws_ami.fortigate` | Looks up latest FortiGate PAYG AMI |
| `aws_security_group.public` | SG for public interface (HTTPS, SSH, IKE, NAT-T) |
| `aws_security_group.private` | SG for private interface (all traffic from subnets) |
| `aws_network_interface.public` | ENI in public subnet (source_dest_check=false) |
| `aws_network_interface.private` | ENI in private subnet (source_dest_check=false) |
| `aws_eip_association` | Associates pre-created EIP to public ENI |
| `aws_instance` | FortiGate EC2 instance with bootstrap config |

**Input Variables:**
| Variable | Type | Description |
|----------|------|-------------|
| `name` | string | Name for the FortiGate instance |
| `instance_type` | string | EC2 instance type (default: t3.small) |
| `key_name` | string | SSH key pair name |
| `vpc_id` | string | VPC ID for security groups |
| `public_subnet_id` | string | Subnet for public interface |
| `private_subnet_id` | string | Subnet for private interface |
| `public_subnet_cidr` | string | CIDR of public subnet |
| `private_subnet_cidr` | string | CIDR of private subnet |
| `admin_cidr` | string | CIDR allowed for management access |
| `remote_private_subnet_cidr` | string | Remote VPC private subnet CIDR |
| `admin_password` | string | FortiGate admin password (sensitive) |
| `vpn_psk` | string | IPSec pre-shared key (sensitive) |
| `vpn_peer_ip` | string | Public IP of VPN peer FortiGate |
| `vpn_name` | string | Name for VPN tunnel interface |
| `eip_allocation_id` | string | Elastic IP allocation ID |
| `eip_public_ip` | string | Elastic IP public address |

**Outputs:**
| Output | Description |
|--------|-------------|
| `instance_id` | FortiGate EC2 instance ID |
| `public_ip` | Public IP address |
| `private_ip` | Private interface IP |
| `private_eni_id` | Private ENI ID (used for routing) |
| `management_url` | HTTPS URL for management console |
| `ssh_command` | SSH command to connect |

**Bootstrap Configuration (`fortigate_config.tpl`):**

The FortiGate is configured at boot time using user_data with the following:

1. **System Settings:**
   - Sets hostname
   - Configures admin password
   - Sets HTTPS management port to 443

2. **Network Interfaces:**
   - `port1` (public): DHCP mode, allows HTTPS/SSH/ping
   - `port2` (private): Static IP, allows ping

3. **IPSec VPN Phase 1:**
   - Interface-based VPN
   - AES256-SHA256 encryption
   - Pre-shared key authentication
   - Remote gateway set to peer FortiGate public IP

4. **IPSec VPN Phase 2:**
   - Policy-based selectors
   - Source: local private subnet
   - Destination: remote private subnet

5. **Firewall Policies:**
   - Policy 1: Allow outbound VPN traffic (port2 → VPN tunnel)
   - Policy 2: Allow inbound VPN traffic (VPN tunnel → port2)
   - Policy 3: NAT for internet access (port2 → port1)

6. **Static Routes:**
   - Remote private subnet via VPN tunnel interface

---

### 3. Ubuntu Module (`modules/ubuntu/`)

**Purpose:** Deploys an Ubuntu 22.04 LTS instance for testing connectivity.

**Resources Created:**
| Resource | Description |
|----------|-------------|
| `data.aws_ami.ubuntu` | Looks up latest Ubuntu 22.04 AMI |
| `aws_security_group` | SG allowing SSH, ICMP, and remote subnet traffic |
| `aws_instance` | Ubuntu EC2 instance |

**Input Variables:**
| Variable | Type | Description |
|----------|------|-------------|
| `name` | string | Instance name |
| `instance_type` | string | EC2 instance type (default: t3.micro) |
| `key_name` | string | SSH key pair name |
| `vpc_id` | string | VPC ID for security group |
| `subnet_id` | string | Subnet ID for placement |
| `private_ip` | string | Static private IP address |
| `admin_cidr` | string | CIDR allowed for SSH |
| `remote_subnet_cidr` | string | Remote subnet CIDR for SG rules |

**Outputs:**
| Output | Description |
|--------|-------------|
| `instance_id` | Ubuntu EC2 instance ID |
| `private_ip` | Private IP address |

**User Data Script:**
- Sets hostname
- Installs traceroute and net-tools packages

---

## Root Module (`main.tf`)

The root module orchestrates all child modules and handles cross-module dependencies.

### Module Instantiation:

```hcl
# VPC Modules (2 instances)
module "vpc1" { ... }  # 10.0.0.0/16
module "vpc2" { ... }  # 10.100.0.0/16

# Elastic IPs (created before FortiGate modules to resolve circular dependency)
resource "aws_eip" "fortigate1" { ... }
resource "aws_eip" "fortigate2" { ... }

# FortiGate Modules (2 instances)
module "fortigate1" { ... }  # VPN peer: fortigate2
module "fortigate2" { ... }  # VPN peer: fortigate1

# Ubuntu Modules (2 instances)
module "ubuntu1" { ... }  # 10.0.1.10
module "ubuntu2" { ... }  # 10.100.1.10

# Route Table Entries (added after FortiGate ENIs exist)
resource "aws_route" "vpc1_to_vpc2" { ... }
resource "aws_route" "vpc1_default" { ... }
resource "aws_route" "vpc2_to_vpc1" { ... }
resource "aws_route" "vpc2_default" { ... }
```

### Dependency Resolution:

The EIPs are created at the root level (not in modules) to solve the circular dependency problem:
- FortiGate-1 needs FortiGate-2's public IP for VPN configuration
- FortiGate-2 needs FortiGate-1's public IP for VPN configuration

By creating EIPs first, both public IPs are known before either FortiGate instance is created.

---

## Network Configuration Details

### IP Addressing:

| Component | VPC 1 | VPC 2 |
|-----------|-------|-------|
| VPC CIDR | 10.0.0.0/16 | 10.100.0.0/16 |
| Public Subnet | 10.0.0.0/24 | 10.100.0.0/24 |
| Private Subnet | 10.0.1.0/24 | 10.100.1.0/24 |
| FortiGate Private IP | DHCP assigned | DHCP assigned |
| Ubuntu VM IP | 10.0.1.10 | 10.100.1.10 |

### Security Group Rules:

**FortiGate Public Interface:**
| Type | Port | Protocol | Source | Purpose |
|------|------|----------|--------|---------|
| Ingress | 443 | TCP | admin_cidr | HTTPS management |
| Ingress | 22 | TCP | admin_cidr | SSH management |
| Ingress | 500 | UDP | 0.0.0.0/0 | IKE (IPSec) |
| Ingress | 4500 | UDP | 0.0.0.0/0 | NAT-T (IPSec) |
| Egress | All | All | 0.0.0.0/0 | Outbound traffic |

**FortiGate Private Interface:**
| Type | Port | Protocol | Source | Purpose |
|------|------|----------|--------|---------|
| Ingress | All | All | local_private_cidr | Local subnet traffic |
| Ingress | All | All | remote_private_cidr | VPN traffic |
| Egress | All | All | 0.0.0.0/0 | Outbound traffic |

**Ubuntu Instance:**
| Type | Port | Protocol | Source | Purpose |
|------|------|----------|--------|---------|
| Ingress | 22 | TCP | admin_cidr | SSH access |
| Ingress | ICMP | ICMP | 0.0.0.0/0 | Ping tests |
| Ingress | All | All | remote_private_cidr | Cross-VPC traffic |
| Egress | All | All | 0.0.0.0/0 | Outbound traffic |

### Routing:

**Public Subnet Route Table:**
| Destination | Target |
|-------------|--------|
| 0.0.0.0/0 | Internet Gateway |

**Private Subnet Route Table:**
| Destination | Target |
|-------------|--------|
| 0.0.0.0/0 | FortiGate Private ENI |
| remote_private_cidr | FortiGate Private ENI |

---

## VPN Configuration

### IPSec Parameters:

| Parameter | Value |
|-----------|-------|
| Phase 1 Proposal | AES256-SHA256 |
| Phase 2 Proposal | AES256-SHA256 |
| Authentication | Pre-Shared Key |
| IKE Version | IKEv1 (default) |
| Mode | Interface-based VPN |

### Traffic Flow:

1. Ubuntu-VM-1 (10.0.1.10) sends packet to Ubuntu-VM-2 (10.100.1.10)
2. Packet hits private route table, forwarded to FortiGate-1 private ENI
3. FortiGate-1 matches firewall policy "vpn-outbound"
4. Packet encrypted and sent through IPSec tunnel to FortiGate-2
5. FortiGate-2 decrypts packet, matches policy "vpn-inbound"
6. Packet forwarded to Ubuntu-VM-2 via private interface

---

## Deployment Steps

### Prerequisites:
1. AWS CLI configured with appropriate credentials
2. Terraform >= 1.0 installed
3. FortiGate PAYG subscription in AWS Marketplace

### Commands:

```bash
# Initialize Terraform and download providers/modules
terraform init

# Validate configuration syntax
terraform validate

# Preview changes
terraform plan -out=tfplan

# Apply changes (creates infrastructure)
terraform apply tfplan

# View outputs after deployment
terraform output
```

### Post-Deployment:

1. Wait 3-5 minutes for FortiGate instances to boot and apply configuration
2. Access FortiGate management via HTTPS URL from outputs
3. Login with username: `admin`, password: from terraform.tfvars
4. Verify VPN tunnel status: `get vpn ipsec tunnel summary`
5. Test connectivity by pinging between Ubuntu VMs

---

## Resource Count

| Resource Type | Count |
|---------------|-------|
| VPCs | 2 |
| Subnets | 4 |
| Internet Gateways | 2 |
| Route Tables | 4 |
| Route Table Associations | 4 |
| Routes | 4 |
| Security Groups | 6 |
| Network Interfaces | 4 |
| Elastic IPs | 2 |
| EIP Associations | 2 |
| EC2 Instances (FortiGate) | 2 |
| EC2 Instances (Ubuntu) | 2 |
| **Total** | **38** |

---

## Configuration Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `aws_region` | us-east-2 | AWS region |
| `key_name` | - | SSH key pair name |
| `admin_cidr` | 0.0.0.0/0 | Management access CIDR |
| `vpc1_cidr` | 10.0.0.0/16 | VPC 1 CIDR |
| `vpc1_public_subnet_cidr` | 10.0.0.0/24 | VPC 1 public subnet |
| `vpc1_private_subnet_cidr` | 10.0.1.0/24 | VPC 1 private subnet |
| `vpc2_cidr` | 10.100.0.0/16 | VPC 2 CIDR |
| `vpc2_public_subnet_cidr` | 10.100.0.0/24 | VPC 2 public subnet |
| `vpc2_private_subnet_cidr` | 10.100.1.0/24 | VPC 2 private subnet |
| `fortigate_instance_type` | t3.small | FortiGate instance size |
| `fortigate_admin_password` | - | FortiGate admin password |
| `ubuntu_instance_type` | t3.micro | Ubuntu instance size |
| `vpn_psk` | - | IPSec pre-shared key |

---

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

This will remove all 38 resources created by this configuration.

---

## Post-Migration Recommendations

After migrating to Terraform, the following improvements are recommended:

### Priority 1: Security

| Issue | Action |
|-------|--------|
| Verify credentials not in git history | Run `git log --all --full-history -- terraform.tfvars` |
| Add `tfplan` to .gitignore | Binary plan files contain infrastructure details |
| Rotate credentials if exposed | Change FortiGate admin password and VPN PSK |

### Priority 2: Configuration Hardening

**1. Tighten provider version constraints** (`providers.tf`):
```hcl
# Current: allows any 5.x version
version = "~> 5.0"

# Recommended: pin to minor version for stability
version = "~> 5.100"
```

**2. Restrict default admin_cidr** (`variables.tf`):
```hcl
# Current default allows all IPs - consider requiring explicit input
variable "admin_cidr" {
  description = "CIDR block allowed for management access"
  type        = string
  # Remove default or use a restrictive default
}
```

**3. Add input variable validation**:
```hcl
variable "vpc1_cidr" {
  description = "CIDR block for VPC 1"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc1_cidr, 0))
    error_message = "vpc1_cidr must be a valid CIDR block."
  }
}
```

### Priority 3: Infrastructure Enhancements

| Enhancement | Benefit |
|-------------|---------|
| Enable VPC Flow Logs | Network traffic visibility and troubleshooting |
| Enable EBS encryption at rest | Data protection compliance |
| Add CloudTrail logging | API call auditing |
| Use `locals` block for computed values | Cleaner configuration |

### Files to Update

| File | Change |
|------|--------|
| `.gitignore` | Add `tfplan` |
| `providers.tf` | Tighten version constraint |
| `variables.tf` | Add validation blocks, restrict `admin_cidr` default |

### Verification Checklist

- [ ] Confirm `terraform.tfvars` never committed to git history
- [ ] Confirm `.pem` files never committed to git history
- [ ] Rotate FortiGate admin password if credentials were exposed
- [ ] Rotate VPN PSK if credentials were exposed
- [ ] Add `tfplan` to `.gitignore`
- [ ] Run `terraform validate` after any configuration changes
