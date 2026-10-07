# Change History
# 2026-10-06 Steve Hager - v1.0 Piloting with only gcp-organization-admins/
# 2026-10-06 Steve Hager - v1.1 Adding the rest of the recommended org-level groups and bindings.
# 2026-10-07 Steve Hager - v1.2 Adding a depends on sleep (time_sleep.seed_apis_propagation) 
# --- inputs -----------------------------------------------------------
variable "org_domain" {
  type    = string
  default = null
}

# Dedicated provider for Cloud Identity calls, billed to the seed project
provider "google" {
  alias                 = "identity"
  billing_project       = google_project.seed.project_id
  user_project_override = true
}

# Looks up the org ID and Workspace customer ID from the domain
data "google_organization" "org" {
  domain = var.org_domain
}

# --- group definitions ------------------------------------------------
locals {
  admin_groups = {
    "gcp-organization-admins" = {
      description = "Org administrators: hierarchy, project creation, org policy"
      org_roles = [
        "roles/resourcemanager.organizationAdmin",
        "roles/resourcemanager.folderAdmin",
        "roles/resourcemanager.projectCreator",
        "roles/orgpolicy.policyAdmin",
        "roles/billing.user",
      ]
    }
    "gcp-billing-admins" = {
      description = "Billing administrators: billing accounts, budgets, payments"
      org_roles = [
        "roles/billing.admin",
        "roles/billing.creator",
        "roles/resourcemanager.organizationViewer",
      ]
    }

    "gcp-billing-viewers" = {
      description = "Read-only access to billing accounts and spend"
      org_roles = [
        "roles/billing.viewer",
      ]
    }

    "gcp-security-admins" = {
      description = "Security posture: IAM review, Security Command Center, audit logs"
      org_roles = [
        "roles/iam.securityReviewer",
        "roles/iam.organizationRoleViewer",
        "roles/securitycenter.admin",
        "roles/resourcemanager.folderIamAdmin",
        "roles/logging.privateLogViewer",
        "roles/logging.configWriter",
        "roles/compute.viewer",
        "roles/container.viewer",
      ]
    }

    "gcp-network-admins" = {
      description = "Networking: Shared VPC, firewall rules, routes, connectivity"
      org_roles = [
        "roles/compute.networkAdmin",
        "roles/compute.xpnAdmin",
        "roles/compute.securityAdmin",
        "roles/resourcemanager.folderViewer",
      ]
    }

    "gcp-logging-admins" = {
      description = "Logging configuration: sinks, buckets, exclusions"
      org_roles = [
        "roles/logging.admin",
      ]
    }

    "gcp-logging-viewers" = {
      description = "Read-only access to logs (excluding Data Access logs)"
      org_roles = [
        "roles/logging.viewer",
      ]
    }

    "gcp-monitoring-admins" = {
      description = "Monitoring: dashboards, alerting policies, uptime checks"
      org_roles = [
        "roles/monitoring.admin",
      ]
    }
  }

  # flatten group -> roles into one map entry per binding
  admin_group_bindings = merge([
    for name, g in local.admin_groups : {
      for role in g.org_roles : "${name}|${role}" => { group = name, role = role }
    }
  ]...)
}

# --- groups -----------------------------------------------------------
resource "google_cloud_identity_group" "admin" {
  provider = google.identity
  for_each = local.admin_groups

  parent       = "customers/${data.google_organization.org.directory_customer_id}"
  display_name = each.key
  description  = each.value.description

  group_key {
    id = "${each.key}@${var.org_domain}"
  }

  labels = {
    "cloudidentity.googleapis.com/groups.discussion_forum" = ""
    "cloudidentity.googleapis.com/groups.security"         = ""
  }

  initial_group_config = "WITH_INITIAL_OWNER"
  depends_on           = [time_sleep.seed_apis_propagation]
}

# --- org-level IAM bindings -------------------------------------------
resource "google_organization_iam_member" "admin_groups" {
  for_each = local.admin_group_bindings

  org_id = data.google_organization.org.org_id
  role   = each.value.role
  member = "group:${google_cloud_identity_group.admin[each.value.group].group_key[0].id}"
}
