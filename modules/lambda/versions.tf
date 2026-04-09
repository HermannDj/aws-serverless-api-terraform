terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      # "archive" est un provider spécial : il crée des fichiers ZIP
      # sans appel AWS. Terraform le gère localement.
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}
