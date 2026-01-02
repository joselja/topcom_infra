output "aws_role_to_assume" {
  value       = aws_iam_role.github_terraform.arn
  description = "IAM Role ARN to configure in GitHub Actions as AWS_ROLE_TO_ASSUME"
}