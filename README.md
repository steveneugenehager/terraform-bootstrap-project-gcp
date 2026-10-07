# GCP Terraform Bootstrap

Creates the foundation every other Terraform configuration in this organization
depends on: a **seed project**, a **versioned GCS bucket for Terraform state**, and
a **Terraform service account** that later configurations impersonate.

This is the only configuration that starts with local state. After its first
apply, it migrates its own state into the bucket it created, so nothing important
ever lives on a single machine.

## What it creates

| Resource | Purpose |
|---|---|
| Seed project (`<prefix>-seed-<random>`) | Holds state and the automation identity. Protected with `deletion_policy = "PREVENT"`. |
| Project APIs | Resource Manager, Cloud Billing, IAM, IAM Credentials, Service Usage, Cloud Storage. |
| State bucket (`<seed-project-id>-tfstate`) | Shared by all configurations, each under its own prefix. Versioned, public access blocked, uniform bucket-level access, old versions trimmed by a lifecycle rule. |
| `terraform` service account | The identity later configurations run as. No key files; access is by impersonation. |
| IAM bindings | Service account access to the state bucket; impersonation rights for listed admins; optional Billing Account User; Project Creator and Folder Admin at the organization when `org_id` is set. |
| Org-level admin groups | Such are few, small and tightly held.|

## Repository layout

```
.
├── versions.tf                 # Terraform and provider versions, backend block
├── variables.tf                # Inputs, with validation
├── main.tf                     # Seed project, APIs, state bucket, service account, IAM
├── outputs.tf                  # Project ID, bucket, service account, example backend block
├── terraform.tfvars.example    # Copy to terraform.tfvars and fill in
├── .terraform.lock.hcl         # Pinned provider versions (committed)
├──.gitignore                   # Excludes state, tfvars, and .terraform/
└── follow-on                   # Follow On Activities belonging in "Bootstrap" stage.
   └── create_secondary_org_admin.sh  # Creates secondary Super Admin for the GCP organization.
```

## Prerequisites

These steps can't be done by Terraform and must exist first.

1. **A Google Cloud organization.** Created automatically when a domain is verified
   in Cloud Identity (the Free edition is sufficient).
2. **A billing account** in good standing, created in the Cloud Console.
3. **An administrator account on the organization's domain** (not a personal
   Gmail account) with these roles at the organization level:
   - Organization Administrator
   - Folder Admin
   - Project Creator
   - Billing Account User (or Billing Account Administrator) on the billing account
4. **Tools** on the machine running Terraform:
   - Terraform 1.5 or later (`terraform version`)
   - Google Cloud CLI (`gcloud version`)

Establish your GCP authentication using the "Org Owner" "Super Admin" account via: 
```
gcloud auth login
```

Look up the IDs you'll need:

```bash
gcloud organizations list            # use the numeric ID column, not DIRECTORY_CUSTOMER_ID
gcloud billing accounts list         # use ACCOUNT_ID
```

## Authenticate

Terraform uses Application Default Credentials (ADC), which are separate from the
regular `gcloud auth login`.

```bash
gcloud auth login admin@yourdomain.com
gcloud auth application-default login
```

On the consent screen, choose **Select all**. If the Google Cloud data permission
is left unchecked, gcloud fails with a "Scope has changed" error.

Verify:

```bash
gcloud auth application-default print-access-token
```

## First run: local state

```bash
cp terraform.tfvars.example terraform.tfvars    # then edit
terraform init
terraform fmt && terraform validate
terraform plan -out=bootstrap.plan
terraform apply bootstrap.plan
```

Example `terraform.tfvars`:

```hcl
billing_account    = "XXXXXX-XXXXXX-XXXXXX"
project_prefix     = "shv-cld-admn"
org_id             = "123456789012"
terraform_admins   = ["user:admin@yourdomain.com"]
grant_billing_user = true
```

`terraform.tfvars` is gitignored. Never commit it.

## Move state into the bucket

1. Get the bucket name:

   ```bash
   terraform output state_bucket
   ```

2. In `versions.tf`, uncomment the `backend "gcs"` block and set `bucket` to that value.

3. Migrate:

   ```bash
   terraform init -migrate-state
   ```

   Answer `yes` to copy the existing state.

4. Confirm, then remove the local copies:

   ```bash
   gcloud storage ls gs://BUCKET/bootstrap/
   rm terraform.tfstate terraform.tfstate.backup
   ```

5. Point ADC's quota project at the new seed project:

   ```bash
   gcloud auth application-default set-quota-project $(terraform output -raw seed_project_id)
   ```

From here on, this configuration's state lives at `gs://BUCKET/bootstrap/`.

## Using the bootstrap from other configurations

Print a ready-made backend block:

```bash
terraform output example_backend_block
```

Each configuration uses the same bucket with its own prefix. Recommended
convention: `DOMAIN/ENV/COMPONENT`.

```hcl
terraform {
  backend "gcs" {
    bucket                      = "SEED_PROJECT_ID-tfstate"
    prefix                      = "network/prod/shared-vpc"
    impersonate_service_account = "terraform@SEED_PROJECT_ID.iam.gserviceaccount.com"
  }
}

provider "google" {
  impersonate_service_account = "terraform@SEED_PROJECT_ID.iam.gserviceaccount.com"
}
```

The backend and the provider authenticate separately, so both need the
impersonation setting.

The service account starts with access only to the state bucket and, with an
organization, project and folder creation. Grant it further roles on the
folders or projects each configuration manages.

## Recovering state

The bucket keeps prior versions of every state file. To list versions:

```bash
gcloud storage ls --all-versions gs://BUCKET/PREFIX/default.tfstate
```

To restore one, copy the chosen generation over the current object:

```bash
gcloud storage cp gs://BUCKET/PREFIX/default.tfstate#GENERATION \
                  gs://BUCKET/PREFIX/default.tfstate
```

## Tearing down

The seed project is protected. Destroying it removes the state of every
configuration that uses the bucket, so destroy those configurations first.

1. Migrate this configuration back to local state: comment out the backend block
   and run `terraform init -migrate-state`.
2. Set `deletion_policy = "DELETE"` in `main.tf` and apply.
3. Empty the bucket, then run `terraform destroy`.

A deleted project can be restored for about 30 days with
`gcloud projects undelete PROJECT_ID`. Its ID can never be reused.

## Troubleshooting

**`Scope has changed from ... to ...`**
The consent screen didn't grant the Google Cloud permission. Rerun
`gcloud auth application-default login` and choose **Select all**.

**`print-access-token` hangs**
Usually missing ADC credentials (the libraries probe for a cloud metadata server)
or a network problem reaching `oauth2.googleapis.com`. Rerun with
`--verbosity=debug` to see which host it's waiting on.

**`User project billing account not in good standing` (403)**
Terraform or ADC is pointing at a deleted or unbilled project. Comment out the
backend block, then:

```bash
rm -rf .terraform
terraform init -reconfigure
```

Also check `quota_project_id` in `~/.config/gcloud/application_default_credentials.json`.

**`resourcemanager.folders.create` permission denied**
The acting identity lacks Folder Admin at the organization. Check whether you're
running as yourself or impersonating the service account, then grant the role:

```bash
gcloud organizations add-iam-policy-binding ORG_ID \
  --member="user:admin@yourdomain.com" \
  --role="roles/resourcemanager.folderAdmin"
```

**Quota project or "API not enabled" errors on first run**
Set an ADC quota project to any existing project the admin account can access:
`gcloud auth application-default set-quota-project PROJECT_ID`.

## Security notes

- No service account keys are created or downloaded; all automation uses impersonation.
- State files can contain sensitive values in plain text. Access to the bucket is
  limited to the Terraform service account and organization administrators.
- `billing_account` is marked `sensitive`, which hides it in plan output but does
  not encrypt it in state.
- `.terraform.lock.hcl` is committed so every machine uses the same provider versions.
  Upgrade deliberately with `terraform init -upgrade`.
