# ---------------------------------------------------------------------------
# Change History
# 2026-10-07 Steve Hager - v1.0 Initial version

variable "org_domain" {
  description = "Primary Workspace / Cloud Identity domain."
  type        = string
  default     = "stevenhager.com"
}

variable "common_folder_id" {
  description = "ID of the existing 'common' folder, in the form folders/123456789012 or just the number."
  type        = string
}

variable "billing_account_id" {
  description = "Billing account to attach to the new project (XXXXXX-XXXXXX-XXXXXX)."
  type        = string
}

variable "project_name" {
  description = "Display name for the identity automation project."
  type        = string
  default     = "Identity Automation"
}

variable "org_prefix" {
  description = "Optional org prefix for the project ID (e.g. \"shv\"). Set to \"\" to omit."
  type        = string
  default     = "shv"

  validation {
    condition     = var.org_prefix == "" || can(regex("^[a-z][a-z0-9]{1,9}$", var.org_prefix))
    error_message = "org_prefix must be empty, or 2-10 lowercase letters/digits starting with a letter."
  }
}

variable "project_id_base" {
  description = "Core of the project ID, typically <env>-<purpose>. Final ID is [org_prefix-]base[-suffix]."
  type        = string
  default     = "common-identity"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.project_id_base))
    error_message = "project_id_base must use lowercase letters, digits and hyphens, and not start or end with a hyphen."
  }
}

variable "project_id_suffix" {
  description = <<-EOT
    Optional suffix for the project ID:
      ""        -> no suffix (default; predictable ID)
      "random"  -> 4 random hex characters, generated once and kept in state
      any other -> used literally, e.g. "01"
    Changing this after the first apply changes the project ID, which forces replacement
    (blocked by deletion_policy = PREVENT).
  EOT
  type        = string
  default     = ""

  validation {
    condition     = var.project_id_suffix == "" || can(regex("^[a-z0-9]{1,8}$", var.project_id_suffix))
    error_message = "project_id_suffix must be empty, \"random\", or 1-8 lowercase letters/digits."
  }
}

variable "project_deletion_policy" {
  description = <<-EOT
    Terraform-side guard for the project (not a GCP setting; changing it is an in-place update):
      PREVENT -> terraform destroy / replacement fails (default)
      DELETE  -> destroy deletes the project
      ABANDON -> destroy removes it from state but leaves the project in GCP
    To tear down: set DELETE, run apply (to record it in state), then destroy.
  EOT
  type        = string
  default     = "PREVENT"

  validation {
    condition     = contains(["PREVENT", "DELETE", "ABANDON"], var.project_deletion_policy)
    error_message = "project_deletion_policy must be PREVENT, DELETE or ABANDON."
  }
}

variable "labels" {
  description = "Labels applied to the project."
  type        = map(string)
  default = {
    environment = "common"
    purpose     = "identity-automation"
    managed_by  = "terraform"
  }
}

variable "service_account_id" {
  description = "Account ID (the part before @) of the provisioning service account."
  type        = string
  default     = "user-provisioner"
}

variable "impersonators" {
  description = <<-EOT
    Principals allowed to mint short-lived tokens as the provisioning SA
    (roles/iam.serviceAccountTokenCreator). Use full IAM member strings,
    e.g. "user:admin@stevenhager.com" or "group:identity-operators@stevenhager.com".
    A CI identity (e.g. a Workload Identity Federation principal) can be added later.
  EOT
  type        = list(string)
  default     = ["user:admin@stevenhager.com"]
}

variable "workspace_customer_id" {
  description = "Workspace customer ID (Admin console > Account > Account settings), e.g. C01abc23d."
  type        = string
}

variable "assign_workspace_roles" {
  description = "Assign the Workspace admin roles to the SA via Terraform. Set false to do it by hand in the Admin console."
  type        = bool
  default     = true
}

variable "workspace_admin_roles" {
  description = "Workspace system admin role names to assign to the SA."
  type        = list(string)
  default = [
    "_USER_MANAGEMENT_ADMIN_ROLE",
    "_GROUPS_ADMIN_ROLE",
  ]
}

variable "terraform_impersonate_sa" {
  description = "Optional: bootstrap Terraform SA to impersonate for the google provider. Leave null to run as your own ADC identity."
  type        = string
  default     = null
}

variable "quota_project" {
  description = "Optional: project used for API quota/billing when calling APIs with user ADC (e.g. the bootstrap project ID)."
  type        = string
  default     = null
}
