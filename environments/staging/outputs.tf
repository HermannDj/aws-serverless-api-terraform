output "api_invoke_url" {
  value = module.api_gateway.invoke_url
}

output "cognito_hosted_ui_url" {
  value = module.cognito.hosted_ui_url
}

output "cognito_client_id" {
  value = module.cognito.client_id
}

output "dynamodb_table_name" {
  value = module.dynamodb.table_name
}

output "lambda_function_name" {
  value = module.lambda.function_name
}
