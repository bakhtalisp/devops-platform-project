provider "aws" {
  region = "us-east-1"
}

module "vpc" {
  source = "../../modules/vpc"
}

module "security_group" {
  source = "../../modules/security-group"
  vpc_id = module.vpc.vpc_id
}

module "ec2" {
  source    = "../../modules/ec2"
  ami_id    = var.ami_id
  subnet_id = module.vpc.public_subnet_id
  sg_id     = module.security_group.sg_id
}

module "s3" {
  source        = "../../modules/s3"
  bucket_suffix = var.bucket_suffix
}
