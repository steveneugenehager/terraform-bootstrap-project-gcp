# identity-automation

Creates the project and service account used to automate user provisioning in
`stevenhager.com`: create users and add them to existing security groups.

## What it builds

| Resource | Purpose |
|---|---|
| `google_project.identity` | `identity-automation-xxxx` in the **common** folder, no default network, `deletion_policy = PREVENT` |
| APIs | Admin SDK, Cloud Identity, IAM, IAM Credentials, Resource Manager, Service Usage, Logging |
| `google_service_account.provisioner` | `user-provisioner@…` — **keyless**, used only through impersonation |
| `roles/iam.serviceAccountTokenCreator` | Granted on the SA (not the project) to each principal in `impersonators` |
| `roles/serviceusage.serviceUsageConsumer` | Lets the SA bill its Admin SDK calls to this project |
| Workspace role assignments | **User Management Admin** + **Groups Admin**, assigned directly to the SA's unique ID |

Because the SA holds Workspace admin roles itself, the automation calls the
Admin SDK *as the SA* — no domain-wide delegation, no impersonating a human
admin, no break-glass account involved.

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

- `deletion_policy = "PREVENT"` blocks `terraform destroy` of the project; set it
  to `"DELETE"` deliberately if you ever need to tear it down.
- Org policy `iam.disableServiceAccountKeyCreation` pairs well with this — nothing
  here needs a key.
- Not yet validated with `terraform validate` — run `terraform init && terraform validate` first.
