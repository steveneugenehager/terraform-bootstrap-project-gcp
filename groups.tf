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

#variable "bootstrap_project_id" {
#  type = string
#}

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
    # "gcp-billing-admins" = { description = "...", org_roles = [...] }
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
}

# --- org-level IAM bindings -------------------------------------------
resource "google_organization_iam_member" "admin_groups" {
  for_each = local.admin_group_bindings

  org_id = data.google_organization.org.org_id
  role   = each.value.role
  member = "group:${google_cloud_identity_group.admin[each.value.group].group_key[0].id}"
}
