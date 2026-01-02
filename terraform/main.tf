data "aws_availability_zones" "available" {
  state = "available"
}

module "network" {
  source = "./modules/network"

  name                 = var.name
  vpc_cidr             = "10.20.0.0/16"
  azs                  = slice(data.aws_availability_zones.available.names, 0, 2)
  public_subnet_cidrs  = ["10.20.0.0/20", "10.20.16.0/20"]
  private_subnet_cidrs = ["10.20.128.0/20", "10.20.144.0/20"]
}

module "efs" {
  source = "./modules/efs"

  name               = var.name
  vpc_id             = module.network.vpc_id
  private_subnet_ids = module.network.private_subnet_ids
  efs_sg_id          = module.network.efs_sg_id
}

module "database" {
  source = "./modules/database"

  name               = var.name
  vpc_id             = module.network.vpc_id
  private_subnet_ids = module.network.private_subnet_ids
  db_sg_id           = module.network.db_sg_id
  db_name            = "wordpress"
  db_username        = "wpadmin"
  min_acu            = 0.5
  max_acu            = 2.0
}

module "ecs_wordpress" {
  source = "./modules/ecs_wordpress"

  name              = var.name
  aws_region        = var.aws_region
  vpc_id            = module.network.vpc_id
  public_subnet_ids = module.network.public_subnet_ids

  alb_sg_id = module.network.alb_sg_id
  ecs_sg_id = module.network.ecs_sg_id

  efs_id    = module.efs.efs_id
  efs_ap_id = module.efs.efs_access_point_id

  db_endpoint            = module.database.db_endpoint
  db_name                = module.database.db_name
  db_user                = module.database.db_username
  db_password_secret_arn = module.database.db_password_secret_arn

  max_tasks = var.max_tasks

  enable_https = var.enable_https
  # This conditional ensures the module only receives a certificate ARN when HTTPS is enabled, 
  # preventing invalid references and keeping the infrastructure deployable without domain ownership
  certificate_arn = var.enable_https ? aws_acm_certificate_validation.wp[0].certificate_arn : null
}

module "alerts" {
  source = "./modules/alerts"

  name        = var.name
  alert_email = var.alert_email

  cluster_arn    = module.ecs_wordpress.cluster_arn
  alb_arn_suffix = module.ecs_wordpress.alb_arn_suffix
  tg_arn_suffix  = module.ecs_wordpress.tg_arn_suffix
}

data "aws_route53_zone" "this" {
  count        = var.enable_https ? 1 : 0
  name         = trimsuffix(var.domain_name, ".")
  private_zone = false
}

locals {
  route53_zone_id = var.enable_https ? data.aws_route53_zone.this[0].zone_id : null
}

# Request ACM certificate (DNS validation)
resource "aws_acm_certificate" "wp" {
  count             = var.enable_https ? 1 : 0
  domain_name       = var.site_fqdn
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# Create DNS validation records in Route53
resource "aws_route53_record" "wp_cert_validation" {
  for_each = var.enable_https ? {
    for dvo in aws_acm_certificate.wp[0].domain_validation_options :
    dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  } : {}

  zone_id = local.route53_zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]
}

# Finalize validation
resource "aws_acm_certificate_validation" "wp" {
  count = var.enable_https ? 1 : 0

  certificate_arn = aws_acm_certificate.wp[0].arn
  validation_record_fqdns = [
    for r in aws_route53_record.wp_cert_validation : r.fqdn
  ]
}

# Optional DNS Alias to ALB (A)
resource "aws_route53_record" "wp_alias_a" {
  count = (var.enable_https && var.create_dns_alias != null) ? 1 : 0

  zone_id = local.route53_zone_id
  name    = var.site_fqdn
  type    = "A"

  alias {
    name                   = module.ecs_wordpress.alb_dns_name
    zone_id                = module.ecs_wordpress.alb_zone_id
    evaluate_target_health = true
  }
}

# Optional DNS Alias to ALB (AAAA)
resource "aws_route53_record" "wp_alias_aaaa" {
  count = (var.enable_https && var.create_dns_alias != null) ? 1 : 0

  zone_id = local.route53_zone_id
  name    = var.site_fqdn
  type    = "AAAA"

  alias {
    name                   = module.ecs_wordpress.alb_dns_name
    zone_id                = module.ecs_wordpress.alb_zone_id
    evaluate_target_health = true
  }
}

resource "null_resource" "input_validation" {
  lifecycle {
    precondition {
      condition     = var.enable_https == false || (var.domain_name != null && length(var.domain_name) > 0)
      error_message = "domain_name must be set when enable_https=true."
    }

    precondition {
      condition     = var.enable_https == false || (var.site_fqdn != null && length(var.site_fqdn) > 0)
      error_message = "site_fqdn must be set when enable_https=true."
    }

    precondition {
      condition     = var.enable_https == false || endswith(var.site_fqdn, ".${var.domain_name}")
      error_message = "site_fqdn must be a subdomain of domain_name (e.g., wp.example.com for example.com)."
    }
  }
}