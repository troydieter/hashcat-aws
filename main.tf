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
  monitoring {
    enabled = True
  }
  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_ssm.name
  }
  vpc_security_group_ids = [aws_security_group.hashcat_sg.id]
  key_name               = var.key_name
  user_data              = base64encode(file("bootstrap.sh"))
}

resource "aws_autoscaling_group" "hashcat" {
  name = "hashcat-asg-${random_id.rando.hex}"

  mixed_instances_policy {
    instances_distribution {
      on_demand_allocation_strategy = "prioritized"
      spot_allocation_strategy      = "lowest-price" # Spot instance allocation strategy
      spot_instance_pools           = 2              # Number of Spot instance pools to choose from
    }



    launch_template {
      launch_template_specification {
        launch_template_name = aws_launch_template.hashcat.name # Use launch_template_name here
        version              = "$Latest"
      }
    }
  }

  instance_maintenance_policy {
    min_healthy_percentage = 90
    max_healthy_percentage = 120
  }

  min_size         = var.min_size
  max_size         = var.max_size
  desired_capacity = var.desired_capacity

  vpc_zone_identifier       = data.aws_subnets.all.ids
  health_check_type         = "EC2"
  health_check_grace_period = 300
  tag {
    key                 = "Name"
    value               = "hashcat-${random_id.rando.hex}"
    propagate_at_launch = true
  }
}

resource "aws_autoscalingplans_scaling_plan" "hashcat" {
  name = "hashcat-asg-plan-dynamic-${random_id.rando.hex}"

  application_source {
    tag_filter {
      key    = "Name"
      values = ["hashcat-${random_id.rando.hex}"]
    }
  }

  scaling_instruction {
    max_capacity       = 2
    min_capacity       = 0
    resource_id        = format("autoScalingGroup/%s", aws_autoscaling_group.hashcat.name)
    scalable_dimension = "autoscaling:autoScalingGroup:DesiredCapacity"
    service_namespace  = "autoscaling"

    target_tracking_configuration {
      predefined_scaling_metric_specification {
        predefined_scaling_metric_type = "ASGAverageCPUUtilization"
      }

      target_value = 70
    }
  }
}

resource "aws_autoscaling_lifecycle_hook" "instance_launching" {
  name                   = "hashcat-instance-launching"
  autoscaling_group_name = aws_autoscaling_group.hashcat.name
  lifecycle_transition   = "autoscaling:EC2_INSTANCE_LAUNCHING"
  heartbeat_timeout      = 300
  default_result         = "CONTINUE"
}

resource "aws_autoscaling_lifecycle_hook" "instance_terminating" {
  name                   = "hashcat-instance-terminating"
  autoscaling_group_name = aws_autoscaling_group.hashcat.name
  lifecycle_transition   = "autoscaling:EC2_INSTANCE_TERMINATING"
  heartbeat_timeout      = 300
  default_result         = "CONTINUE"
}

# Retrieve current NAT'd public IP address - Windows only
# If this is having issues, use the var.home_ip variable instead and define the string.
data "external" "current_ip" {
  program = ["powershell", "-Command", "(Invoke-WebRequest -Uri 'https://ifconfig.io').Content.Trim() | ConvertTo-Json -Compress | % { '{\"ip\":\"' + ($_ -replace '\"','') + '/32\"}' }"]
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
    cidr_blocks = [data.external.current_ip.result.ip]
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