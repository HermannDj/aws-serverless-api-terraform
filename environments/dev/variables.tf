variable "aws_region" {
  description = "Région AWS de déploiement"
  type        = string
  default     = "ca-central-1"
}

variable "project" {
  description = "Nom du projet (utilisé dans tous les noms de ressources)"
  type        = string
}

variable "owner" {
  description = "Propriétaire du projet (ton nom ou email)"
  type        = string
}

variable "cost_center" {
  description = "Centre de coût pour la facturation"
  type        = string
  default     = "personal"
}

variable "alarm_email" {
  description = "Email pour les alarmes CloudWatch. Laisser vide pour désactiver."
  type        = string
  default     = ""
}

# trigger CI
