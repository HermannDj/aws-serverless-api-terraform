output "api_id" {
  description = "ID de l'API REST Gateway"
  value       = aws_api_gateway_rest_api.this.id
}

output "api_arn" {
  description = "ARN de l'API REST Gateway"
  value       = aws_api_gateway_rest_api.this.arn
}

output "execution_arn" {
  description = "ARN d'exécution — utilisé pour la permission Lambda (aws_lambda_permission)"
  value       = aws_api_gateway_rest_api.this.execution_arn
}

output "invoke_url" {
  description = "URL publique de l'API : https://{id}.execute-api.{region}.amazonaws.com/{env}"
  value       = aws_api_gateway_stage.this.invoke_url
}

output "stage_name" {
  description = "Nom du stage actif"
  value       = aws_api_gateway_stage.this.stage_name
}

output "access_log_group_name" {
  description = "Nom du log group CloudWatch pour l'access logging"
  value       = aws_cloudwatch_log_group.api_access.name
}
