resource "random_id" "rando" {
  byte_length = 2
}

resource "random_integer" "rando_int" {
  min = 1
  max = 100
}

module "s3_bucket" {
  source = "terraform-aws-modules/s3-bucket/aws"

  bucket_prefix = "hashcat"
  acl           = "private"

  control_object_ownership = true
  object_ownership         = "ObjectWriter"

  versioning = {
    enabled = true
  }
}

resource "aws_launch_template" "hashcat" {
  name_prefix   = "hashcat-"
  image_id      = var.ami
  instance_type = var.instance_size
  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_ssm.name
  }
  vpc_security_group_ids = [aws_security_group.hashcat_sg.id]
  key_name               = var.key_name

  user_data = base64encode(<<EOT
#!/bin/bash

# Enable logging for debugging
exec > /var/log/user_data.log 2>&1
set -x

# Variables
HASHCAT_DIR="/usr/local/hashcat"
TMP="/tmp"
HOST=$(hostname)

# Ensure required tools are installed
apt-get update && apt-get install -y jq wget p7zip-full tmux awscli

# Ensure required directories exist
mkdir -p /mnt/hashes /mnt/hashcat "$HASHCAT_DIR"

# Download Hashcat
cd $TMP
HASHCAT_URL=$(curl -s https://api.github.com/repos/hashcat/hashcat/releases/latest | jq -r '.assets[] | select(.name|endswith(".7z")) | .browser_download_url')
if [[ -z "$HASHCAT_URL" ]]; then
  echo "Error: Unable to fetch Hashcat download URL" | tee -a /var/log/user_data.log
  exit 1
fi

wget -q "$HASHCAT_URL" -O hashcat.7z
if [[ ! -f "hashcat.7z" ]]; then
  echo "Error: Hashcat download failed" | tee -a /var/log/user_data.log
  exit 1
fi

# Extract Hashcat
7zr x hashcat.7z -o"$TMP/hashcat" && rm -f hashcat.7z

# Find extracted Hashcat directory
EXTRACTED_DIR=$(find "$TMP/hashcat" -maxdepth 1 -type d | tail -n 1)
if [[ ! -d "$EXTRACTED_DIR" ]]; then
  echo "Error: Hashcat extraction failed" | tee -a /var/log/user_data.log
  exit 1
fi

# Move extracted files correctly
if [[ -d "$EXTRACTED_DIR/hashcat-6.2.6" ]]; then
  mv "$EXTRACTED_DIR/hashcat-6.2.6"/* "$HASHCAT_DIR/"
  rm -rf "$EXTRACTED_DIR/hashcat-6.2.6"
else
  mv "$EXTRACTED_DIR"/* "$HASHCAT_DIR/"
fi
chmod -R 755 "$HASHCAT_DIR"

# Verify Hashcat installation
if [[ ! -f "$HASHCAT_DIR/hashcat.bin" ]]; then
  echo "Error: Hashcat binary not found after installation" | tee -a /var/log/user_data.log
  exit 1
fi

# Check if Hashcat runs properly
if ! "$HASHCAT_DIR/hashcat.bin" -V; then
  echo "Error: Hashcat failed to run" | tee -a /var/log/user_data.log
  exit 1
fi

echo "Hashcat installation successful!" | tee -a /var/log/user_data.log
EOT
  )
}

resource "aws_autoscaling_group" "hashcat" {
  name = "hashcat-asg-${random_id.rando.hex}"
  launch_template {
    id      = aws_launch_template.hashcat.id
    version = "$Latest"
  }

  min_size         = var.min_size
  max_size         = var.max_size
  desired_capacity = var.desired_capacity


  vpc_zone_identifier       = data.aws_subnets.all.ids
  target_group_arns         = []
  health_check_type         = "EC2" # Can also be "ELB" if using a load balancer
  health_check_grace_period = 300   # Give the instance 5 minutes to initialize
  tag {
    key                 = "Name"
    value               = "hashcat-${random_id.rando.hex}"
    propagate_at_launch = true
  }
}

##################################################################
# Data sources to get VPC, subnet, security group and AMI details
##################################################################
data "aws_vpc" "selected" {
  id = var.vpc
}

data "aws_subnets" "all" {
  filter {
    name   = "tag:Reach"
    values = ["public"]
  }
}

resource "aws_security_group" "hashcat_sg" {
  name_prefix = "hashcat-sg-"
  vpc_id      = data.aws_vpc.selected.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.home_ip]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# SSM
data "aws_iam_policy" "required-policy" {
  name = "AmazonSSMManagedInstanceCore"
}

# IAM Role
resource "aws_iam_role" "hashcat-role" {
  name = "hashcat-${random_id.rando.hex}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "bucket_full_access" {
  name        = "bucket-full-access"
  description = "Allows all actions on the S3 bucket defined in module.s3_bucket"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "FullAccessToBucket",
        Effect = "Allow",
        Action = "s3:*",
        Resource = [
          module.s3_bucket.s3_bucket_arn,
          "${module.s3_bucket.s3_bucket_arn}/*"
        ]
      }
    ]
  })
}


# Attach the policy to the role
resource "aws_iam_role_policy_attachment" "attach-ssm" {
  role       = aws_iam_role.hashcat-role.name
  policy_arn = data.aws_iam_policy.required-policy.arn
}

resource "aws_iam_role_policy_attachment" "attach-s3" {
  role       = aws_iam_role.hashcat-role.name
  policy_arn = aws_iam_policy.bucket_full_access.arn
}

resource "aws_iam_instance_profile" "ec2_ssm" {
  name = "aws_ssm_hashcat-${random_id.rando.hex}"
  role = aws_iam_role.hashcat-role.name
}