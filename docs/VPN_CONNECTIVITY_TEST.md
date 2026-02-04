# VPN Connectivity Test Procedure

## Overview

This document provides step-by-step instructions for accessing the Ubuntu VMs deployed in private subnets and testing IPSec VPN connectivity between VPC 1 and VPC 2.

## Architecture Context

```
┌───────────────────────────────────────┐     ┌─────────────────────────────────────┐
│           VPC 1 (10.0.0.0/16)         │     │         VPC 2 (10.100.0.0/16)       │
│                                       │     │                                     │
│  ┌─────────────────────────────┐      │     │    ┌─────────────────────────────┐  │
│  │  Public Subnet (10.0.0.0/24)│      │     │    │Public Subnet (10.100.0.0/24)│  │
│  │     ┌─────────────────┐     │      │     │    │     ┌─────────────────┐     │  │
│  │     │  FortiGate-1    │     │      │ VPN │    │     │  FortiGate-2    │     │  │
│  │     │  3.23.187.8     │◄────┼──────┼─────┼────┼────►│  3.133.221.252  │     │  │
│  │     └────────┬────────┘     │IPSec │     │    │     └────────┬────────┘     │  │
│  └──────────────┼──────────────┘Tunnel│     │    └──────────────┼──────────────┘  │
│                 │                     │     │                   │                 │
│  ┌──────────────┼──────────────┐      │     │    ┌──────────────┼──────────────┐  │
│  │  Private Subnet (10.0.1.0/24)      │     │    │Private Subnet (10.100.1.0/24)  │
│  │     ┌─────────────────┐     │      │     │    │     ┌─────────────────┐     │  │
│  │     │   Ubuntu-VM-1   │     │      │     │    │     │   Ubuntu-VM-2   │     │  │
│  │     │   10.0.1.10     │     │      │     │    │     │   10.100.1.10   │     │  │
│  │     └─────────────────┘     │      │     │    │     └─────────────────┘     │  │
│  └─────────────────────────────┘      │     │    └─────────────────────────────┘  │
└───────────────────────────────────────┘     └─────────────────────────────────────┘
```

## The Challenge

The Ubuntu VMs are deployed in **private subnets** with no public IP addresses. 

Test VPN connectivity (ping from Ubuntu-VM-1 to Ubuntu-VM-2)

---

## VIP Port Forwarding via FortiGate (temporary enablement to test connectivity)

This method configures FortiGate-1 to forward SSH connections on port 2222 to Ubuntu-VM-1 on port 22.

### Prerequisites

- SSH key file: `fortigate-demo-key.pem`
- FortiGate-1 Public IP: `3.23.187.8`
- FortiGate-1 Instance ID (initial password): `i-00eae7a6e7f5e2aee`
- Ubuntu-VM-1 Private IP: `10.0.1.10`

### Step 1: Update AWS Security Group

Allow inbound traffic on port 2222 to FortiGate-1's public security group.

```bash
# Get the security group ID (if needed)
aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=FortiGate-1-public-sg" \
    --query "SecurityGroups[*].GroupId" \
    --output text

# Add ingress rule for port 2222
aws ec2 authorize-security-group-ingress \
    --group-id sg-094788664219fbb98 \
    --protocol tcp \
    --port 2222 \
    --cidr 0.0.0.0/0
```


### Step 2: SSH to FortiGate-1

```bash
ssh -i fortigate-demo-key.pem admin@3.23.187.8
```


### Step 3: Configure Virtual IP (VIP) on FortiGate

Once logged into the FortiGate CLI, run the following commands:

```bash
# Create a Virtual IP to forward port 2222 to Ubuntu-VM-1 SSH (port 22)
config firewall vip
    edit "ubuntu-vm1-ssh"
        set extintf "port1"
        set portforward enable
        set mappedip "10.0.1.10"
        set extport 2222
        set mappedport 22
    next
end

# Create a firewall policy to allow the VIP traffic
config firewall policy
    edit 100
        set name "ssh-to-ubuntu-vm1"
        set srcintf "port1"
        set dstintf "port2"
        set srcaddr "all"
        set dstaddr "ubuntu-vm1-ssh"
        set action accept
        set schedule "always"
        set service "ALL"
    next
end
```

### Step 4: Verify Configuration

Still in FortiGate CLI:

```bash
# Verify VIP is configured
show firewall vip

# Verify firewall policy is active
show firewall policy 100

# Test connectivity from FortiGate to Ubuntu-VM-1
execute ping 10.0.1.10
```

### Step 5: Exit FortiGate and SSH to Ubuntu-VM-1

```bash
# Exit FortiGate CLI
exit

# SSH to Ubuntu-VM-1 via FortiGate port forwarding
ssh -i fortigate-demo-key.pem -p 2222 ubuntu@3.23.187.8
```

### Step 6: Test VPN Connectivity

Once logged into Ubuntu-VM-1:

```bash
# Ping Ubuntu-VM-2 in VPC 2 over the VPN tunnel
ping 10.100.1.10

# Traceroute to see the path (should go through FortiGate)
traceroute 10.100.1.10

```

**Expected Ping Output:**
```
ubuntu@Ubuntu-VM-1:~$ ping 10.100.1.10
PING 10.100.1.10 (10.100.1.10) 56(84) bytes of data.
64 bytes from 10.100.1.10: icmp_seq=1 ttl=62 time=0.688 ms
64 bytes from 10.100.1.10: icmp_seq=2 ttl=62 time=0.670 ms
64 bytes from 10.100.1.10: icmp_seq=3 ttl=62 time=0.723 ms
```

### Step 7: Cleanup (Optional)

To remove the VIP and firewall policy after testing:

```bash
# SSH back to FortiGate
ssh -i fortigate-demo-key.pem admin@3.23.187.8

# Remove firewall policy first (must be removed before VIP)
config firewall policy
    delete 100
end

# Remove VIP
config firewall vip
    delete "ubuntu-vm1-ssh"
end

# Exit FortiGate
exit

# Remove AWS security group rule
aws ec2 revoke-security-group-ingress \
    --group-id sg-094788664219fbb98 \
    --protocol tcp \
    --port 2222 \
    --cidr 0.0.0.0/0
```

---

## Demo Recording

A video recording of the VPN connectivity test is available:

[vpn_connectivity_test_recording.mov](vpn_connectivity_test_recording.mov)

This recording demonstrates:
- SSH access to Ubuntu-VM-1 via FortiGate VIP port forwarding
- Successful ping from Ubuntu-VM-1 (10.0.1.10) to Ubuntu-VM-2 (10.100.1.10) over the IPSec VPN tunnel


---

## Alternative Access Methods

If VIP port forwarding is not suitable, consider these alternatives:

| Option | Description |
|--------|-------------|
| **Temporary Public IP** | Assign an Elastic IP directly to Ubuntu-VM-1 for direct SSH access. Quick but bypasses FortiGate for SSH traffic. |
| **AWS Systems Manager** | Use SSM Session Manager for shell access. Requires IAM instance profile and either NAT Gateway or VPC Endpoints. Recommended for production environments. |

---





