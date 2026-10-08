# ---------------------------------------------------------------------------
# Change History
# 2026-10-07 Steve Hager - v1.0 Initial version

output "project_id" {
  description = "ID of the identity automation project."
  value       = google_project.identity.project_id
}

output "project_number" {
  description = "Number of the identity automation project."
  value       = google_project.identity.number
}

output "provisioner_sa_email" {
  description = "Email of the user provisioning service account."
  value       = google_service_account.provisioner.email
}

output "provisioner_sa_unique_id" {
  description = "Numeric unique ID of the SA (what Workspace role assignments reference)."
  value       = google_service_account.provisioner.unique_id
}

output "workspace_role_assignments" {
  description = "Workspace admin roles assigned to the SA, by role name."
  value       = { for k, v in googleworkspace_role_assignment.provisioner : k => v.id }
}
