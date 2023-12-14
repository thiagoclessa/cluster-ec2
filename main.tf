data "aws_availability_zones" "available" {
  state = "available"
}
data "aws_ami" "amazon-linux" {
  most_recent = true

  filter {
    name   = "owner-alias"
    values = ["amazon"]
  }

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-ebs"]
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
    Template = "Platform_Ec2"
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
  Template = "Platform_Ec2"
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
sudo yum update && sudo yum upgrade
sudo yum install -y curl-minimal wget openssl git unzip docker sed
sudo service docker start && sudo systemctl enable docker.service
sudo usermod -a -G docker ec2-user && newgrp docker
wget -q -O - https://raw.githubusercontent.com/rancher/k3d/main/install.sh | bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/1.27.7/2023-11-02/bin/linux/amd64/kubectl
chmod +x ./kubectl && mkdir -p $HOME/bin && cp ./kubectl $HOME/bin/kubectl && export PATH=$HOME/bin:$PATH
k3d cluster create k3s --servers 1 -p "80:80@loadbalancer" -p "443:443@loadbalancer" --api-port 6550  --k3s-arg "--disable=traefik@server:*" --kubeconfig-update-default
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx

EOF
  tags = {
  Name = local.config.cluster_name
  Template = "Platform_Ec2"
  }
}

resource "aws_eip" "webip" {
    instance = aws_instance.platform_ec2.id
    vpc = true
    tags = {
    Template = "Platform_Ec2"
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