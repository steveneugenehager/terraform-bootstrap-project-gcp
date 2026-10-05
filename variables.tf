variable "billing_account" {
  description = "Billing account ID (gcloud billing accounts list)."
  type        = string
  sensitive   = true
}

variable "project_prefix" {
  description = "Short prefix for the seed project ID, e.g. your initials or domain."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,18}$", var.project_prefix))
    error_message = "Use 3-19 lowercase letters, digits, or hyphens, starting with a letter."
  }
}

variable "region" {
  description = "Default region for regional resources."
  type        = string
  default     = "us-central1"
}

variable "state_bucket_location" {
  description = "Location of the state bucket. A multi-region (US) survives a regional outage."
  type        = string
  default     = "US"
}

variable "org_id" {
  description = "Organization ID, if you have one (gcloud organizations list). Leave null otherwise."
  type        = string
  default     = null
}

variable "folder_id" {
  description = "Optional folder to hold the seed project, instead of the organization root."
  type        = string
  default     = null
}

variable "terraform_admins" {
  description = "Principals allowed to impersonate the Terraform service account, e.g. [\"user:you@example.com\"]."
  type        = list(string)
  default     = []
}

variable "grant_billing_user" {
  description = "Grant the Terraform service account Billing Account User, so it can link new projects to billing. Requires billing admin rights on the account."
  type        = bool
  default     = false
}

variable "state_versions_to_keep" {
  description = "Number of older versions of each state file to retain for recovery."
  type        = number
  default     = 20
}
