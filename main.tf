# ---------------------------------------------------------------------------
# Seed project: holds Terraform state and the identity Terraform runs as.
# ---------------------------------------------------------------------------

resource "random_id" "suffix" {
  byte_length = 2
}

resource "google_project" "seed" {
  name            = "${var.project_prefix}-seed"
  project_id      = "${var.project_prefix}-seed-${random_id.suffix.hex}"
  billing_account = var.billing_account

  # A project can have one parent: a folder, the organization, or neither.
  folder_id = var.folder_id
  org_id    = var.folder_id == null ? var.org_id : null

  # Losing this project means losing all Terraform state. Keep it protected;
  # change to "DELETE" deliberately if you ever need to tear it down.
  deletion_policy = "PREVENT"

  labels = {
    purpose    = "terraform-bootstrap"
    managed_by = "terraform"
  }
}

locals {
  seed_apis = [
    "cloudresourcemanager.googleapis.com", # create and manage projects
    "cloudbilling.googleapis.com",         # link projects to billing
    "iam.googleapis.com",                  # service accounts and roles
    "iamcredentials.googleapis.com",       # service account impersonation
    "serviceusage.googleapis.com",         # enable APIs in other projects
    "storage.googleapis.com",              # the state bucket
  ]
}

resource "google_project_service" "seed" {
  for_each = toset(local.seed_apis)

  project            = google_project.seed.project_id
  service            = each.value
  disable_on_destroy = false
}

# ---------------------------------------------------------------------------
# State bucket: shared by every later configuration, each under its own prefix.
# ---------------------------------------------------------------------------

resource "google_storage_bucket" "tfstate" {
  project  = google_project.seed.project_id
  name     = "${google_project.seed.project_id}-tfstate"
  location = var.state_bucket_location

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false

  # Every write keeps the previous version, so a corrupted or bad state
  # can be restored.
  versioning {
    enabled = true
  }

  # Trim old versions so the history doesn't grow forever.
  lifecycle_rule {
    condition {
      num_newer_versions = var.state_versions_to_keep
      with_state         = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }

  labels = {
    purpose = "terraform-state"
  }

  depends_on = [google_project_service.seed]
}

# ---------------------------------------------------------------------------
# Terraform service account: later configurations run as this identity,
# via impersonation, so no key files are ever downloaded.
# ---------------------------------------------------------------------------

resource "google_service_account" "terraform" {
  project      = google_project.seed.project_id
  account_id   = "terraform"
  display_name = "Terraform automation"

  depends_on = [google_project_service.seed]
}

# Read and write state in the bucket.
resource "google_storage_bucket_iam_member" "terraform_state" {
  bucket = google_storage_bucket.tfstate.name
  role   = "roles/storage.objectAdmin"
  member = google_service_account.terraform.member
}

# Let named administrators act as the service account.
resource "google_service_account_iam_member" "admins_impersonate" {
  for_each = toset(var.terraform_admins)

  service_account_id = google_service_account.terraform.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = each.value
}

# Let the service account link new projects to the billing account.
resource "google_billing_account_iam_member" "terraform_billing_user" {
  count = var.grant_billing_user ? 1 : 0

  billing_account_id = var.billing_account
  role               = "roles/billing.user"
  member             = google_service_account.terraform.member
}

# With an organization, let the service account create projects and folders.
# (Without one, a service account can't create parentless projects.)
resource "google_organization_iam_member" "terraform_org" {
  for_each = var.org_id == null ? toset([]) : toset([
    "roles/resourcemanager.projectCreator",
    "roles/resourcemanager.folderAdmin",
  ])

  org_id = var.org_id
  role   = each.value
  member = google_service_account.terraform.member
}
