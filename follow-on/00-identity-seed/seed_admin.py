#!/usr/bin/env python3
"""Stage 0 identity seed: give a service account Workspace admin roles.

Run ONCE, as a super admin (e.g. admin@stevenhager.com), via ADC:

    gcloud auth application-default login \
      --scopes=https://www.googleapis.com/auth/admin.directory.rolemanagement,https://www.googleapis.com/auth/cloud-platform
    gcloud auth application-default set-quota-project <bootstrap-project-id>

Prereqs in the bootstrap project: Admin SDK API (admin.googleapis.com) and
IAM API (iam.googleapis.com) enabled.

    pip install google-api-python-client google-auth

Idempotent: it creates or assigns only what is missing, so reruns are safe.

Example:
    python seed_admin.py --project my-bootstrap-proj --sa-id identity-admin \
        --impersonator user:ops@stevenhager.com --dry-run
"""

from __future__ import annotations

import argparse
import sys
import time

import google.auth
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError

SCOPES = [
    "https://www.googleapis.com/auth/admin.directory.rolemanagement",
    "https://www.googleapis.com/auth/cloud-platform",
]

# Prebuilt Workspace role names (stable across customers; roleIds are not).
TARGET_ROLES = ["_USER_MANAGEMENT_ADMIN_ROLE", "_GROUPS_ADMIN_ROLE"]

CUSTOMER = "my_customer"  # alias for the caller's own Workspace customer


def log(msg: str) -> None:
    print(msg, flush=True)


# --------------------------------------------------------------------------- #
# Service account (GCP IAM)
# --------------------------------------------------------------------------- #
def ensure_service_account(iam, project: str, sa_id: str, display_name: str,
                           dry_run: bool) -> dict | None:
    email = f"{sa_id}@{project}.iam.gserviceaccount.com"
    name = f"projects/{project}/serviceAccounts/{email}"
    try:
        sa = iam.projects().serviceAccounts().get(name=name).execute()
        log(f"[ok]     service account exists: {email} (uniqueId {sa['uniqueId']})")
        return sa
    except HttpError as e:
        if e.resp.status != 404:
            raise

    if dry_run:
        log(f"[dry]    would create service account {email}")
        return None

    sa = iam.projects().serviceAccounts().create(
        name=f"projects/{project}",
        body={"accountId": sa_id, "serviceAccount": {"displayName": display_name}},
    ).execute()
    log(f"[create] service account {email} (uniqueId {sa['uniqueId']})")
    return sa


def ensure_impersonator(iam, sa_email: str, member: str, project: str,
                        dry_run: bool) -> None:
    """Grant roles/iam.serviceAccountTokenCreator on the SA to `member`."""
    resource = f"projects/{project}/serviceAccounts/{sa_email}"
    role = "roles/iam.serviceAccountTokenCreator"
    policy = iam.projects().serviceAccounts().getIamPolicy(resource=resource).execute()
    bindings = policy.setdefault("bindings", [])
    binding = next((b for b in bindings if b["role"] == role), None)
    if binding and member in binding.get("members", []):
        log(f"[ok]     {member} already has {role} on SA")
        return
    if dry_run:
        log(f"[dry]    would grant {role} on SA to {member}")
        return
    if binding:
        binding["members"].append(member)
    else:
        bindings.append({"role": role, "members": [member]})
    iam.projects().serviceAccounts().setIamPolicy(
        resource=resource, body={"policy": policy}
    ).execute()
    log(f"[grant]  {role} on SA to {member}")


# --------------------------------------------------------------------------- #
# Workspace admin roles (Admin SDK Directory API)
# --------------------------------------------------------------------------- #
def paginate(method, key: str, **kwargs):
    token = None
    while True:
        resp = method(pageToken=token, **kwargs).execute()
        yield from resp.get(key, [])
        token = resp.get("nextPageToken")
        if not token:
            return


def role_ids_by_name(directory) -> dict[str, str]:
    roles = list(paginate(directory.roles().list, "items", customer=CUSTOMER))
    by_name = {r["roleName"]: r["roleId"] for r in roles}
    missing = [n for n in TARGET_ROLES if n not in by_name]
    if missing:
        log(f"[error]  roles not found: {missing}")
        log("         available: " + ", ".join(sorted(by_name)))
        sys.exit(2)
    return {n: by_name[n] for n in TARGET_ROLES}


def ensure_role_assignment(directory, role_name: str, role_id: str,
                           assignee_id: str, dry_run: bool) -> None:
    existing = paginate(directory.roleAssignments().list, "items",
                        customer=CUSTOMER, roleId=role_id)
    if any(a.get("assignedTo") == assignee_id for a in existing):
        log(f"[ok]     {role_name} already assigned")
        return
    if dry_run:
        log(f"[dry]    would assign {role_name}")
        return

    body = {"roleId": role_id, "assignedTo": assignee_id, "scopeType": "CUSTOMER"}
    # A freshly created SA can take a little while to become visible to
    # Workspace, so retry with backoff.
    for attempt in range(6):
        try:
            directory.roleAssignments().insert(customer=CUSTOMER, body=body).execute()
            log(f"[assign] {role_name}")
            return
        except HttpError as e:
            if e.resp.status in (400, 404) and attempt < 5:
                wait = 5 * 2 ** attempt
                log(f"[retry]  {role_name}: {e.resp.status}, waiting {wait}s")
                time.sleep(wait)
                continue
            raise


# --------------------------------------------------------------------------- #
def main() -> None:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--project", required=True, help="bootstrap GCP project ID")
    p.add_argument("--sa-id", default="identity-admin",
                   help="service account ID (the part before @)")
    p.add_argument("--display-name", default="Workspace identity admin (bootstrap)")
    p.add_argument("--impersonator", action="append", default=[],
                   help="member allowed to impersonate the SA, e.g. "
                        "user:ops@stevenhager.com (repeatable)")
    p.add_argument("--dry-run", action="store_true")
    args = p.parse_args()

    creds, _ = google.auth.default(scopes=SCOPES)
    iam = build("iam", "v1", credentials=creds, cache_discovery=False)
    directory = build("admin", "directory_v1", credentials=creds, cache_discovery=False)

    sa = ensure_service_account(iam, args.project, args.sa_id,
                                args.display_name, args.dry_run)
    roles = role_ids_by_name(directory)

    if sa is None:  # dry run, SA not yet created
        for name in roles:
            log(f"[dry]    would assign {name} to new SA")
        return

    for member in args.impersonator:
        ensure_impersonator(iam, sa["email"], member, args.project, args.dry_run)

    for name, role_id in roles.items():
        ensure_role_assignment(directory, name, role_id, sa["uniqueId"], args.dry_run)

    log("done.")


if __name__ == "__main__":
    main()
