# ┌─────────────────────────────────────────────────────────────────────────────┐
# │  MODULE : api-gateway                                                       │
# │                                                                             │
# │  REST API v1 (vs HTTP API v2) : on choisit v1 car plus feature-rich        │
# │    → Usage plans, API keys, WAF integration, request validation             │
# │                                                                             │
# │  Free Tier : 1 million d'appels API/mois (12 premiers mois)                │
# │                                                                             │
# │  Architecture des routes :                                                  │
# │    GET    /items        → liste tous les items                              │
# │    POST   /items        → crée un item                                      │
# │    GET    /items/{id}   → récupère un item                                  │
# │    PUT    /items/{id}   → met à jour un item                                │
# │    DELETE /items/{id}   → supprime un item                                  │
# │                                                                             │
# │  Toutes les routes sont protégées par Cognito (JWT Bearer token)           │
# └─────────────────────────────────────────────────────────────────────────────┘

locals {
  api_name    = "${var.project}-${var.environment}-api"
  common_tags = merge(var.tags, { Module = "api-gateway" })
}

# ─── IAM Role : permet à API Gateway d'écrire dans CloudWatch ─────────────────
# Ce rôle est requis au NIVEAU DU COMPTE AWS (une seule fois).
# Sans lui, l'activation de l'access logging échoue avec BadRequestException.
data "aws_iam_policy_document" "apigw_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "apigw_cloudwatch" {
  name               = "${local.api_name}-cloudwatch-role"
  assume_role_policy = data.aws_iam_policy_document.apigw_assume.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "apigw_cloudwatch" {
  role       = aws_iam_role.apigw_cloudwatch.name
  # Managed policy AWS : autorise API Gateway à pousser des logs CloudWatch
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

# Paramètre au niveau du compte — configure le rôle CloudWatch pour API Gateway
resource "aws_api_gateway_account" "this" {
  cloudwatch_role_arn = aws_iam_role.apigw_cloudwatch.arn

  depends_on = [aws_iam_role_policy_attachment.apigw_cloudwatch]
}

# ─── Log Group pour l'access logging ─────────────────────────────────────────
# L'access logging enregistre qui appelle l'API (IP, user, route, status)
# C'est différent des execution logs (détails d'invocation Lambda)
resource "aws_cloudwatch_log_group" "api_access" {
  name              = "/aws/api-gateway/${local.api_name}"
  retention_in_days = 7

  tags = local.common_tags
}

# ─── 1. REST API ──────────────────────────────────────────────────────────────
resource "aws_api_gateway_rest_api" "this" {
  name        = local.api_name
  description = "API serverless ${var.project} — environnement ${var.environment}"

  endpoint_configuration {
    # REGIONAL = l'API est déployée dans une seule région
    # EDGE = via CloudFront (global, mais plus cher et complexe)
    # Pour dev/staging, REGIONAL est suffisant
    types = ["REGIONAL"]
  }

  tags = local.common_tags
}

# ─── 2. Cognito Authorizer ────────────────────────────────────────────────────
# Vérifie le JWT Bearer token dans le header Authorization
# Si le token est invalide ou expiré → 401 Unauthorized automatique
# La Lambda ne reçoit la requête QUE si le token est valide
resource "aws_api_gateway_authorizer" "cognito" {
  name          = "${local.api_name}-cognito-auth"
  rest_api_id   = aws_api_gateway_rest_api.this.id
  type          = "COGNITO_USER_POOLS"
  provider_arns = [var.cognito_user_pool_arn]

  # Le token JWT doit être dans le header Authorization
  identity_source = "method.request.header.Authorization"
}

# ─── 3. Ressource /items ──────────────────────────────────────────────────────
resource "aws_api_gateway_resource" "items" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "items"
}

# ─── GET /items ───────────────────────────────────────────────────────────────
resource "aws_api_gateway_method" "get_items" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.items.id
  http_method   = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

resource "aws_api_gateway_integration" "get_items" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.items.id
  http_method             = aws_api_gateway_method.get_items.http_method
  integration_http_method = "POST" # Lambda s'invoque toujours en POST, peu importe la méthode HTTP
  type                    = "AWS_PROXY" # Proxy = API Gateway transmet tout à Lambda sans transformation
  uri                     = var.lambda_invoke_arn
}

# ─── POST /items ──────────────────────────────────────────────────────────────
resource "aws_api_gateway_method" "post_items" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.items.id
  http_method   = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

resource "aws_api_gateway_integration" "post_items" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.items.id
  http_method             = aws_api_gateway_method.post_items.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.lambda_invoke_arn
}

# ─── 4. Ressource /items/{id} ─────────────────────────────────────────────────
resource "aws_api_gateway_resource" "item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_resource.items.id
  path_part   = "{id}" # {id} = path parameter — API Gateway l'extrait et le transmet à Lambda
}

# ─── GET /items/{id} ──────────────────────────────────────────────────────────
resource "aws_api_gateway_method" "get_item" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.item.id
  http_method   = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id

  request_parameters = {
    "method.request.path.id" = true # true = paramètre requis
  }
}

resource "aws_api_gateway_integration" "get_item" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.item.id
  http_method             = aws_api_gateway_method.get_item.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.lambda_invoke_arn
}

# ─── PUT /items/{id} ──────────────────────────────────────────────────────────
resource "aws_api_gateway_method" "put_item" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.item.id
  http_method   = "PUT"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

resource "aws_api_gateway_integration" "put_item" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.item.id
  http_method             = aws_api_gateway_method.put_item.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.lambda_invoke_arn
}

# ─── DELETE /items/{id} ───────────────────────────────────────────────────────
resource "aws_api_gateway_method" "delete_item" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.item.id
  http_method   = "DELETE"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

resource "aws_api_gateway_integration" "delete_item" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.item.id
  http_method             = aws_api_gateway_method.delete_item.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.lambda_invoke_arn
}

# ─── 5. Déploiement ───────────────────────────────────────────────────────────
# CONCEPT CLÉ : En REST API v1, les changements ne sont PAS automatiquement live.
# Il faut créer un "deployment" puis l'associer à un "stage".
# triggers → forcer un nouveau déploiement quand les méthodes/intégrations changent.
resource "aws_api_gateway_deployment" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.items.id,
      aws_api_gateway_resource.item.id,
      aws_api_gateway_method.get_items.id,
      aws_api_gateway_method.post_items.id,
      aws_api_gateway_method.get_item.id,
      aws_api_gateway_method.put_item.id,
      aws_api_gateway_method.delete_item.id,
      aws_api_gateway_integration.get_items.id,
      aws_api_gateway_integration.post_items.id,
      aws_api_gateway_integration.get_item.id,
      aws_api_gateway_integration.put_item.id,
      aws_api_gateway_integration.delete_item.id,
    ]))
  }

  # create_before_destroy évite les downtime lors des redéploiements
  lifecycle {
    create_before_destroy = true
  }
}

# ─── 6. Stage ─────────────────────────────────────────────────────────────────
# Le stage = version "live" du déploiement.
# URL finale : https://{api-id}.execute-api.{region}.amazonaws.com/{stage_name}
resource "aws_api_gateway_stage" "this" {
  deployment_id = aws_api_gateway_deployment.this.id
  rest_api_id   = aws_api_gateway_rest_api.this.id
  stage_name    = var.environment

  # Access logging : enregistre chaque requête dans CloudWatch
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_access.arn
    # Format JSON structuré pour faciliter les requêtes CloudWatch Insights
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      caller         = "$context.identity.caller"
      user           = "$context.identity.user"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      resourcePath   = "$context.resourcePath"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
    })
  }

  xray_tracing_enabled = false # X-Ray coûte ~$5/million de traces → désactivé

  depends_on = [aws_api_gateway_account.this]

  tags = local.common_tags
}

# ─── 7. Method Settings (throttling) ─────────────────────────────────────────
# Protège contre les abus et les coûts inattendus
# */* = s'applique à toutes les méthodes et toutes les ressources du stage
resource "aws_api_gateway_method_settings" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = aws_api_gateway_stage.this.stage_name
  method_path = "*/*"

  settings {
    throttling_burst_limit = var.throttling_burst_limit # Pic max simultané
    throttling_rate_limit  = var.throttling_rate_limit  # Requêtes/seconde steady state
    metrics_enabled        = true                       # Active les métriques CloudWatch (gratuit)
    logging_level          = "OFF"                      # Execution logs nécessitent un IAM role au niveau compte
    data_trace_enabled     = false
  }
}
