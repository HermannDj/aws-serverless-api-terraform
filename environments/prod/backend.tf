terraform {
  backend "s3" {
    bucket         = "serverless-api-terraform-state-e503a9f9"
    key            = "prod/terraform.tfstate"
    region         = "ca-central-1"
    encrypt        = true
    dynamodb_table = "serverless-api-terraform-locks"
  }
}
