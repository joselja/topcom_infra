output "alb_dns_name" {
  value = module.ecs_wordpress.alb_dns_name
}

output "sns_topic_arn" {
  value = module.alerts.sns_topic_arn
}

output "db_endpoint" {
  value = module.database.db_endpoint
}