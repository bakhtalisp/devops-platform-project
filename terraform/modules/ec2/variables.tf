variable "project_name" {
  type    = string
  default = "devops-platform"
}

variable "ami_id" {
  type        = string
  description = "Free-tier eligible AMI (Amazon Linux 2023)"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "subnet_id" {
  type = string
}

variable "sg_id" {
  type = string
}
