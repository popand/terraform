# -----------------------------------------------------------------------------
# VPC Modules
# -----------------------------------------------------------------------------
module "vpc1" {
  source = "./modules/vpc"

  name                = "vpc1"
  vpc_cidr            = var.vpc1_cidr
  public_subnet_cidr  = var.vpc1_public_subnet_cidr
  private_subnet_cidr = var.vpc1_private_subnet_cidr
  availability_zone   = "${var.aws_region}a"
}

module "vpc2" {
  source = "./modules/vpc"

  name                = "vpc2"
  vpc_cidr            = var.vpc2_cidr
  public_subnet_cidr  = var.vpc2_public_subnet_cidr
  private_subnet_cidr = var.vpc2_private_subnet_cidr
  availability_zone   = "${var.aws_region}a"
}

# -----------------------------------------------------------------------------
# Elastic IPs (created first to resolve circular dependency)
# -----------------------------------------------------------------------------
resource "aws_eip" "fortigate1" {
  domain = "vpc"

  tags = {
    Name = "fortigate1-eip"
  }

  depends_on = [module.vpc1]
}

resource "aws_eip" "fortigate2" {
  domain = "vpc"

  tags = {
    Name = "fortigate2-eip"
  }

  depends_on = [module.vpc2]
}

# -----------------------------------------------------------------------------
# FortiGate Modules
# -----------------------------------------------------------------------------
module "fortigate1" {
  source = "./modules/fortigate"

  name                       = "FortiGate-1"
  instance_type              = var.fortigate_instance_type
  key_name                   = var.key_name
  vpc_id                     = module.vpc1.vpc_id
  public_subnet_id           = module.vpc1.public_subnet_id
  private_subnet_id          = module.vpc1.private_subnet_id
  public_subnet_cidr         = module.vpc1.public_subnet_cidr
  private_subnet_cidr        = module.vpc1.private_subnet_cidr
  admin_cidr                 = var.admin_cidr
  remote_private_subnet_cidr = module.vpc2.private_subnet_cidr
  admin_password             = var.fortigate_admin_password
  vpn_psk                    = var.vpn_psk
  vpn_peer_ip                = aws_eip.fortigate2.public_ip
  vpn_name                   = "vpn-to-vpc2"
  eip_allocation_id          = aws_eip.fortigate1.id
  eip_public_ip              = aws_eip.fortigate1.public_ip
}

module "fortigate2" {
  source = "./modules/fortigate"

  name                       = "FortiGate-2"
  instance_type              = var.fortigate_instance_type
  key_name                   = var.key_name
  vpc_id                     = module.vpc2.vpc_id
  public_subnet_id           = module.vpc2.public_subnet_id
  private_subnet_id          = module.vpc2.private_subnet_id
  public_subnet_cidr         = module.vpc2.public_subnet_cidr
  private_subnet_cidr        = module.vpc2.private_subnet_cidr
  admin_cidr                 = var.admin_cidr
  remote_private_subnet_cidr = module.vpc1.private_subnet_cidr
  admin_password             = var.fortigate_admin_password
  vpn_psk                    = var.vpn_psk
  vpn_peer_ip                = aws_eip.fortigate1.public_ip
  vpn_name                   = "vpn-to-vpc1"
  eip_allocation_id          = aws_eip.fortigate2.id
  eip_public_ip              = aws_eip.fortigate2.public_ip
}

# -----------------------------------------------------------------------------
# Ubuntu Modules
# -----------------------------------------------------------------------------
module "ubuntu1" {
  source = "./modules/ubuntu"

  name               = "Ubuntu-VM-1"
  instance_type      = var.ubuntu_instance_type
  key_name           = var.key_name
  vpc_id             = module.vpc1.vpc_id
  subnet_id          = module.vpc1.private_subnet_id
  private_ip         = cidrhost(var.vpc1_private_subnet_cidr, 10)
  admin_cidr         = var.admin_cidr
  remote_subnet_cidr = module.vpc2.private_subnet_cidr
}

module "ubuntu2" {
  source = "./modules/ubuntu"

  name               = "Ubuntu-VM-2"
  instance_type      = var.ubuntu_instance_type
  key_name           = var.key_name
  vpc_id             = module.vpc2.vpc_id
  subnet_id          = module.vpc2.private_subnet_id
  private_ip         = cidrhost(var.vpc2_private_subnet_cidr, 10)
  admin_cidr         = var.admin_cidr
  remote_subnet_cidr = module.vpc1.private_subnet_cidr
}

# -----------------------------------------------------------------------------
# Route Table Updates (routes to FortiGate for cross-VPC traffic)
# -----------------------------------------------------------------------------
resource "aws_route" "vpc1_to_vpc2" {
  route_table_id         = module.vpc1.private_route_table_id
  destination_cidr_block = var.vpc2_private_subnet_cidr
  network_interface_id   = module.fortigate1.private_eni_id
}

resource "aws_route" "vpc1_default" {
  route_table_id         = module.vpc1.private_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = module.fortigate1.private_eni_id
}

resource "aws_route" "vpc2_to_vpc1" {
  route_table_id         = module.vpc2.private_route_table_id
  destination_cidr_block = var.vpc1_private_subnet_cidr
  network_interface_id   = module.fortigate2.private_eni_id
}

resource "aws_route" "vpc2_default" {
  route_table_id         = module.vpc2.private_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = module.fortigate2.private_eni_id
}

# -----------------------------------------------------------------------------
# Phase 2: Bedrock AI Agent Module
# -----------------------------------------------------------------------------
module "bedrock_agent" {
  source = "./modules/bedrock-agent"

  count = var.enable_bedrock_agent ? 1 : 0

  project_name   = "terraform-docs"
  aws_region     = var.aws_region
  enable_agent   = var.enable_bedrock_agent

  # Pass Phase 1 outputs to the agent for infrastructure testing
  phase1_outputs = {
    fortigate1_public_ip  = module.fortigate1.public_ip
    fortigate2_public_ip  = module.fortigate2.public_ip
    fortigate1_private_ip = module.fortigate1.private_ip
    fortigate2_private_ip = module.fortigate2.private_ip
    ubuntu1_private_ip    = module.ubuntu1.private_ip
    ubuntu2_private_ip    = module.ubuntu2.private_ip
    vpc1_id               = module.vpc1.vpc_id
    vpc2_id               = module.vpc2.vpc_id
  }

  tags = {
    Project     = "FortiGate-VPN-Demo"
    Phase       = "2"
    Component   = "Bedrock-Agent"
    ManagedBy   = "Terraform"
  }
}

# -----------------------------------------------------------------------------
# Chat UI Module (requires Bedrock Agent)
# -----------------------------------------------------------------------------
module "chat_ui" {
  source = "./modules/chat-ui"

  count = var.enable_chat_ui && var.enable_bedrock_agent ? 1 : 0

  project_name   = "terraform-chat"
  aws_region     = var.aws_region
  agent_id       = module.bedrock_agent[0].agent_id
  agent_alias_id = module.bedrock_agent[0].agent_alias_id

  tags = {
    Project     = "FortiGate-VPN-Demo"
    Phase       = "2"
    Component   = "Chat-UI"
    ManagedBy   = "Terraform"
  }
}
