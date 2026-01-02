variable "name" { type = string }
variable "aws_region" { type = string }

variable "vpc_id" { type = string }
variable "public_subnet_ids" { type = list(string) }

variable "alb_sg_id" { type = string }
variable "ecs_sg_id" { type = string }

variable "efs_id" { type = string }
variable "efs_ap_id" { type = string }

variable "db_endpoint" { type = string }
variable "db_name" { type = string }
variable "db_user" { type = string }
variable "db_password_secret_arn" { type = string }

variable "max_tasks" { type = number }

variable "certificate_arn" {
  type        = string
  description = "ACM certificate ARN to attach to the ALB HTTPS listener"
  default     = null
}

variable "enable_https" {
  type    = bool
  default = false
}