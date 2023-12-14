terraform {
  backend "s3" {
    bucket = "vkpr-teste"
    key    = "cluster-ec2-demo-a/terraform.tfstate"
    region = "us-east-1"
  }
}