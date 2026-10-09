# ---------------------------------------------------------------------------
# Org-policy service account: used by terraform-org-level-policy-gcp.
# Kept separate from the general "terraform" SA so org-wide policy rights
# aren't held by the identity every other configuration runs as.
# ---------------------------------------------------------------------------
# Change History
# 2026-10-08 Steve Hager - v1.0 Created to provision an SA specifically for
#                                 maintaining organization-level policies.

resource "google_service_account" "org_policy" {
  count = var.org_id == null ? 0 : 1

  project      = google_project.seed.project_id
  account_id   = "tf-org-policy-admin"
  display_name = "Terraform organization policy automation"

  depends_on = [google_project_service.seed]
}

# Manage organization policies.
resource "google_organization_iam_member" "org_policy_admin" {
  count = var.org_id == null ? 0 : 1

  org_id = var.org_id
  role   = "roles/orgpolicy.policyAdmin"
  member = google_service_account.org_policy[0].member
}

# Use the seed project as the quota/billing project for API calls.
resource "google_project_iam_member" "org_policy_usage_consumer" {
  count = var.org_id == null ? 0 : 1

  project = google_project.seed.project_id
  role    = "roles/serviceusage.serviceUsageConsumer"
  member  = google_service_account.org_policy[0].member
}

# Read and write its state in the shared bucket.
resource "google_storage_bucket_iam_member" "org_policy_state" {
  count = var.org_id == null ? 0 : 1

  bucket = google_storage_bucket.tfstate.name
  role   = "roles/storage.objectAdmin"
  member = google_service_account.org_policy[0].member
}

# Let named administrators impersonate it.
resource "google_service_account_iam_member" "org_policy_impersonate" {
  for_each = var.org_id == null ? toset([]) : toset(var.terraform_admins)

  service_account_id = google_service_account.org_policy[0].name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = each.value
}
