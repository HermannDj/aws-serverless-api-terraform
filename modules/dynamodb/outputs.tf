output "table_name" {
  description = "Nom de la table DynamoDB"
  value       = aws_dynamodb_table.this.name
}

output "table_arn" {
  description = "ARN de la table DynamoDB (utilisé dans les policies IAM)"
  value       = aws_dynamodb_table.this.arn
}

output "table_id" {
  description = "ID de la table (identique au nom pour DynamoDB)"
  value       = aws_dynamodb_table.this.id
}

output "stream_arn" {
  description = "ARN du DynamoDB Stream (null si les streams ne sont pas activés)"
  value       = aws_dynamodb_table.this.stream_arn
}
