output "lambda_errors_alarm_arn" {
  description = "ARN de l'alarme erreurs Lambda"
  value       = aws_cloudwatch_metric_alarm.lambda_errors.arn
}

output "lambda_duration_alarm_arn" {
  description = "ARN de l'alarme durée Lambda"
  value       = aws_cloudwatch_metric_alarm.lambda_duration.arn
}

output "api_5xx_alarm_arn" {
  description = "ARN de l'alarme 5XX API Gateway"
  value       = aws_cloudwatch_metric_alarm.api_5xx.arn
}

output "api_4xx_alarm_arn" {
  description = "ARN de l'alarme 4XX API Gateway"
  value       = aws_cloudwatch_metric_alarm.api_4xx.arn
}

output "sns_topic_arn" {
  description = "ARN du topic SNS pour les notifications (null si alarm_email non fourni)"
  value       = length(aws_sns_topic.alarms) > 0 ? aws_sns_topic.alarms[0].arn : null
}
