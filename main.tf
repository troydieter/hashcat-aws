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
HASHCAT="/usr/local/hashcat/hashcat.bin"
WORDLIST="/mnt/wordlists/xsukax-Wordlist-All.txt"
RULES="/usr/local/hashcat/rules/best64.rule"
HASHES="/mnt/hashes"
TMP="/tmp"
HOST=$(hostname)

# Ensure required tools are installed
apt-get update && apt-get install -y jq wget p7zip-full tmux awscli

# Ensure required directories exist
mkdir -p /mnt/hashes /mnt/hashcat /usr/local/hashcat

# Download and extract Hashcat
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

7zr x hashcat.7z -o/usr/local/hashcat && rm -f hashcat.7z
chmod -R 755 /usr/local/hashcat

# Verify Hashcat installation
if ! $HASHCAT -V; then
  echo "Error: Hashcat failed installation" | tee -a /var/log/user_data.log
  exit 1
fi

# Restore previous session if exists
if [ -d /mnt/hashcat ]; then
  cp -f /mnt/hashcat/hashcat.restore /usr/local/hashcat/hashcat.restore 
  cp -f /mnt/hashcat/hashcat.potfile /usr/local/hashcat/hashcat.potfile
  cp -f /mnt/hashcat/hashcat.dictstat2 /usr/local/hashcat/hashcat.dictstat2
  cp -f /mnt/hashcat/hashcat.log /usr/local/hashcat/hashcat.log
fi

# Check if hash list and type exist
if [ ! -f /mnt/hashes/crackme.type ]; then
  echo "Error: Hash type file not found!" | tee -a /var/log/user_data.log
  exit 1
fi

HASHTYPE=$(cat /mnt/hashes/crackme.type)

# Run Hashcat info and check for errors
if ! $HASHCAT -I >> "$HASHES/hashcat-info-$HOST.log" 2>&1; then
  echo "Error: Hashcat failed initialization" | tee -a /var/log/user_data.log
  exit 1
fi

# Start Hashcat in a tmux session
session="hashcat"
tmux new-session -d -s $session
tmux send-keys -t $session "$HASHCAT -o crackme.cracked -a 0 -m $HASHTYPE crackme $WORDLIST -r $RULES -w 4" C-m

# Ensure Hashcat started properly
sleep 10
if ! pgrep -x "hashcat.bin" > /dev/null; then
  echo "Error: Hashcat did not start properly" | tee -a /var/log/user_data.log
  exit 1
fi

# Monitor Hashcat process
while true; do
  if ! pgrep -x "hashcat.bin" > /dev/null; then
    echo "Hashcat finished, saving results..." | tee -a /var/log/user_data.log
    cp -f /usr/local/hashcat/hashcat.restore /mnt/hashcat/hashcat.restore
    cp -f /usr/local/hashcat/hashcat.potfile /mnt/hashcat/hashcat.potfile
    cp -f /usr/local/hashcat/hashcat.dictstat2 /mnt/hashcat/hashcat.dictstat2
    cp -f /usr/local/hashcat/hashcat.log /mnt/hashcat/hashcat.log
    shutdown -h now
  fi
  sleep 60
done
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