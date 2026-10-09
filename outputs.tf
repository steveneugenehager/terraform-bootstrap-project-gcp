# ---------------------------------------------------------------------------
# Change History
# 2026-10-08 Steve Hager - v1.3 Added output "org_policy_service_account".

output "seed_project_id" {
  description = "ID of the seed project."
  value       = google_project.seed.project_id
}

output "state_bucket" {
  description = "Bucket holding Terraform state for every configuration."
  value       = google_storage_bucket.tfstate.name
}

output "terraform_service_account" {
  description = "Service account later configurations should impersonate."
  value       = google_service_account.terraform.email
}

output "org_policy_service_account" {
  description = "Impersonated by terraform-org-level-policy-gcp to manage org-level constraints. Holds roles/orgpolicy.policyAdmin at the org."
  value       = one(google_service_account.org_policy[*].email)
}

output "example_backend_block" {
  description = "Backend block for other configurations; change the prefix for each one."
  value       = <<-EOT
    terraform {
      backend "gcs" {
        bucket                      = "${google_storage_bucket.tfstate.name}"
        prefix                      = "DOMAIN/ENV/COMPONENT"
        impersonate_service_account = "${google_service_account.terraform.email}"
      }
    }
  EOT
}
