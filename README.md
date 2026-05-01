# AWS Transfer Family Web App — Terraform

A fully automated, browser-based secure file transfer portal that allows internet users to upload and download files to Amazon S3 — no SFTP client required. Authentication is handled by **AWS IAM Identity Center (SSO)** and per-user file access is controlled via **Amazon S3 Access Grants**.

---

## Architecture

```
Internet Users (Browser)
        │
        ▼
AWS Transfer Family Web App  ──  Public HTTPS Endpoint
        │
        ▼
IAM Identity Center  ──  SSO Authentication
        │
        ▼
S3 Access Grants  ──  Per-user access control
        │
        ▼
Amazon S3  ──  File storage (ap-southeast-1)
```

---

## Prerequisites

| Requirement | Details |
|---|---|
| Terraform | >= 1.5.0 |
| AWS Provider | >= 6.16.0 (auto-downloaded) |
| AWS CLI | Configured with access keys |
| IAM Identity Center | Must be **enabled** in your target region before applying |

> Enable IAM Identity Center: AWS Console → IAM Identity Center → Enable

---

## Project Structure

```
terraform/
├── providers.tf              # AWS provider configuration
├── variables.tf              # Input variables
├── main.tf                   # All AWS resources
├── outputs.tf                # Web app URL and resource info
├── terraform.tfvars          # Your values (DO NOT commit)
└── terraform.tfvars.example  # Template — copy and fill in
```

---

## Quick Start

### 1. Configure variables

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
aws_region                = "ap-southeast-1"
project_name              = "secure-transfer"
environment               = "dev"
web_app_provisioned_units = 1

transfer_users = [
  {
    display_name = "John Doe"
    user_name    = "john.doe"
    email        = "john.doe@company.com"
    given_name   = "John"
    family_name  = "Doe"
  }
]
```

### 2. Deploy

```bash
cd terraform
terraform init
terraform plan
terraform apply -auto-approve
```

### 3. Get the web app URL

```bash
terraform output web_app_url
```

Share this URL with your users. Each user receives an **AWS invitation email** to set their password on first login.

---

## Resources Deployed (19 total)

| # | Terraform Resource | Purpose |
|---|---|---|
| 1 | `aws_s3_bucket` | File storage bucket |
| 2 | `aws_s3_bucket_versioning` | Enable versioning |
| 3 | `aws_s3_bucket_server_side_encryption_configuration` | AES-256 encryption |
| 4 | `aws_s3_bucket_public_access_block` | Block all public access |
| 5 | `aws_s3_bucket_lifecycle_configuration` | Abort incomplete multipart uploads after 7 days |
| 6 | `aws_s3_bucket_cors_configuration` | Allow web app origin for browser requests |
| 7 | `aws_iam_role` (Identity Bearer) | Trusted by `transfer.amazonaws.com` |
| 8 | `aws_iam_role_policy` (Identity Bearer) | `s3:GetDataAccess`, `s3:ListCallerAccessGrants`, `s3:ListAccessGrantsInstances` |
| 9 | `aws_iam_role` (Access Grants Location) | Trusted by `access-grants.s3.amazonaws.com` |
| 10 | `aws_iam_role_policy` (Access Grants Location) | S3 read/write on bucket |
| 11 | `aws_s3control_access_grants_instance` | S3 Access Grants instance linked to Identity Center |
| 12 | `aws_s3control_access_grants_location` | Registers `s3://bucket/*` as a managed location |
| 13 | `aws_s3control_access_grant` | Per-user READWRITE grant via `DIRECTORY_USER` identity |
| 14 | `aws_ssoadmin_permission_set` | `TransferWebAppAccess` permission set |
| 15 | `aws_ssoadmin_permission_set_inline_policy` | S3 read/write scoped to bucket |
| 16 | `aws_identitystore_user` | User account in IAM Identity Center |
| 17 | `aws_ssoadmin_account_assignment` | Assigns permission set to user for AWS account |
| 18 | `aws_ssoadmin_application_assignment` | Assigns user to Transfer Family Web App SSO application |
| 19 | `aws_transfer_web_app` | Transfer Family Web App (public HTTPS endpoint) |

---

## Adding Users

Add entries to `transfer_users` in `terraform.tfvars` and re-apply:

```hcl
transfer_users = [
  {
    display_name = "Jane Smith"
    user_name    = "jane.smith"
    email        = "jane.smith@company.com"
    given_name   = "Jane"
    family_name  = "Smith"
  }
]
```

```bash
terraform apply -auto-approve
```

---

## IAM Role Configuration — Critical Notes

### Identity Bearer Role (Web App Role)

```json
{
  "Trust Policy": {
    "Principal": "transfer.amazonaws.com",
    "Action": ["sts:AssumeRole", "sts:SetContext"]
  },
  "Permissions": [
    "s3:GetDataAccess",
    "s3:ListCallerAccessGrants",
    "s3:ListAccessGrantsInstances"
  ]
}
```

> **Common mistake:** Using `s3:ListAccessGrants` + `s3:ListAccessGrantsLocations` instead of `s3:ListCallerAccessGrants` + `s3:ListAccessGrantsInstances`. These are different actions and will cause a silent "application setup" error.

### S3 Access Grants Location Role

```json
{
  "Trust Policy": {
    "Principal": "access-grants.s3.amazonaws.com",
    "Action": ["sts:AssumeRole", "sts:SetContext"]
  }
}
```

> **Common mistake:** Using `sts:SetSourceIdentity` instead of `sts:SetContext`. Only `sts:SetContext` propagates the IAM Identity Center user identity correctly.

---

## User Access — How It Works

Each user requires **4 assignments** — missing any one causes a different login error:

| Assignment | Missing = Error |
|---|---|
| `aws_identitystore_user` | User doesn't exist |
| `aws_ssoadmin_account_assignment` | No AWS account access |
| `aws_ssoadmin_application_assignment` | *"You do not have access to this application"* |
| `aws_s3control_access_grant` | *"There is an issue with the application setup"* |

---

## S3 CORS — Required

The S3 bucket must allow the Transfer Family Web App URL as `AllowedOrigin`. This is configured automatically via Terraform using the web app's `access_endpoint` output.

> Do **not** add a trailing slash to the origin URL.

---

## Teardown

Empty the S3 bucket first (versioning creates version markers that block bucket deletion):

```bash
# Remove all current objects
aws s3 rm s3://<bucket-name> --recursive --region ap-southeast-1

# Then destroy all resources
cd terraform
terraform destroy -auto-approve
```

---

## Outputs

| Output | Description |
|---|---|
| `web_app_url` | Public HTTPS URL — share with users |
| `web_app_id` | Transfer Family Web App ID |
| `web_app_arn` | Transfer Family Web App ARN |
| `s3_bucket_name` | S3 bucket name |
| `s3_bucket_arn` | S3 bucket ARN |
| `created_users` | List of usernames created in Identity Center |

---

## Cost Estimate

| Service | Cost | Free Tier |
|---|---|---|
| Transfer Family Web App | ~$0.30/hr per endpoint | Not included |
| S3 Storage | $0.023/GB/month | 5 GB free |
| IAM Identity Center | Free | Always free |
| S3 Access Grants | Free | Always free |

> Run `terraform destroy` when not in use to avoid charges (~$7.20/day).

---

## Tech Stack

`AWS Transfer Family` · `Amazon S3` · `S3 Access Grants` · `IAM Identity Center` · `Terraform` · `AWS IAM`
