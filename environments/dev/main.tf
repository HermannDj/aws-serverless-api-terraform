# ┌─────────────────────────────────────────────────────────────────────────────┐
# │  ENVIRONNEMENT : dev                                                        │
# │                                                                             │
# │  C'est ICI qu'on assemble les modules comme des LEGO.                      │
# │  Chaque module = une brique. Cet fichier = la notice de montage.           │
# │                                                                             │
# │  Flux des dépendances :                                                     │
# │    cognito → api-gateway (besoin de user_pool_arn pour l'authorizer)       │
# │    dynamodb → lambda    (besoin de table_arn pour la policy IAM)           │
# │    lambda  → api-gateway (besoin de invoke_arn pour l'intégration)         │
# │    lambda + api-gateway → monitoring                                        │
# └─────────────────────────────────────────────────────────────────────────────┘

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
      Environment = "dev"
      Owner       = var.owner
      CostCenter  = var.cost_center
      ManagedBy   = "terraform"
    }
  }
}

locals {
  environment = "dev"
  # Tags communs transmis à chaque module
  common_tags = {
    Project     = var.project
    Environment = local.environment
    Owner       = var.owner
    CostCenter  = var.cost_center
    ManagedBy   = "terraform"
  }
}

# ─── Module : DynamoDB ────────────────────────────────────────────────────────
module "dynamodb" {
  source = "../../modules/dynamodb"

  project     = var.project
  environment = local.environment
  table_name  = "items"

  hash_key = "id"
  attributes = [
    { name = "id", type = "S" }
  ]

  # Dev : 5/5 → dans les 25/25 RCU/WCU du Free Tier always-free
  read_capacity  = 5
  write_capacity = 5

  ttl_attribute = "expires_at"
  enable_pitr   = false # Pas de PITR en dev → gratuit

  tags = local.common_tags
}

# ─── Module : Cognito ─────────────────────────────────────────────────────────
module "cognito" {
  source = "../../modules/cognito"

  project     = var.project
  environment = local.environment

  callback_urls = ["http://localhost:3000/callback"]
  logout_urls   = ["http://localhost:3000/logout"]

  tags = local.common_tags
}

# ─── Module : Lambda ──────────────────────────────────────────────────────────
module "lambda" {
  source = "../../modules/lambda"

  project       = var.project
  environment   = local.environment
  function_name = "api"
  description   = "API CRUD serverless — items"
  handler       = "handler.lambda_handler"
  runtime       = "python3.12"

  # Chemin vers le code source Python
  # path.module = environments/dev/ → on remonte 2 niveaux vers lambda_src/
  source_dir = "${path.module}/../../lambda_src"

  memory_size        = 128 # Free Tier : 400 000 GB-secondes/mois
  timeout            = 30
  log_retention_days = 7

  # Variables d'environnement injectées dans la Lambda
  environment_variables = {
    TABLE_NAME  = module.dynamodb.table_name
    ENVIRONMENT = local.environment
  }

  # La Lambda a besoin de lire/écrire dans DynamoDB
  dynamodb_table_arns = [module.dynamodb.table_arn]

  # Permettre à API Gateway d'invoquer Lambda
  # On utilise l'ARN d'exécution du module api-gateway
  api_gateway_execution_arn = module.api_gateway.execution_arn

  tags = local.common_tags

  # Lambda dépend de DynamoDB (la table doit exister avant)
  depends_on = [module.dynamodb]
}

# ─── Module : API Gateway ────────────────────────────────────────────────────
module "api_gateway" {
  source = "../../modules/api-gateway"

  project     = var.project
  environment = local.environment

  lambda_invoke_arn     = module.lambda.invoke_arn
  cognito_user_pool_arn = module.cognito.user_pool_arn

  # Throttling conservateur pour dev (protège contre les abus accidentels)
  throttling_burst_limit = 10
  throttling_rate_limit  = 20

  tags = local.common_tags
}

# ─── Module : Monitoring ──────────────────────────────────────────────────────
module "monitoring" {
  source = "../../modules/monitoring"

  project     = var.project
  environment = local.environment

  lambda_function_name = module.lambda.function_name
  api_gateway_name     = "${var.project}-${local.environment}-api"
  api_gateway_stage    = local.environment

  alarm_email = var.alarm_email # Vide par défaut → pas d'email en dev

  # Seuils souples en dev (on veut être alerté rapidement)
  lambda_error_threshold       = 3
  lambda_duration_threshold_ms = 3000
  api_5xx_threshold            = 5
  api_4xx_threshold            = 30

  tags = local.common_tags
}
