variable "project" {
  description = "Nom du projet — préfixe dans tous les noms de ressources"
  type        = string
}

variable "environment" {
  description = "Environnement de déploiement"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment doit être dev, staging ou prod."
  }
}

variable "function_name" {
  description = "Nom court de la fonction (sans préfixe project/env)"
  type        = string
}

variable "description" {
  description = "Description lisible de ce que fait la Lambda"
  type        = string
  default     = ""
}

variable "handler" {
  description = "Point d'entrée : fichier.nom_de_fonction"
  type        = string
  default     = "handler.lambda_handler"
}

variable "runtime" {
  description = "Runtime Lambda (python3.12, nodejs20.x, etc.)"
  type        = string
  default     = "python3.12"
}

variable "source_dir" {
  description = "Chemin absolu vers le dossier contenant le code source Lambda"
  type        = string
}

variable "memory_size" {
  description = "RAM allouée en MB. Free Tier : 400 000 GB-secondes/mois"
  type        = number
  default     = 128

  validation {
    condition     = var.memory_size >= 128 && var.memory_size <= 10240
    error_message = "memory_size doit être entre 128 et 10240 MB."
  }
}

variable "timeout" {
  description = "Durée max d'exécution en secondes (1–900)"
  type        = number
  default     = 30

  validation {
    condition     = var.timeout >= 1 && var.timeout <= 900
    error_message = "timeout doit être entre 1 et 900 secondes."
  }
}

variable "log_retention_days" {
  description = "Rétention des logs CloudWatch en jours"
  type        = number
  default     = 7

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365], var.log_retention_days)
    error_message = "Valeur de rétention invalide pour CloudWatch."
  }
}

variable "environment_variables" {
  description = "Variables d'environnement à injecter dans la Lambda"
  type        = map(string)
  default     = {}
  sensitive   = false
}

variable "dynamodb_table_arns" {
  description = "ARNs des tables DynamoDB auxquelles cette Lambda a accès en CRUD"
  type        = list(string)
  default     = []
}

variable "api_gateway_execution_arn" {
  description = "ARN d'exécution de l'API Gateway (permet l'invocation). Laisser vide pour ignorer."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags supplémentaires à fusionner avec les tags du module"
  type        = map(string)
  default     = {}
}
