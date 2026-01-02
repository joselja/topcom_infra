data "aws_rds_engine_version" "aurora_mysql" {
  engine                 = "aurora-mysql"
  parameter_group_family = "aurora-mysql8.0"
  default_only           = true
}

resource "random_id" "suffix" {
  byte_length = 3
}

resource "random_password" "db" {
  length           = 24
  special          = true
  override_special = "!#$%&'()*+,-.:;<=>?[]^_{|}~"
}

resource "aws_secretsmanager_secret" "db_password" {
  # Add random suffix to avoid name conflicts  
  name = "${var.name}-db-password-${random_id.suffix.hex}"
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = random_password.db.result
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-db-subnets"
  subnet_ids = var.private_subnet_ids
}

resource "aws_rds_cluster" "this" {
  cluster_identifier = "${var.name}-aurora"
  engine             = "aurora-mysql"
  engine_version     = data.aws_rds_engine_version.aurora_mysql.version

  database_name   = var.db_name
  master_username = var.db_username
  master_password = random_password.db.result

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.db_sg_id]

  storage_encrypted   = true
  deletion_protection = false
  skip_final_snapshot = true

  serverlessv2_scaling_configuration {
    min_capacity = var.min_acu
    max_capacity = var.max_acu
  }
}

# Serverless v2 still needs at least one cluster instance, with instance_class=db.serverless
resource "aws_rds_cluster_instance" "this" {
  identifier         = "${var.name}-aurora-1"
  cluster_identifier = aws_rds_cluster.this.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.this.engine
  engine_version     = aws_rds_cluster.this.engine_version
}