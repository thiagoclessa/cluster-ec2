data "aws_availability_zones" "available" {
  state = "available"
}
data "aws_ami" "ubuntu-linux-2004" {
  most_recent = true
  owners      = ["099720109477"] 
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

### REDE


resource "aws_internet_gateway" "igw" {
  vpc_id = local.config.VPC_ID
}
resource "aws_subnet" "public_subnet" {
  vpc_id = local.config.VPC_ID
  cidr_block = local.config.publicsCIDRblock
  map_public_ip_on_launch = "true" 
  availability_zone = local.config.availabilityZone
  tags = {
    Template = "Exati_Ec2"
  }
}
resource "aws_route_table" "public_rt" {
  vpc_id = local.config.VPC_ID
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public" {
  route_table_id = aws_route_table.public_rt.id
  subnet_id = aws_subnet.public_subnet.id
  
}


resource "aws_security_group" "web_security_group" {
  name        = "access_cluster_SG"
  description = "Allow SSH and HTTP"
  vpc_id      = local.config.VPC_ID
  ingress {
    description = "SSH from VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    }
  ingress {
    description = "EFS mount target"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    }
  ingress {
    description = "HTTP from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    }
  ingress {
    description = "Cluster Access"
    from_port   = 6550
    to_port     = 6550
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
  Template = "Exati_Ec2"
  }
}

resource "aws_instance" "platform_ec2" {
  ami                    = data.aws_ami.amazon-linux.id
  key_name               = local.config.keypar
  security_groups        = [aws_security_group.web_security_group.id]
  instance_type          = local.config.instance_type
  subnet_id              = aws_subnet.public_subnet.id
  user_data = <<EOF
#!/bin/bash
sudo apt update
sudo apt install nginx
EOF
  tags = {
  Name = local.config.cluster_name
  Template = "Exati_Ec2"
  }
}

resource "aws_eip" "webip" {
    instance = aws_instance.platform_ec2.id
    vpc = true
    tags = {
    Template = "Exati_Ec2"
  }
}

resource "aws_efs_file_system" "efs" {}

resource "aws_efs_mount_target" "mount" {
  file_system_id = aws_efs_file_system.efs.id
  subnet_id      = aws_instance.platform_ec2.subnet_id
  security_groups = [aws_security_group.web_security_group.id]
}


output "instance_ip_addr" {
  value       = aws_eip.webip.public_ip
}
