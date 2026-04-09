terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project
      Environment = "staging"
      Owner       = var.owner
      CostCenter  = var.cost_center
      ManagedBy   = "terraform"
    }
  }
}

locals {
  environment = "staging"
  common_tags = {
    Project     = var.project
    Environment = local.environment
    Owner       = var.owner
    CostCenter  = var.cost_center
    ManagedBy   = "terraform"
  }
}

module "dynamodb" {
  source = "../../modules/dynamodb"

  project     = var.project
  environment = local.environment
  table_name  = "items"
  hash_key    = "id"
  attributes  = [{ name = "id", type = "S" }]

  read_capacity  = 10
  write_capacity = 10
  enable_pitr    = false
  ttl_attribute  = "expires_at"

  tags = local.common_tags
}

module "cognito" {
  source = "../../modules/cognito"

  project     = var.project
  environment = local.environment

  callback_urls = ["https://staging.example.com/callback"]
  logout_urls   = ["https://staging.example.com/logout"]

  tags = local.common_tags
}

module "lambda" {
  source = "../../modules/lambda"

  project       = var.project
  environment   = local.environment
  function_name = "api"
  description   = "API CRUD serverless — items (staging)"
  handler       = "handler.lambda_handler"
  runtime       = "python3.12"
  source_dir    = "${path.module}/../../lambda_src"

  memory_size        = 256
  timeout            = 30
  log_retention_days = 14

  environment_variables = {
    TABLE_NAME  = module.dynamodb.table_name
    ENVIRONMENT = local.environment
  }

  dynamodb_table_arns       = [module.dynamodb.table_arn]
  api_gateway_execution_arn = module.api_gateway.execution_arn

  tags       = local.common_tags
  depends_on = [module.dynamodb]
}

module "api_gateway" {
  source = "../../modules/api-gateway"

  project     = var.project
  environment = local.environment

  lambda_invoke_arn     = module.lambda.invoke_arn
  cognito_user_pool_arn = module.cognito.user_pool_arn

  throttling_burst_limit = 50
  throttling_rate_limit  = 100

  tags = local.common_tags
}

module "monitoring" {
  source = "../../modules/monitoring"

  project     = var.project
  environment = local.environment

  lambda_function_name         = module.lambda.function_name
  api_gateway_name             = "${var.project}-${local.environment}-api"
  api_gateway_stage            = local.environment
  alarm_email                  = var.alarm_email
  lambda_error_threshold       = 5
  lambda_duration_threshold_ms = 5000
  api_5xx_threshold            = 10
  api_4xx_threshold            = 50

  tags = local.common_tags
}
