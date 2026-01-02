resource "aws_efs_file_system" "this" {
  encrypted = true

  lifecycle_policy {
    transition_to_ia = "AFTER_14_DAYS"
  }

  tags = { Name = "${var.name}-efs" }
}

resource "aws_efs_mount_target" "mt" {
  for_each        = { for i, id in var.private_subnet_ids : tostring(i) => id }
  file_system_id  = aws_efs_file_system.this.id
  subnet_id       = each.value
  security_groups = [var.efs_sg_id]
}

resource "aws_efs_access_point" "wp" {
  file_system_id = aws_efs_file_system.this.id

  posix_user {
    uid = 33
    gid = 33
  }

  root_directory {
    path = "/wp-content"
    creation_info {
      owner_uid   = 33
      owner_gid   = 33
      permissions = "0755"
    }
  }

  tags = { Name = "${var.name}-efs-ap-wp" }
}