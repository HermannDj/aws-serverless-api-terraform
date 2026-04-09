variable "project" {
  description = "Nom du projet"
  type        = string
}

variable "environment" {
  description = "Environnement (dev, staging, prod)"
  type        = string
}

variable "lambda_invoke_arn" {
  description = "ARN d'invocation de la Lambda (output du module lambda)"
  type        = string
}

variable "cognito_user_pool_arn" {
  description = "ARN du User Pool Cognito (output du module cognito)"
  type        = string
}

variable "throttling_burst_limit" {
  description = "Nombre max de requêtes simultanées (burst)"
  type        = number
  default     = 50
}

variable "throttling_rate_limit" {
  description = "Nombre max de requêtes par seconde (steady state)"
  type        = number
  default     = 100
}

variable "tags" {
  description = "Tags additionnels"
  type        = map(string)
  default     = {}
}
