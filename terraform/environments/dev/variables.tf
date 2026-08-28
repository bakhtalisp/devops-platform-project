variable "ami_id" {
  type        = string
  description = "Ubuntu AMI for us-east-1 (verify current AMI ID in AWS console before apply)"
}

variable "bucket_suffix" {
  type = string
}
