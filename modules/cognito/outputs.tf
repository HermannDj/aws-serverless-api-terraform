output "user_pool_id" {
  description = "ID du User Pool Cognito"
  value       = aws_cognito_user_pool.this.id
}

output "user_pool_arn" {
  description = "ARN du User Pool Cognito (utilisé par l'authorizer API Gateway)"
  value       = aws_cognito_user_pool.this.arn
}

output "user_pool_endpoint" {
  description = "Endpoint du User Pool (utilisé pour valider les tokens JWT)"
  value       = aws_cognito_user_pool.this.endpoint
}

output "client_id" {
  description = "ID du client (à configurer dans l'application front-end)"
  value       = aws_cognito_user_pool_client.this.id
}

output "domain" {
  description = "Domaine de la Hosted UI Cognito"
  value       = aws_cognito_user_pool_domain.this.domain
}

output "hosted_ui_url" {
  description = "URL complète de la Hosted UI pour la connexion"
  value       = "https://${aws_cognito_user_pool_domain.this.domain}.auth.${data.aws_region.current.name}.amazoncognito.com"
}

data "aws_region" "current" {}
