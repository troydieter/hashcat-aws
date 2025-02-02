# AWS Hashcat Infrastructure

This project provides an automated way to deploy and manage a fleet of GPU-enabled EC2 instances for running Hashcat password cracking operations at scale using AWS infrastructure.

## Overview

The infrastructure consists of:
- Auto Scaling Group (ASG) with mixed instance types support
- Launch Template with GPU-enabled instances
- S3 bucket for storing results
- Security Groups with your IP automatically configured
- IAM roles and policies for EC2 and S3 access
- Systems Manager (SSM) integration for instance management

## Prerequisites

- AWS Account
- Terraform installed (v1.0.0+)
- AWS CLI configured
- PowerShell (for automatic IP detection)
- Valid AWS key pair for EC2 instances

## Quick Start

1. Clone this repository:
```bash
git clone https://github.com/troydieter/hashcat-aws.git
cd aws-hashcat
```

2. Create a `terraform.tfvars` file:
```hcl
vpc           = "vpc-xxxxxx"
ami           = "ami-xxxxxx"  # Ubuntu AMI with NVIDIA drivers
instance_size = "g4dn.xlarge"
key_name      = "your-key-pair-name"
min_size      = 1
max_size      = 10
desired_capacity = 2
```

3. Initialize and apply Terraform:
```bash
terraform init
terraform plan
terraform apply
```

## Features

### Auto Scaling
- Dynamic scaling between min and max instances
- Spot instance support for cost optimization
- Mixed instance types support
- Health checks and automatic replacement of unhealthy instances

### Security
- Private S3 bucket with versioning enabled
- Security group automatically configured with your current IP
- IAM roles with least privilege access
- SSM integration for secure instance management

### Cost Optimization
- Spot instance usage
- Auto-termination after task completion
- Configurable instance sizes

## Configuration

### Variables

| Variable | Description | Default |
|----------|-------------|---------|
| vpc | VPC ID | Required |
| ami | AMI ID | Required |
| instance_size | EC2 instance type | g4dn.xlarge |
| key_name | SSH key pair name | Required |
| min_size | Minimum instances | 1 |
| max_size | Maximum instances | 10 |
| desired_capacity | Target number of instances | 2 |

### Instance Types

The infrastructure supports GPU-enabled instances:
- g4dn.xlarge
- g4dn.2xlarge
- p3.2xlarge
- p3.8xlarge

## Monitoring and Management

### Accessing Instances
```bash
aws ssm start-session --target i-xxxxxxxxxxxxxxxxx
```

### Checking Results
Results are stored in the S3 bucket created by the infrastructure:
```bash
aws s3 ls s3://hashcat-xxxxx/
```

## Bootstrap Process

The instances are bootstrapped with:
1. NVIDIA driver installation
2. Hashcat installation
3. Automatic configuration
4. Task execution
5. Result upload to S3
6. Auto-termination on completion

## Cleanup

To destroy the infrastructure:
```bash
terraform destroy
```

## Security Considerations

- Access is restricted to your IP address
- All S3 data is private and versioned
- Instance access is managed through SSM
- No direct SSH access by default
- Least privilege IAM policies

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

[Your chosen license]

## Disclaimer

This tool is for legal security testing only. Ensure you have permission to perform password cracking operations.
