[infra_mgmt]
${mgmt_ip} ansible_connection=aws_ssm ansible_aws_ssm_region=${region}

[jenkins_server]
${jenkins_ip} ansible_connection=aws_ssm ansible_aws_ssm_region=${region}

[jump_server]
${jump_ip} ansible_connection=aws_ssm ansible_aws_ssm_region=${region}

[all:vars]
# Using AWS Systems Manager Session Manager for secure, keyless access
ansible_connection=aws_ssm
ansible_aws_ssm_region=${region}
region=${region}
cluster_name=${cluster_name}
ecr_frontend_url=${ecr_frontend_url}
ecr_backend_url=${ecr_backend_url}
aws_account_id=${account_id}
ansible_python_interpreter=/usr/bin/python3
infra_mgmt_private_ip=${mgmt_private_ip}
ansible_ssh_private_key_file=./private_key.pem
