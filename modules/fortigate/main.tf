# -----------------------------------------------------------------------------
# FortiGate AMI Lookup (PAYG - On-Demand)
# -----------------------------------------------------------------------------
data "aws_ami" "fortigate" {
  most_recent = true
  owners      = ["aws-marketplace"]

  filter {
    name   = "name"
    values = ["FortiGate-VM64-AWSONDEMAND *"]
  }

  filter {
    name   = "product-code"
    values = ["2wqkpek696qhdeo7lbbjncqli"] # FortiGate PAYG On-Demand
  }
}

# -----------------------------------------------------------------------------
# Security Groups
# -----------------------------------------------------------------------------
resource "aws_security_group" "public" {
  name        = "${var.name}-public-sg"
  description = "Security group for ${var.name} public interface"
  vpc_id      = var.vpc_id

  # HTTPS management access
  ingress {
    description = "HTTPS management"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  # SSH management access
  ingress {
    description = "SSH management"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  # IKE for IPSec VPN
  ingress {
    description = "IKE"
    from_port   = 500
    to_port     = 500
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # NAT-T for IPSec VPN
  ingress {
    description = "NAT-T"
    from_port   = 4500
    to_port     = 4500
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name}-public-sg"
  }
}

resource "aws_security_group" "private" {
  name        = "${var.name}-private-sg"
  description = "Security group for ${var.name} private interface"
  vpc_id      = var.vpc_id

  # Allow all traffic from local private subnet
  ingress {
    description = "Traffic from local private subnet"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.private_subnet_cidr]
  }

  # Allow traffic from remote private subnet (via VPN)
  ingress {
    description = "Traffic from remote subnet via VPN"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.remote_private_subnet_cidr]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name}-private-sg"
  }
}

# -----------------------------------------------------------------------------
# Network Interfaces
# -----------------------------------------------------------------------------
resource "aws_network_interface" "public" {
  subnet_id         = var.public_subnet_id
  security_groups   = [aws_security_group.public.id]
  source_dest_check = false

  tags = {
    Name = "${var.name}-public-eni"
  }
}

resource "aws_network_interface" "private" {
  subnet_id         = var.private_subnet_id
  security_groups   = [aws_security_group.private.id]
  source_dest_check = false

  tags = {
    Name = "${var.name}-private-eni"
  }
}

# -----------------------------------------------------------------------------
# Elastic IP Association
# -----------------------------------------------------------------------------
resource "aws_eip_association" "this" {
  allocation_id        = var.eip_allocation_id
  network_interface_id = aws_network_interface.public.id

  # Wait for the instance to be running before associating EIP
  depends_on = [aws_instance.this]
}

# -----------------------------------------------------------------------------
# FortiGate Instance
# -----------------------------------------------------------------------------
resource "aws_instance" "this" {
  ami           = data.aws_ami.fortigate.id
  instance_type = var.instance_type
  key_name      = var.key_name

  network_interface {
    network_interface_id = aws_network_interface.public.id
    device_index         = 0
  }

  network_interface {
    network_interface_id = aws_network_interface.private.id
    device_index         = 1
  }

  user_data = templatefile("${path.module}/templates/fortigate_config.tpl", {
    hostname          = var.name
    admin_password    = var.admin_password
    private_ip        = aws_network_interface.private.private_ip
    private_netmask   = "255.255.255.0"
    private_gateway   = cidrhost(var.private_subnet_cidr, 1)
    vpn_peer_ip       = var.vpn_peer_ip
    vpn_psk           = var.vpn_psk
    vpn_name          = var.vpn_name
    local_subnet      = var.private_subnet_cidr
    remote_subnet     = var.remote_private_subnet_cidr
  })

  tags = {
    Name = var.name
  }
}
