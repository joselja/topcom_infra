resource "aws_s3_bucket" "tf_state" {
  bucket = var.state_bucket_name
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket                  = aws_s3_bucket.tf_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "locks" {
  name         = var.lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

# ----------------------------
# GitHub Actions OIDC Provider
# ----------------------------
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1"
  ]
}

data "aws_iam_policy_document" "github_oidc_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Restrict to your repo
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:joselja/topcom_test:*"]
    }
  }
}

resource "aws_iam_role" "github_terraform" {
  name               = "github-terraform"
  assume_role_policy = data.aws_iam_policy_document.github_oidc_trust.json
}

data "aws_iam_policy_document" "terraform_permissions" {
  statement {
    actions = [
      "ec2:*",
      "ecs:*",
      "elasticloadbalancing:*",
      "rds:*",
      "elasticfilesystem:*",
      "route53:*",
      "acm:*",
      "logs:*",
      "cloudwatch:*",
      "sns:*",
      "iam:*"
    ]
    resources = ["*"]
  }

  # Backend state bucket permissions
  statement {
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.tf_state.arn,
      "${aws_s3_bucket.tf_state.arn}/*"
    ]
  }

  # State lock table permissions
  statement {
    actions   = ["dynamodb:*"]
    resources = [aws_dynamodb_table.locks.arn]
  }
}

resource "aws_iam_policy" "github_terraform" {
  name   = "github-terraform-policy"
  policy = data.aws_iam_policy_document.terraform_permissions.json
}

resource "aws_iam_role_policy_attachment" "github_terraform" {
  role       = aws_iam_role.github_terraform.name
  policy_arn = aws_iam_policy.github_terraform.arn
}