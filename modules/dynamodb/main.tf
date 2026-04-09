# ┌─────────────────────────────────────────────────────────────────────────────┐
# │  MODULE : dynamodb                                                          │
# │                                                                             │
# │  IMPORTANT — Free Tier DynamoDB :                                           │
# │    • Always-free : 25 WCU + 25 RCU provisionnés (pour TOUT le compte)      │
# │    • Always-free : 25 GB de stockage                                        │
# │    • PAY_PER_REQUEST N'EST PAS dans l'always-free tier → on utilise        │
# │      PROVISIONED avec des valeurs basses (5/5) pour rester gratuit         │
# └─────────────────────────────────────────────────────────────────────────────┘

locals {
  table_name  = "${var.project}-${var.environment}-${var.table_name}"
  common_tags = merge(var.tags, { Module = "dynamodb" })
}

resource "aws_dynamodb_table" "this" {
  name         = local.table_name
  billing_mode = "PROVISIONED"

  # 5 RCU = ~5 lectures fortement consistantes/seconde sur un item de 4KB
  # 5 WCU = ~5 écritures/seconde sur un item de 1KB
  # Largement suffisant pour un projet portfolio, et dans les 25/25 gratuits
  read_capacity  = var.read_capacity
  write_capacity = var.write_capacity

  # Clé primaire
  hash_key  = var.hash_key
  range_key = var.range_key != "" ? var.range_key : null

  # DynamoDB est "schemaless" MAIS les attributs utilisés comme clés
  # doivent être déclarés ici (seulement les clés, pas tous les champs)
  dynamic "attribute" {
    for_each = var.attributes
    content {
      name = attribute.value.name
      type = attribute.value.type
    }
  }

  # TTL : expiration automatique des items sans coût supplémentaire
  # Utile pour des sessions, des tokens temporaires, du cache
  ttl {
    attribute_name = var.ttl_attribute
    enabled        = var.ttl_attribute != "" ? true : false
  }

  # PITR : restauration à n'importe quel moment dans les 35 derniers jours
  # Désactivé en dev pour éviter tout coût, activé en prod
  point_in_time_recovery {
    enabled = var.enable_pitr
  }

  # Chiffrement au repos avec la clé gérée par AWS (GRATUIT)
  # Les clés KMS personnalisées coûtent $1/mois → on utilise AWS_OWNED_KMS
  server_side_encryption {
    enabled     = true
    kms_key_arn = null # null = AWS_OWNED_KMS (gratuit)
  }

  # GSIs : Global Secondary Indexes
  # Permettent de requêter par un attribut autre que la clé primaire
  dynamic "global_secondary_index" {
    for_each = var.global_secondary_indexes
    content {
      name            = global_secondary_index.value.name
      hash_key        = global_secondary_index.value.hash_key
      range_key       = lookup(global_secondary_index.value, "range_key", null)
      projection_type = global_secondary_index.value.projection_type
      read_capacity   = global_secondary_index.value.read_capacity
      write_capacity  = global_secondary_index.value.write_capacity
    }
  }

  tags = local.common_tags
}
