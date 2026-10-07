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
  default     = "identity-automation"
}

variable "project_id_prefix" {
  description = "Prefix for the project ID; a random 4-hex suffix is appended for global uniqueness."
  type        = string
  default     = "identity-automation"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,24}$", var.project_id_prefix))
    error_message = "Prefix must start with a letter, use lowercase letters/digits/hyphens, and be 5-25 characters (leaves room for the suffix)."
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
