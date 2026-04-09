# Ces outputs s'affichent après un `terraform apply` réussi.
# Très utile pour avoir immédiatement les infos nécessaires au test.

output "api_invoke_url" {
  description = "URL publique de l'API — copie cette URL pour tester avec curl ou Postman"
  value       = module.api_gateway.invoke_url
}

output "cognito_hosted_ui_url" {
  description = "URL de la Hosted UI Cognito pour créer un compte et se connecter"
  value       = module.cognito.hosted_ui_url
}

output "cognito_client_id" {
  description = "Client ID Cognito à utiliser dans l'application front-end"
  value       = module.cognito.client_id
}

output "cognito_user_pool_id" {
  description = "ID du User Pool Cognito"
  value       = module.cognito.user_pool_id
}

output "dynamodb_table_name" {
  description = "Nom de la table DynamoDB"
  value       = module.dynamodb.table_name
}

output "lambda_function_name" {
  description = "Nom de la fonction Lambda"
  value       = module.lambda.function_name
}

output "lambda_log_group" {
  description = "Log group CloudWatch — pour voir les logs Lambda"
  value       = module.lambda.log_group_name
}
