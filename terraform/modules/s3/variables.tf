variable "project_name" {
  type    = string
  default = "devops-platform"
}

variable "bucket_suffix" {
  type        = string
  description = "Unique suffix since S3 bucket names are globally unique"
}
