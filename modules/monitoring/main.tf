# ┌─────────────────────────────────────────────────────────────────────────────┐
# │  MODULE : monitoring                                                        │
# │                                                                             │
# │  CloudWatch Free Tier :                                                     │
# │    • 10 alarmes (12 premiers mois)                                          │
# │    • Métriques Lambda/API Gateway INCLUSES dans leurs services              │
# │    • On crée 4 alarmes → dans les limites Free Tier                        │
# │                                                                             │
# │  Alarmes créées :                                                           │
# │    1. Lambda Errors (erreurs d'exécution)                                   │
# │    2. Lambda Duration P95 (lenteur)                                         │
# │    3. API Gateway 5XX (erreurs serveur)                                     │
# │    4. API Gateway 4XX (erreurs client — trop élevé = anomalie)              │
# └─────────────────────────────────────────────────────────────────────────────┘

locals {
  prefix      = "${var.project}-${var.environment}"
  common_tags = merge(var.tags, { Module = "monitoring" })
}

# ─── SNS Topic (notifications par email) ─────────────────────────────────────
# SNS Free Tier : 1 million de requêtes + 1 000 emails/mois
resource "aws_sns_topic" "alarms" {
  count = var.alarm_email != "" ? 1 : 0

  name = "${local.prefix}-alarms"
  tags = local.common_tags
}

resource "aws_sns_topic_subscription" "email" {
  count = var.alarm_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.alarms[0].arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

locals {
  # Si alarm_email est fourni, on notifie par SNS. Sinon, liste vide.
  alarm_actions = var.alarm_email != "" ? [aws_sns_topic.alarms[0].arn] : []
}

# ─── Alarme 1 : Erreurs Lambda ────────────────────────────────────────────────
# Métrique "Errors" = exceptions non catchées dans le code Lambda
# Période 300s = on compte les erreurs sur une fenêtre de 5 minutes
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${local.prefix}-lambda-errors"
  alarm_description   = "Erreurs Lambda > ${var.lambda_error_threshold} sur 5 minutes"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = var.lambda_error_threshold
  evaluation_periods  = 1
  period              = 300
  statistic           = "Sum"

  namespace   = "AWS/Lambda"
  metric_name = "Errors"
  dimensions = {
    FunctionName = var.lambda_function_name
  }

  treat_missing_data = "notBreaching" # Pas de données = pas d'alarme (ex: Lambda au repos)
  alarm_actions      = local.alarm_actions
  ok_actions         = local.alarm_actions

  tags = local.common_tags
}

# ─── Alarme 2 : Durée Lambda (P95) ───────────────────────────────────────────
# P95 = 95% des invocations terminent dans ce délai
# Si P95 > seuil → problème de performance à investiguer
resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  alarm_name          = "${local.prefix}-lambda-duration"
  alarm_description   = "Durée Lambda P95 > ${var.lambda_duration_threshold_ms}ms"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = var.lambda_duration_threshold_ms
  evaluation_periods  = 2 # 2 périodes consécutives pour éviter les faux positifs
  period              = 300
  extended_statistic  = "p95"

  namespace   = "AWS/Lambda"
  metric_name = "Duration"
  dimensions = {
    FunctionName = var.lambda_function_name
  }

  treat_missing_data = "notBreaching"
  alarm_actions      = local.alarm_actions
  ok_actions         = local.alarm_actions

  tags = local.common_tags
}

# ─── Alarme 3 : API Gateway 5XX ──────────────────────────────────────────────
# 5XX = erreurs côté serveur (bug dans Lambda, timeout, etc.)
resource "aws_cloudwatch_metric_alarm" "api_5xx" {
  alarm_name          = "${local.prefix}-api-5xx"
  alarm_description   = "Erreurs 5XX API > ${var.api_5xx_threshold} sur 5 minutes"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = var.api_5xx_threshold
  evaluation_periods  = 1
  period              = 300
  statistic           = "Sum"

  namespace   = "AWS/ApiGateway"
  metric_name = "5XXError"
  dimensions = {
    ApiName  = var.api_gateway_name
    Stage    = var.api_gateway_stage
  }

  treat_missing_data = "notBreaching"
  alarm_actions      = local.alarm_actions
  ok_actions         = local.alarm_actions

  tags = local.common_tags
}

# ─── Alarme 4 : API Gateway 4XX ──────────────────────────────────────────────
# 4XX = erreurs côté client (401, 403, 404...)
# Un taux anormalement élevé peut indiquer une attaque ou un bug client
resource "aws_cloudwatch_metric_alarm" "api_4xx" {
  alarm_name          = "${local.prefix}-api-4xx"
  alarm_description   = "Erreurs 4XX API > ${var.api_4xx_threshold} sur 5 minutes"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = var.api_4xx_threshold
  evaluation_periods  = 1
  period              = 300
  statistic           = "Sum"

  namespace   = "AWS/ApiGateway"
  metric_name = "4XXError"
  dimensions = {
    ApiName = var.api_gateway_name
    Stage   = var.api_gateway_stage
  }

  treat_missing_data = "notBreaching"
  alarm_actions      = local.alarm_actions
  ok_actions         = local.alarm_actions

  tags = local.common_tags
}
