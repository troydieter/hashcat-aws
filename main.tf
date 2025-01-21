resource "random_id" "rando" {
  byte_length = 2
}

resource "random_integer" "rando_int" {
  min = 1
  max = 100
}

resource "aws_launch_template" "hashcat" {
  name_prefix   = "hashcat-"
  image_id      = var.ami
  instance_type = var.instance_size

  user_data = base64encode(<<EOT
#!/bin/bash
HASHCAT=/usr/local/hashcat/hashcat.bin
WORDLIST=/mnt/wordlists/xsukax-Wordlist-All.txt
RULES=/usr/local/hashcat/rules/best64.rule
HASHES=/mnt/hashes/
TMP=/tmp/
HOST=`/bin/hostname`

cd $TMP
curl -s https://api.github.com/repos/hashcat/hashcat/releases/latest | jq '.assets[] | select(.name|match(".7z$")) | .browser_download_url' | sed 's/"/ /' | sed 's/"/ /' | wget -i -
7zr x hashcat*.7z
rm -f hashcat*.7z
mv -f /tmp/hashcat* /usr/local/hashcat

if [ -e /mnt/hashcat ]; then
  cp -f /mnt/hashcat/hashcat.restore /usr/local/hashcat/hashcat.restore 
  cp -f /mnt/hashcat/hashcat.potfile /usr/local/hashcat/hashcat.potfile
  cp -f /mnt/hashcat/hashcat.dictstat2 /usr/local/hashcat/hashcat.dictstat2
  cp -f /mnt/hashcat/hashcat.log /usr/local/hashcat/hashcat.log
fi

$HASHCAT -I >> $HASHES/hashcat-info-$HOST.log

cd /mnt/hashes/
HASHTYPE=`cat /mnt/hashes/crackme.type`
session="hashcat"
tmux new-session -d -s $session
window=0
tmux rename-window -t $session:$window 'hashcat'
tmux send-keys -t $session:$window "$HASHCAT -o crackme.cracked -a 0 -m $HASHTYPE crackme $WORDLIST -r $RULES -w 4" C-m

sleep 60s
while true; do
  pidof hashcat.bin > /dev/null 2>&1
  retVal=$?
  if [[ $retVal -ne 0 ]]; then
    cp -f /usr/local/hashcat/hashcat.restore /mnt/hashcat/hashcat.restore
    cp -f /usr/local/hashcat/hashcat.potfile /mnt/hashcat/hashcat.potfile
    cp -f /usr/local/hashcat/hashcat.dictstat2 /mnt/hashcat/hashcat.dictstat2
    cp -f /usr/local/hashcat/hashcat.log /mnt/hashcat/hashcat.log
    shutdown -h now
  fi
  sleep 60s
done
EOT
  )
}

resource "aws_autoscaling_group" "hashcat" {
  launch_template {
    id      = aws_launch_template.hashcat.id
    version = "$Latest"
  }

  min_size         = 1
  max_size         = 5
  desired_capacity = 1

  vpc_zone_identifier = [tolist(data.aws_subnets.all.ids)[0], tolist(data.aws_subnets.all.ids)[1]]
  target_group_arns   = []
  tags = [
    {
      key                 = "Name"
      value               = "hashcat-instance"
      propagate_at_launch = true
    }
  ]
}

##################################################################
# Data sources to get VPC, subnet, security group and AMI details
##################################################################
data "aws_vpc" "default" {
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
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = -1
    to_port     = -1
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
resource "aws_iam_role" "ssm-role" {
  name = "eggdrop-${random_id.rando.hex}"
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
      },
    ]
  })
}

# Attach the policy to the role
resource "aws_iam_role_policy_attachment" "attach-ssm" {
  role       = aws_iam_role.ssm-role.name
  policy_arn = data.aws_iam_policy.required-policy.arn
}

resource "aws_iam_instance_profile" "ec2_ssm" {
  name = "aws_ssm_eggdrop-${random_id.rando.hex}"
  role = aws_iam_role.ssm-role.name
}