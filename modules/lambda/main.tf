# ┌─────────────────────────────────────────────────────────────────────────────┐
# │  MODULE : lambda                                                            │
# │                                                                             │
# │  Ce module crée :                                                           │
# │    1. Un CloudWatch Log Group (pré-créé pour contrôler la rétention)        │
# │    2. Un IAM Role avec le principe du moindre privilège                     │
# │    3. Une policy logs (uniquement sur CE log group, pas sur *)              │
# │    4. Une policy DynamoDB (conditionnelle — seulement si on passe des ARNs) │
# │    5. Le ZIP du code Python (via le provider archive)                       │
# │    6. La fonction Lambda elle-même                                          │
# │    7. La permission pour qu'API Gateway puisse l'invoquer                  │
# └─────────────────────────────────────────────────────────────────────────────┘

locals {
  # Nom complet : ex. "myapp-dev-api"
  function_name = "${var.project}-${var.environment}-${var.function_name}"

  common_tags = merge(var.tags, {
    Module = "lambda"
  })
}

# ─── 1. CloudWatch Log Group ──────────────────────────────────────────────────
# POURQUOI le créer avant la Lambda ?
# Si on ne le pré-crée pas, Lambda le crée automatiquement SANS rétention.
# Les logs s'accumulent indéfiniment → coût CloudWatch et désordre.
resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

# ─── 2. IAM Role (identité de la Lambda) ─────────────────────────────────────
# "Trust policy" : qui peut endosser ce rôle ?
# Réponse : uniquement le service lambda.amazonaws.com
data "aws_iam_policy_document" "assume_role" {
  statement {
    sid     = "LambdaAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${local.function_name}-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  tags = local.common_tags
}

# ─── 3. Policy : CloudWatch Logs (moindre privilège) ─────────────────────────
# On N'utilise PAS AWSLambdaBasicExecutionRole (managed policy d'AWS).
# Cette policy gérée autorise CreateLogGroup sur "*" → trop permissif.
# Notre policy custom restreint à CE log group uniquement.
data "aws_iam_policy_document" "logs" {
  statement {
    sid    = "AllowCloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    # ":*" = tous les log streams dans CE groupe uniquement
    resources = ["${aws_cloudwatch_log_group.this.arn}:*"]
  }
}

resource "aws_iam_policy" "logs" {
  name        = "${local.function_name}-logs-policy"
  description = "Autorise Lambda à écrire dans son log group CloudWatch uniquement"
  policy      = data.aws_iam_policy_document.logs.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "logs" {
  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.logs.arn
}

# ─── 4. Policy : DynamoDB (conditionnelle) ───────────────────────────────────
# count = 0 si aucune table n'est passée → la policy n'existe pas du tout.
# C'est le pattern "feature flag" en Terraform : count = condition ? 1 : 0
data "aws_iam_policy_document" "dynamodb" {
  count = length(var.dynamodb_table_arns) > 0 ? 1 : 0

  statement {
    sid    = "DynamoDBCRUD"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:Query",
      "dynamodb:Scan",
    ]
    # On liste explicitement les ARNs — pas de wildcard *
    resources = var.dynamodb_table_arns
  }
}

resource "aws_iam_policy" "dynamodb" {
  count = length(var.dynamodb_table_arns) > 0 ? 1 : 0

  name        = "${local.function_name}-dynamodb-policy"
  description = "Autorise Lambda à faire du CRUD sur les tables DynamoDB spécifiées"
  policy      = data.aws_iam_policy_document.dynamodb[0].json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "dynamodb" {
  count = length(var.dynamodb_table_arns) > 0 ? 1 : 0

  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.dynamodb[0].arn
}

# ─── 5. Archive ZIP du code source ───────────────────────────────────────────
# Le provider "archive" zippe le dossier source_dir en local.
# output_base64sha256 = empreinte du ZIP → Lambda ne redéploie QUE si le code change.
# Sans ça, Terraform redéploierait à chaque `apply` même sans changement de code.
data "archive_file" "this" {
  type        = "zip"
  source_dir  = var.source_dir
  output_path = "${path.module}/.build/${local.function_name}.zip"
}

# ─── 6. Fonction Lambda ───────────────────────────────────────────────────────
resource "aws_lambda_function" "this" {
  function_name = local.function_name
  description   = var.description

  # Identité d'exécution
  role    = aws_iam_role.this.arn
  handler = var.handler
  runtime = var.runtime

  # Package de déploiement
  filename         = data.archive_file.this.output_path
  source_code_hash = data.archive_file.this.output_base64sha256

  # Performance
  # Free Tier : 1 million d'invocations/mois + 400 000 GB-secondes/mois
  # 128MB × 30s = 3.75 GB-secondes par invocation → large marge
  memory_size = var.memory_size
  timeout     = var.timeout

  environment {
    variables = var.environment_variables
  }

  # PassThrough = pas de X-Ray → pas de coût X-Ray
  # "Active" coûterait $5/million de traces → à éviter sur Free Tier
  tracing_config {
    mode = "PassThrough"
  }

  # On attend que le log group ET le role attachment soient créés
  # avant de créer la fonction (sinon Lambda tente d'écrire sans permission)
  depends_on = [
    aws_cloudwatch_log_group.this,
    aws_iam_role_policy_attachment.logs,
  ]

  tags = local.common_tags
}

# ─── 7. Permission API Gateway → Lambda ──────────────────────────────────────
# AWS requiert une permission explicite pour qu'API Gateway puisse invoquer Lambda.
# Sans ça : 403 "Internal server error" très difficile à déboguer.
# La resource_based_policy (≠ IAM policy) autorise un service externe.
resource "aws_lambda_permission" "api_gateway" {
  # POURQUOI sans count ?
  # count = condition basée sur un ARN calculé à l'apply → Terraform ne peut pas
  # évaluer la condition au plan. On crée toujours cette permission.
  # Si api_gateway_execution_arn est vide, terraform apply échouera explicitement.

  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  principal     = "apigateway.amazonaws.com"

  # source_arn avec "/*/*" = autorise toutes les méthodes et toutes les routes
  # Plus sécurisé que "*" : on restreint à CETTE API uniquement
  source_arn = "${var.api_gateway_execution_arn}/*/*"
}
