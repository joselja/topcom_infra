output "db_endpoint" {
  value = aws_rds_cluster.this.endpoint
}

output "db_name" {
  value = var.db_name
}

output "db_username" {
  value = var.db_username
}

output "db_password_secret_arn" {
  value = aws_secretsmanager_secret.db_password.arn
}