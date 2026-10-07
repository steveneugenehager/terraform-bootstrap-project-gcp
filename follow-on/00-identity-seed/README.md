What it does, as admin@ through ADC. Each step is skipped if it's already done:

Creates identity-admin@<project>.iam.gserviceaccount.com in your bootstrap project.
Optionally grants roles/iam.serviceAccountTokenCreator on that service account to whoever you pass with --impersonator, so you can act as it later.
Looks up the per-customer role IDs for _USER_MANAGEMENT_ADMIN_ROLE and _GROUPS_ADMIN_ROLE.
Assigns both roles to the service account's numeric uniqueId. It retries for a while because a brand-new service account can take a minute to become visible to Workspace.



Run it. Start with --dry-run:

python seed_admin.py --project <bootstrap-project-id> \
  --impersonator user:admin@stevenhager.com --dry-run


If the role-name lookup fails, the script prints every role name it found, so you can fix the constant.

Later stages run as the service account rather than admin@. Use impersonation; no key file or domain-wide delegation is needed:

gcloud auth application-default login \
  --impersonate-service-account=identity-admin@<project>.iam.gserviceaccount.com \
  --scopes=https://www.googleapis.com/auth/admin.directory.user,https://www.googleapis.com/auth/admin.directory.group,https://www.googleapis.com/auth/cloud-platform


Two caveats:

The Admin console may show the assignment as a service account rather than a user. That's expected.
Avoid granting Token Creator broadly. Anyone who holds it effectively holds these two admin roles.