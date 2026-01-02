terraform {
  backend "s3" {
    bucket         = "topcom-test-state-bucket"
    key            = "wp-test/terraform.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}