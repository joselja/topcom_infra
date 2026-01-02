variable "aws_region" {
  type    = string
  default = "eu-west-1"
}

variable "name" {
  type    = string
  default = "wp-test"
}

variable "alert_email" {
  type        = string
  description = "Email to subscribe to SNS alerts"
}

variable "max_tasks" {
  type    = number
  default = 6
}

variable "certificate_arn" {
  type        = string
  description = "ACM certificate ARN (must be in same region as the ALB)"
  default     = null
}

variable "domain_name" {
  type        = string
  description = "Base domain hosted in Route53, e.g. example.com"
  default     = null
}


variable "create_dns_alias" {
  type    = bool
  default = true
}

variable "enable_https" {
  type        = bool
  description = "Enable HTTPS using ACM and ALB (requires domain ownership and DNS access)"
  default     = false
}

variable "site_fqdn" {
  type        = string
  description = "FQDN for WordPress (e.g. wp.example.com). Required only if HTTPS is enabled."
  default     = null
}