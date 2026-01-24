output "instance_id" {
  description = "FortiGate instance ID"
  value       = aws_instance.this.id
}

output "public_ip" {
  description = "FortiGate public IP address"
  value       = var.eip_public_ip
}

output "private_ip" {
  description = "FortiGate private interface IP"
  value       = aws_network_interface.private.private_ip
}

output "private_eni_id" {
  description = "FortiGate private network interface ID"
  value       = aws_network_interface.private.id
}

output "management_url" {
  description = "FortiGate management URL"
  value       = "https://${var.eip_public_ip}"
}

output "ssh_command" {
  description = "SSH command to connect to FortiGate"
  value       = "ssh admin@${var.eip_public_ip}"
}
