output "instance_id" {
  value = aws_instance.taskflow.id
}

output "instance_address" {
  description = "Address taskflow-api is reachable on"
  value       = coalesce(aws_instance.taskflow.public_ip, aws_instance.taskflow.private_ip)
}

output "security_group_id" {
  value = aws_security_group.taskflow.id
}

output "host_name" {
  description = "Container name Ansible connects to"
  value       = docker_container.host.name
}

output "host_address" {
  value = docker_container.host.network_data[0].ip_address
}
