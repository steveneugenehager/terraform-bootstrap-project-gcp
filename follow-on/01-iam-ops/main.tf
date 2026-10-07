locals {
  folder_id = trimprefix(var.common_folder_id, "folders/")

  # APIs the provisioning automation needs inside its own project.
  # admin.googleapis.com     -> Admin SDK Directory API (users, groups, members)
  # cloudidentity            -> Cloud Identity Groups API (optional alternative for group membership)
  # iamcredentials           -> short-lived tokens via impersonation (no keys)
  project_services = [
    "admin.googleapis.com",
    "cloudidentity.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "serviceusage.googleapis.com",
    "logging.googleapis.com",
  ]
}

# --------------------------------------------------------------------------
# Project
# --------------------------------------------------------------------------

resource "random_id" "project_suffix" {
  byte_length = 2
}

resource "google_project" "identity" {
  name            = var.project_name
  project_id      = "${var.project_id_prefix}-${random_id.project_suffix.hex}"
  folder_id       = local.folder_id
  billing_account = var.billing_account_id
  labels          = var.labels

  # Don't create the legacy "default" network; this project has no workloads.
  auto_create_network = false

  # Guard against an accidental `terraform destroy` of an identity-critical project.
  deletion_policy = "PREVENT"
}

resource "google_project_service" "services" {
  for_each = toset(local.project_services)

  project            = google_project.identity.project_id
  service            = each.value
  disable_on_destroy = false
}

# --------------------------------------------------------------------------
# Provisioning service account (keyless)
# --------------------------------------------------------------------------

resource "google_service_account" "provisioner" {
  project      = google_project.identity.project_id
  account_id   = var.service_account_id
  display_name = "User provisioning automation"
  description  = "Creates users in ${var.org_domain} and adds them to existing security groups. Holds Workspace User Management Admin + Groups Admin. Use via impersonation only; no keys."

  depends_on = [google_project_service.services]
}

# Who may act as the SA. Token creator on the SA itself, not the project,
# so impersonation rights don't leak to any other SA created here later.
resource "google_service_account_iam_member" "impersonators" {
  for_each = toset(var.impersonators)

  service_account_id = google_service_account.provisioner.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = each.value
}

# Lets the SA be the quota/billing project when it calls the Admin SDK.
resource "google_project_iam_member" "provisioner_service_usage" {
  project = google_project.identity.project_id
  role    = "roles/serviceusage.serviceUsageConsumer"
  member  = google_service_account.provisioner.member
}

# --------------------------------------------------------------------------
# Workspace admin roles for the SA
# --------------------------------------------------------------------------
# Workspace lets you assign admin roles directly to a service account,
# keyed by its numeric unique ID. With these roles the SA calls the Admin SDK
# as itself — no domain-wide delegation and no impersonating a human admin.

data "googleworkspace_role" "admin_roles" {
  for_each = var.assign_workspace_roles ? toset(var.workspace_admin_roles) : toset([])

  name = each.value
}

resource "googleworkspace_role_assignment" "provisioner" {
  for_each = data.googleworkspace_role.admin_roles

  role_id     = each.value.id
  assigned_to = google_service_account.provisioner.unique_id
  scope_type  = "CUSTOMER"
}
