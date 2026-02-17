output "infra_mgmt_server_ip" { value = module.mgmt_server.public_ip }
output "jenkins_server_ip" { value = module.jenkins_server.public_ip }
output "jump_server_ip" { value = module.jump_server.public_ip }

output "infra_mgmt_private_ip" { value = module.mgmt_server.private_ip }
output "jenkins_private_ip" { value = module.jenkins_server.private_ip }
output "jump_server_private_ip" { value = module.jump_server.private_ip }

output "infra_mgmt_instance_id" { value = module.mgmt_server.instance_id }
output "jenkins_instance_id" { value = module.jenkins_server.instance_id }
output "jump_server_instance_id" { value = module.jump_server.instance_id }
