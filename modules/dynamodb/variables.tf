variable "project" {
  description = "Nom du projet"
  type        = string
}

variable "environment" {
  description = "Environnement (dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment doit être dev, staging ou prod."
  }
}

variable "table_name" {
  description = "Nom court de la table (sans préfixe project/env)"
  type        = string
}

variable "hash_key" {
  description = "Nom de la partition key (clé primaire)"
  type        = string
  default     = "id"
}

variable "range_key" {
  description = "Nom de la sort key (clé de tri). Laisser vide si non utilisée."
  type        = string
  default     = ""
}

variable "attributes" {
  description = "Définition des attributs utilisés comme clés (hash_key, range_key, index keys)"
  type = list(object({
    name = string
    type = string # "S" = String, "N" = Number, "B" = Binary
  }))
  default = [
    { name = "id", type = "S" }
  ]
}

variable "read_capacity" {
  description = "Unités de lecture provisionnées. Free Tier always-free : 25 RCU total."
  type        = number
  default     = 5

  validation {
    condition     = var.read_capacity >= 1 && var.read_capacity <= 25
    error_message = "Garder read_capacity <= 25 pour rester dans le Free Tier."
  }
}

variable "write_capacity" {
  description = "Unités d'écriture provisionnées. Free Tier always-free : 25 WCU total."
  type        = number
  default     = 5

  validation {
    condition     = var.write_capacity >= 1 && var.write_capacity <= 25
    error_message = "Garder write_capacity <= 25 pour rester dans le Free Tier."
  }
}

variable "ttl_attribute" {
  description = "Nom de l'attribut TTL (expiration automatique des items). Laisser vide pour désactiver."
  type        = string
  default     = "expires_at"
}

variable "enable_pitr" {
  description = "Activer le Point-In-Time Recovery (recommandé en prod, coût négligeable en dev)"
  type        = bool
  default     = false
}

variable "global_secondary_indexes" {
  description = "GSIs optionnels pour des patterns de requête additionnels"
  type = list(object({
    name            = string
    hash_key        = string
    range_key       = string
    projection_type = string
    read_capacity   = number
    write_capacity  = number
  }))
  default = []
}

variable "tags" {
  description = "Tags additionnels"
  type        = map(string)
  default     = {}
}
