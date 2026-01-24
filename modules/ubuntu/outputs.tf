output "instance_id" {
  description = "Ubuntu instance ID"
  value       = aws_instance.this.id
}

output "private_ip" {
  description = "Ubuntu private IP address"
  value       = aws_instance.this.private_ip
}
