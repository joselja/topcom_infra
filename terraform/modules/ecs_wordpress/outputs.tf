output "alb_dns_name" { value = aws_lb.alb.dns_name }

output "cluster_arn" { value = aws_ecs_cluster.this.arn }

output "alb_arn_suffix" { value = aws_lb.alb.arn_suffix }

output "tg_arn_suffix" { value = aws_lb_target_group.tg.arn_suffix }

output "alb_zone_id" { value = aws_lb.alb.zone_id }

output "alb_arn" { value = aws_lb.alb.arn }