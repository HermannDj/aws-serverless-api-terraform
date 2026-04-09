variable "project" {
  description = "Nom du projet"
  type        = string
}

variable "environment" {
  description = "Environnement (dev, staging, prod)"
  type        = string
}

variable "lambda_function_name" {
  description = "Nom de la fonction Lambda à surveiller"
  type        = string
}

variable "api_gateway_name" {
  description = "Nom de l'API Gateway à surveiller"
  type        = string
}

variable "api_gateway_stage" {
  description = "Nom du stage API Gateway"
  type        = string
}

variable "alarm_email" {
  description = "Email pour les notifications d'alarme CloudWatch (laisser vide pour désactiver)"
  type        = string
  default     = ""
}

variable "lambda_error_threshold" {
  description = "Nombre d'erreurs Lambda par 5min avant alarme"
  type        = number
  default     = 5
}

variable "lambda_duration_threshold_ms" {
  description = "Durée max Lambda en ms avant alarme (p95)"
  type        = number
  default     = 5000
}

variable "api_5xx_threshold" {
  description = "Nombre d'erreurs 5XX API Gateway par 5min avant alarme"
  type        = number
  default     = 10
}

variable "api_4xx_threshold" {
  description = "Nombre d'erreurs 4XX API Gateway par 5min avant alarme"
  type        = number
  default     = 50
}

variable "tags" {
  description = "Tags additionnels"
  type        = map(string)
  default     = {}
}
