variable "aws_region" {
  type        = string
  description = "AWS Region"
  default     = "us-east-1"
}
variable "vpc" {
  type        = string
  description = "VPC to deploy to"
  default     = "vpc-0a2a83d4e068c74c6"
}

variable "home_ip" {
  type        = string
  description = "My Home IP"
  default     = "69.244.147.227/32"
}

variable "ami" {
  type        = string
  description = "AMI to be used"
  default     = "ami-0e1bed4f06a3b463d"
}

variable "environment" {
  type        = string
  description = "environment"
  default     = "dev"
}

variable "instance_size" {
  type        = string
  description = "The instance size"
  default     = "g4dn.xlarge"
}

variable "zone_id" {
  type        = string
  description = "Route53 Zone ID"
  default     = "Z10057183MLGVY8QQ2VGK"
}

variable "key_name" {
  type        = string
  default     = "hashcat"
  description = "The Amazon EC2 Keypair name"
}

variable "min_size" {
  description = "The minimum number of instances in the Auto Scaling Group"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "The maximum number of instances in the Auto Scaling Group"
  type        = number
  default     = 2
}

variable "desired_capacity" {
  description = "The desired number of instances in the Auto Scaling Group"
  type        = number
  default     = 1
}
