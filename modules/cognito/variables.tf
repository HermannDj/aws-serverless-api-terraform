variable "project" {
  description = "Nom du projet"
  type        = string
}

variable "environment" {
  description = "Environnement (dev, staging, prod)"
  type        = string
}

variable "allowed_oauth_flows" {
  description = "Flux OAuth autorisés pour le client"
  type        = list(string)
  default     = ["code"]
}

variable "allowed_oauth_scopes" {
  description = "Scopes OAuth autorisés"
  type        = list(string)
  default     = ["openid", "email", "profile"]
}

variable "callback_urls" {
  description = "URLs de callback après authentification (pour le flux code)"
  type        = list(string)
  default     = ["http://localhost:3000/callback"]
}

variable "logout_urls" {
  description = "URLs de déconnexion"
  type        = list(string)
  default     = ["http://localhost:3000/logout"]
}

variable "token_validity_hours" {
  description = "Durée de validité du token d'accès en heures"
  type        = number
  default     = 1
}

variable "refresh_token_validity_days" {
  description = "Durée de validité du refresh token en jours"
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags additionnels"
  type        = map(string)
  default     = {}
}
