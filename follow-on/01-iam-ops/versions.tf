# ---------------------------------------------------------------------------
# Change History
# 2026-10-07 Steve Hager - v1.0 Initial version
# 2026-10-07 Steve Hager - v1.1 added time to required_providers.

terraform {
  required_version = ">= 1.6"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    googleworkspace = {
      source  = "hashicorp/googleworkspace"
      version = "~> 0.7"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    time = { 
      source = "hashicorp/time"
      version = "~> 0.12" 
    }
  }

  # State lives in the bucket created by the bootstrap project.
  # Supply bucket/prefix at init time:
  #   terraform init -backend-config=backend.hcl
  backend "gcs" {}
}

provider "google" {
  # Runs as admin@stevenhager.com via ADC (or impersonates the bootstrap
  # Terraform SA if you set var.terraform_impersonate_sa).
  impersonate_service_account = var.terraform_impersonate_sa
  billing_project             = var.quota_project
  user_project_override       = var.quota_project != null
}

provider "googleworkspace" {
  customer_id = var.workspace_customer_id

  # Only these scopes are needed to look up and assign admin roles.
  oauth_scopes = [
    "https://www.googleapis.com/auth/admin.directory.rolemanagement",
  ]
}
