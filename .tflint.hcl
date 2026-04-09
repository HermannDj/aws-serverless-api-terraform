# ─── Configuration TFLint ─────────────────────────────────────────────────────
# TFLint = linter Terraform qui vérifie les bonnes pratiques
# Le plugin AWS vérifie les valeurs invalides (ex: type d'instance inexistant)

plugin "aws" {
  enabled = true
  version = "0.30.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

# ─── Règles activées ──────────────────────────────────────────────────────────

# Interdit les variables sans type déclaré
rule "terraform_typed_variables" {
  enabled = true
}

# Interdit les modules sans version source fixée
rule "terraform_module_pinned_source" {
  enabled = true
  style   = "flexible" # "flexible" accepte "../local/path"
}

# Oblige à documenter les variables et outputs
rule "terraform_documented_variables" {
  enabled = true
}

rule "terraform_documented_outputs" {
  enabled = true
}

# Naming conventions
rule "terraform_naming_convention" {
  enabled = true

  variable {
    format = "snake_case"
  }

  output {
    format = "snake_case"
  }

  resource {
    format = "snake_case"
  }
}

# Interdit les déprecated arguments AWS
rule "aws_resource_missing_tags" {
  enabled = false # Désactivé : on gère les tags via default_tags du provider
}
