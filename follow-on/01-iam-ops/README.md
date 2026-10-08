# identity-automation

Creates the project and service account used to automate user provisioning in
`stevenhager.com`: create users and add them to existing security groups.

## What it builds

| Resource | Purpose |
|---|---|
| `google_project.identity` | `shv-common-identity` in the **common** folder, no default network, `deletion_policy = PREVENT` |
| APIs | Admin SDK, Cloud Identity, IAM, IAM Credentials, Resource Manager, Service Usage, Logging |
| `google_service_account.provisioner` | `user-provisioner@…` — **keyless**, used only through impersonation |
| `roles/iam.serviceAccountTokenCreator` | Granted on the SA (not the project) to each principal in `impersonators` |
| `roles/serviceusage.serviceUsageConsumer` | Lets the SA bill its Admin SDK calls to this project |
| Workspace role assignments | **User Management Admin** + **Groups Admin**, assigned directly to the SA's unique ID |

Because the SA holds Workspace admin roles itself, the automation calls the
Admin SDK *as the SA* — no domain-wide delegation, no impersonating a human
admin, no break-glass account involved.

## Project ID naming

`project_id = [org_prefix-]project_id_base[-suffix]`

| `org_prefix` | `project_id_base` | `project_id_suffix` | Result |
|---|---|---|---|
| `shv` | `common-identity` | `""` | `shv-common-identity` (default) |
| `shv` | `common-identity` | `random` | `shv-common-identity-3f9a` |
| `shv` | `common-identity` | `01` | `shv-common-identity-01` |
| `""` | `common-identity` | `""` | `common-identity` |

A random suffix is generated once and kept in state. Decide on the ID before the
first apply: changing any of these afterwards renames the project, which forces a
replacement that `deletion_policy = "PREVENT"` will block. A non-empty `org_prefix`
is also added as an `org` label.

## Prerequisites

1. Bootstrap project and state bucket exist; `common` folder exists.
2. Your identity (admin@stevenhager.com or the bootstrap Terraform SA) has, on the
   common folder / billing account: Project Creator, Billing Account User, and
   enough IAM to grant roles on the new project.
3. For the Workspace role assignment the caller must be a Super Admin, and ADC
   needs the Workspace scope:

   ```bash
   gcloud auth application-default login \
     --scopes=openid,https://www.googleapis.com/auth/userinfo.email,https://www.googleapis.com/auth/cloud-platform,https://www.googleapis.com/auth/admin.directory.rolemanagement
   gcloud auth application-default set-quota-project <bootstrap-project-id>
   ```

   If you'd rather not widen ADC scopes, set `assign_workspace_roles = false` and
   assign the two roles in **Admin console → Account → Admin roles → (role) →
   Admins → Assign service accounts**, using the `provisioner_sa_email` output.

## Usage

```bash
cp backend.hcl.example backend.hcl          # point at the bootstrap state bucket
cp terraform.tfvars.example terraform.tfvars
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

## Using the SA from the provisioning automation

```bash
SA=$(terraform output -raw provisioner_sa_email)
gcloud auth print-access-token --impersonate-service-account="$SA" \
  --scopes=https://www.googleapis.com/auth/admin.directory.user,https://www.googleapis.com/auth/admin.directory.group.member
```

In Python, `google.auth.impersonated_credentials.Credentials` with those two
scopes, then `googleapiclient.discovery.build("admin", "directory_v1", ...)`.

Least-privilege note: Groups Admin can also create/delete groups. If the
automation should only add members to *existing* groups, consider a custom
Workspace role later (Users: create/read/update; Groups: read + manage members)
and swap it into `workspace_admin_roles`.

## Notes

- `project_deletion_policy` (default `PREVENT`) blocks `terraform destroy` of the
  project. It's a Terraform-only setting, so switching it is an in-place update and
  never recreates the project. To tear down: set `DELETE`, run `terraform apply`
  so the new value is saved in state, *then* `terraform destroy`. Setting it and
  running destroy directly still fails, because destroy reads the value from state.
- Org policy `iam.disableServiceAccountKeyCreation` pairs well with this — nothing
  here needs a key.
- Not yet validated with `terraform validate` — run `terraform init && terraform validate` first.
