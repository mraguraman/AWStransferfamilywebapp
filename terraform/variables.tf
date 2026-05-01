variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "ap-southeast-1"
}

variable "project_name" {
  description = "Project name used as prefix for all resource names"
  type        = string
  default     = "secure-transfer"
}

variable "environment" {
  description = "Deployment environment (dev / staging / prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket for file storage. Leave empty to auto-generate."
  type        = string
  default     = ""
}

variable "web_app_provisioned_units" {
  description = "Number of provisioned capacity units. Each unit supports 250 concurrent sessions."
  type        = number
  default     = 1

  validation {
    condition     = var.web_app_provisioned_units >= 1
    error_message = "provisioned_units must be at least 1."
  }
}

variable "transfer_users" {
  description = "List of users to create in IAM Identity Center and assign to the web app"
  type = list(object({
    display_name = string
    user_name    = string
    email        = string
    given_name   = string
    family_name  = string
  }))
  default = []
}
