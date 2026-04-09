# ┌─────────────────────────────────────────────────────────────────────────────┐
# │  MODULE : cognito                                                           │
# │                                                                             │
# │  Cognito Free Tier (Always Free) :                                          │
# │    • 50 000 Monthly Active Users (MAU)                                      │
# │    • Les fonctionnalités basiques (email/password) sont gratuites           │
# │                                                                             │
# │  Ce module crée :                                                           │
# │    1. User Pool : le "répertoire" des utilisateurs                          │
# │    2. User Pool Domain : l'URL hébergée pour la connexion                   │
# │    3. User Pool Client : l'application qui consomme le pool                 │
# └─────────────────────────────────────────────────────────────────────────────┘

locals {
  pool_name   = "${var.project}-${var.environment}-users"
  common_tags = merge(var.tags, { Module = "cognito" })
}

# ─── 1. User Pool ─────────────────────────────────────────────────────────────
resource "aws_cognito_user_pool" "this" {
  name = local.pool_name

  # Les utilisateurs se connectent avec leur email (plus user-friendly qu'un username)
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  # Politique de mots de passe : suffisamment forte pour la prod
  password_policy {
    minimum_length                   = 8
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = false
    temporary_password_validity_days = 7
  }

  # MFA désactivé pour simplifier le dev (activer en prod)
  mfa_configuration = "OFF"

  # Configuration de vérification par email
  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
    email_subject        = "Votre code de vérification ${var.project}"
    email_message        = "Votre code de vérification est {####}"
  }

  # Schéma des attributs utilisateur
  # On garde le minimum — Cognito crée email, sub, etc. automatiquement
  schema {
    name                     = "email"
    attribute_data_type      = "String"
    required                 = true
    mutable                  = true
    developer_only_attribute = false

    string_attribute_constraints {
      min_length = 0
      max_length = 2048
    }
  }

  # Politique de suppression de compte utilisateur
  admin_create_user_config {
    allow_admin_create_user_only = false
  }

  # Tags — Cognito utilise une syntaxe différente des autres services
  user_pool_add_ons {
    advanced_security_mode = "OFF" # "ENFORCED" coûte ~$0.05/MAU → désactivé
  }

  tags = local.common_tags
}

# ─── 2. User Pool Domain ──────────────────────────────────────────────────────
# Crée l'URL Cognito Hosted UI : https://{domain}.auth.{region}.amazoncognito.com
# Nécessaire pour le flux OAuth2 Authorization Code
resource "aws_cognito_user_pool_domain" "this" {
  domain       = "${var.project}-${var.environment}-auth"
  user_pool_id = aws_cognito_user_pool.this.id
}

# ─── 3. User Pool Client ──────────────────────────────────────────────────────
# Le "client" = l'application qui utilise Cognito pour authentifier
# client_credentials_flow = false → on utilise Authorization Code (plus sécurisé)
resource "aws_cognito_user_pool_client" "this" {
  name         = "${var.project}-${var.environment}-client"
  user_pool_id = aws_cognito_user_pool.this.id

  # PKCE + Authorization Code Flow — recommandé pour les SPA et apps mobiles
  allowed_oauth_flows                  = var.allowed_oauth_flows
  allowed_oauth_scopes                 = var.allowed_oauth_scopes
  allowed_oauth_flows_user_pool_client = true
  supported_identity_providers         = ["COGNITO"]

  callback_urls = var.callback_urls
  logout_urls   = var.logout_urls

  # Durée de validité des tokens
  access_token_validity  = var.token_validity_hours
  id_token_validity      = var.token_validity_hours
  refresh_token_validity = var.refresh_token_validity_days

  # PKCE = Proof Key for Code Exchange
  # Protection contre l'interception du code d'autorisation
  prevent_user_existence_errors = "ENABLED"

  # Pas de client_secret → application publique (SPA, mobile)
  generate_secret = false

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",      # Auth sécurisée (SRP = Secure Remote Password)
    "ALLOW_USER_PASSWORD_AUTH", # Auth directe user/password (utile pour les tests CLI)
    "ALLOW_REFRESH_TOKEN_AUTH", # Renouvellement du token
  ]
}
