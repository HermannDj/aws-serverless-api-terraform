# ┌─────────────────────────────────────────────────────────────────────────────┐
# │  BACKEND S3 — Terraform Remote State                                        │
# │                                                                             │
# │  POURQUOI un remote state ?                                                 │
# │    • Le state local (terraform.tfstate) ne convient qu'à une seule         │
# │      personne. En équipe ou en CI/CD, il faut un state partagé.            │
# │    • S3 = stockage du state                                                 │
# │    • DynamoDB = verrou (évite 2 apply simultanés qui corrompraient le state)│
# │                                                                             │
# │  AVANT de faire terraform init ici, tu dois bootstrapper l'infrastructure  │
# │  S3/DynamoDB. Lance :                                                       │
# │    cd bootstrap && terraform init && terraform apply                        │
# │                                                                             │
# │  Remplace les valeurs YOUR_* par celles créées par le bootstrap.           │
# └─────────────────────────────────────────────────────────────────────────────┘

terraform {
  backend "s3" {
    bucket         = "serverless-api-terraform-state-e503a9f9" # Bucket créé par bootstrap/
    key            = "dev/terraform.tfstate"                   # Chemin dans le bucket
    region         = "ca-central-1"                            # Ta région AWS
    encrypt        = true                                      # Chiffrement du state au repos
    dynamodb_table = "serverless-api-terraform-locks"          # Table créée par bootstrap/
  }
}
