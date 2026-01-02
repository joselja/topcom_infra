resource "aws_cloudwatch_log_group" "wp" {
  name              = "/ecs/${var.name}/wordpress"
  retention_in_days = 14
}

resource "aws_ecs_cluster" "this" {
  name = "${var.name}-cluster"
}

resource "aws_ecs_cluster_capacity_providers" "cp" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = 3
    base              = 1
  }

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
  }
}

resource "aws_lb" "alb" {
  name               = "${var.name}-alb"
  load_balancer_type = "application"
  subnets            = var.public_subnet_ids
  security_groups    = [var.alb_sg_id]
}

resource "aws_lb_target_group" "tg" {
  name        = "${var.name}-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/wp-login.php"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
    matcher             = "200-399"
  }
}

resource "aws_lb_listener" "http_redirect" {
  count             = var.enable_https ? 1 : 0
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}



resource "aws_lb_listener" "http_forward" {
  count             = var.enable_https ? 0 : 1
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}


resource "aws_lb_listener" "https" {
  count             = var.enable_https ? 1 : 0
  load_balancer_arn = aws_lb.alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

# IAM for ECS task execution (pull image, write logs, read secrets)
data "aws_iam_policy_document" "ecs_exec_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_execution" {
  name               = "${var.name}-ecs-exec"
  assume_role_policy = data.aws_iam_policy_document.ecs_exec_assume.json
}

resource "aws_iam_role_policy_attachment" "ecs_exec_managed" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Allow execution role to read DB password from Secrets Manager
data "aws_iam_policy_document" "secrets_read" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.db_password_secret_arn]
  }
}

resource "aws_iam_policy" "secrets_read" {
  name   = "${var.name}-secrets-read"
  policy = data.aws_iam_policy_document.secrets_read.json
}

resource "aws_iam_role_policy_attachment" "ecs_exec_secrets" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = aws_iam_policy.secrets_read.arn
}

# Task role (EFS IAM authorization uses task role when iam=ENABLED)
resource "aws_iam_role" "ecs_task" {
  name               = "${var.name}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_exec_assume.json
}

data "aws_iam_policy_document" "efs_client" {
  statement {
    actions = [
      "elasticfilesystem:ClientMount",
      "elasticfilesystem:ClientWrite",
      "elasticfilesystem:ClientRootAccess"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "efs_client" {
  name   = "${var.name}-efs-client"
  policy = data.aws_iam_policy_document.efs_client.json
}

resource "aws_iam_role_policy_attachment" "efs_client_attach" {
  role       = aws_iam_role.ecs_task.name
  policy_arn = aws_iam_policy.efs_client.arn
}

resource "aws_ecs_task_definition" "wp" {
  family                   = "${var.name}-wp"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  volume {
    name = "wp-content"
    efs_volume_configuration {
      file_system_id     = var.efs_id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = var.efs_ap_id
        iam             = "ENABLED"
      }
    }
  }

  container_definitions = jsonencode([{
    name  = "wordpress"
    image = "wordpress:6-php8.2-apache"

    portMappings = [{
      containerPort = 80
      protocol      = "tcp"
    }]

    environment = [
      { name = "WORDPRESS_DB_HOST", value = var.db_endpoint },
      { name = "WORDPRESS_DB_NAME", value = var.db_name },
      { name = "WORDPRESS_DB_USER", value = var.db_user }
    ]

    secrets = [
      { name = "WORDPRESS_DB_PASSWORD", valueFrom = var.db_password_secret_arn }
    ]

    mountPoints = [{
      sourceVolume  = "wp-content"
      containerPath = "/var/www/html/wp-content"
      readOnly      = false
    }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.wp.name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "wp"
      }
    }

    healthCheck = {
      command  = ["CMD-SHELL", "curl -f http://localhost/wp-login.php || exit 1"]
      interval = 30
      timeout  = 5
      retries  = 3
    }
  }])
}

resource "aws_ecs_service" "wp" {
  name            = "${var.name}-wp"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.wp.arn
  desired_count   = 1

  capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = 3
    base              = 1
  }
  capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
  }

  network_configuration {
    subnets          = var.public_subnet_ids
    security_groups  = [var.ecs_sg_id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.tg.arn
    container_name   = "wordpress"
    container_port   = 80
  }

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  depends_on = [
    aws_lb_listener.http_redirect,
    aws_lb_listener.http_forward,
    aws_lb_listener.https
  ]
}

# Autoscaling
resource "aws_appautoscaling_target" "ecs" {
  max_capacity       = var.max_tasks
  min_capacity       = 1
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.wp.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "cpu" {
  name               = "${var.name}-cpu-tt"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value = 50
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    scale_in_cooldown  = 180
    scale_out_cooldown = 60
  }
}