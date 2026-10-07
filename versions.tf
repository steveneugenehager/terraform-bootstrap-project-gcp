# Change History
# 2026-10-07 Steve Hager - v1.1 Added terraform.required_providers.time
terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }

  # Step 1: leave this commented out; the first apply uses local state.
  # Step 2: after the first apply, uncomment, fill in the bucket from the
  #         outputs, and run: terraform init -migrate-state
  #
#  backend "gcs" {
#    bucket = "shv-cld-admn-btstrp-4329-tfstate"
#    prefix = "bootstrap"
#  }
}

provider "google" {
  region = var.region
}
