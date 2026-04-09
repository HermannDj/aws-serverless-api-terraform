# Les outputs d'un module = ce que les autres modules peuvent utiliser.
# Ex : api-gateway a besoin de invoke_arn pour savoir où envoyer les requêtes.

output "function_arn" {
  description = "ARN complet de la fonction Lambda"
  value       = aws_lambda_function.this.arn
}

output "function_name" {
  description = "Nom de la fonction Lambda"
  value       = aws_lambda_function.this.function_name
}

output "invoke_arn" {
  description = "ARN d'invocation utilisé par API Gateway (format différent de function_arn)"
  value       = aws_lambda_function.this.invoke_arn
}

output "role_arn" {
  description = "ARN du rôle IAM d'exécution"
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "Nom du rôle IAM d'exécution"
  value       = aws_iam_role.this.name
}

output "log_group_name" {
  description = "Nom du log group CloudWatch"
  value       = aws_cloudwatch_log_group.this.name
}

output "log_group_arn" {
  description = "ARN du log group CloudWatch"
  value       = aws_cloudwatch_log_group.this.arn
}
