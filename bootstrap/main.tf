# ┌─────────────────────────────────────────────────────────────────────────────┐
# │  BOOTSTRAP — Infrastructure du state Terraform                             │
# │                                                                             │
# │  Ce fichier doit être appliqué UNE SEULE FOIS avant tout le reste.        │
# │  Il crée le "poulet avant l'œuf" :                                         │
# │    → Le bucket S3 qui stockera le state Terraform de tous les envs         │
# │    → La table DynamoDB qui servira de verrou                               │
# │                                                                             │
# │  UTILISATION :                                                              │
# │    cd bootstrap/                                                            │
# │    terraform init      # State LOCAL ici (pas de remote state pour le boot)│
# │    terraform apply                                                          │
# │    # Note le nom du bucket affiché en output                               │
# │    # Remplace YOUR_PROJECT_NAME dans environments/*/backend.tf             │
# └─────────────────────────────────────────────────────────────────────────────┘

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
  # Pas de backend ici → state LOCAL dans bootstrap/terraform.tfstate
  # Ne commite JAMAIS ce fichier dans git (il contient des infos sensibles)
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform-bootstrap"
    }
  }
}

variable "aws_region" {
  type    = string
  default = "ca-central-1"
}

variable "project" {
  type        = string
  description = "Nom du projet — utilisé dans le nom du bucket"
}

# ─── Bucket S3 : stockage du Terraform state ─────────────────────────────────
# Les noms de bucket S3 sont GLOBALEMENT uniques → on ajoute un suffix aléatoire
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "terraform_state" {
  # Format : myproject-terraform-state-a1b2c3d4
  bucket = "${var.project}-terraform-state-${random_id.bucket_suffix.hex}"

  # PROTECTION : empêche la suppression accidentelle du state
  lifecycle {
    prevent_destroy = true
  }
}

# Versioning : garde l'historique des states → peut rollback en cas de corruption
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Chiffrement au repos obligatoire pour les secrets dans le state
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256" # Gratuit — KMS coûterait $1/mois
    }
  }
}

# Bloquer tout accès public au bucket (sécurité critique)
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket                  = aws_s3_bucket.terraform_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ─── Table DynamoDB : verrou du state ─────────────────────────────────────────
# Terraform acquiert un verrou dans cette table pendant plan/apply.
# Empêche 2 personnes d'appliquer simultanément → corruption du state.
# La clé DOIT s'appeler "LockID" (convention Terraform).
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "${var.project}-terraform-locks"
  billing_mode = "PAY_PER_REQUEST" # Très peu d'écritures → coût quasi-nul
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

# ─── Outputs ──────────────────────────────────────────────────────────────────
output "state_bucket_name" {
  description = "Copie ce nom dans environments/*/backend.tf (remplace YOUR_PROJECT_NAME)"
  value       = aws_s3_bucket.terraform_state.id
}

output "lock_table_name" {
  description = "Copie ce nom dans environments/*/backend.tf"
  value       = aws_dynamodb_table.terraform_locks.name
}
