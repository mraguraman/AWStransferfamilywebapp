# ─────────────────────────────────────────────
# Data sources
# ─────────────────────────────────────────────

data "aws_caller_identity" "current" {}

# IAM Identity Center must be enabled in your AWS account before applying.
# Enable it via: AWS Console → IAM Identity Center → Enable
data "aws_ssoadmin_instances" "main" {}

locals {
  account_id          = data.aws_caller_identity.current.account_id
  identity_center_arn = tolist(data.aws_ssoadmin_instances.main.arns)[0]
  identity_store_id   = tolist(data.aws_ssoadmin_instances.main.identity_store_ids)[0]

  bucket_name = var.s3_bucket_name != "" ? var.s3_bucket_name : "${var.project_name}-files-${local.account_id}"
}

# ─────────────────────────────────────────────
# S3 Bucket
# ─────────────────────────────────────────────

resource "aws_s3_bucket" "transfer" {
  bucket        = local.bucket_name
  force_destroy = false
}

resource "aws_s3_bucket_versioning" "transfer" {
  bucket = aws_s3_bucket.transfer.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "transfer" {
  bucket = aws_s3_bucket.transfer.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "transfer" {
  bucket = aws_s3_bucket.transfer.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "transfer" {
  bucket = aws_s3_bucket.transfer.id

  rule {
    id     = "abort-incomplete-multipart"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_cors_configuration" "transfer" {
  bucket = aws_s3_bucket.transfer.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST", "DELETE", "HEAD"]
    allowed_origins = [aws_transfer_web_app.main.access_endpoint]
    expose_headers = [
      "last-modified",
      "content-length",
      "etag",
      "x-amz-version-id",
      "content-type",
      "x-amz-request-id",
      "x-amz-id-2",
      "date",
      "x-amz-cf-id",
      "x-amz-storage-class",
      "access-control-expose-headers"
    ]
    max_age_seconds = 3000
  }
}

# ─────────────────────────────────────────────
# IAM — Transfer Family Web App Role
# ─────────────────────────────────────────────

resource "aws_iam_role" "transfer_web_app" {
  name        = "${var.project_name}-transfer-web-app-role"
  description = "Allows Transfer Family Web App to access S3 and Identity Center"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "transfer.amazonaws.com"
        }
        Action = ["sts:AssumeRole", "sts:SetContext"]
      }
    ]
  })
}

resource "aws_iam_role_policy" "transfer_s3_access" {
  name = "${var.project_name}-s3-access-policy"
  role = aws_iam_role.transfer_web_app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowS3AccessGrants"
        Effect = "Allow"
        Action = [
          "s3:GetDataAccess",
          "s3:ListCallerAccessGrants",
          "s3:ListAccessGrantsInstances"
        ]
        Resource = "*"
      }
    ]
  })
}

# ─────────────────────────────────────────────
# S3 Access Grants
# Transfer Family Web App requires S3 Access Grants to resolve
# per-user file access via IAM Identity Center identities.
# ─────────────────────────────────────────────

resource "aws_s3control_access_grants_instance" "main" {
  identity_center_arn = local.identity_center_arn
}

resource "aws_iam_role" "s3_access_grants" {
  name        = "${var.project_name}-s3-access-grants-role"
  description = "Used by S3 Access Grants to vend temporary credentials for the transfer bucket"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "access-grants.s3.amazonaws.com"
        }
        Action = ["sts:AssumeRole", "sts:SetContext"]
      }
    ]
  })
}

resource "aws_iam_role_policy" "s3_access_grants" {
  name = "${var.project_name}-s3-access-grants-policy"
  role = aws_iam_role.s3_access_grants.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:GetObjectVersion",
          "s3:DeleteObjectVersion"
        ]
        Resource = [
          aws_s3_bucket.transfer.arn,
          "${aws_s3_bucket.transfer.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_s3control_access_grants_location" "main" {
  location_scope = "s3://${aws_s3_bucket.transfer.id}/*"
  iam_role_arn   = aws_iam_role.s3_access_grants.arn

  depends_on = [aws_s3control_access_grants_instance.main]
}

resource "aws_s3control_access_grant" "transfer_users" {
  for_each = { for u in var.transfer_users : u.user_name => u }

  access_grants_location_id = aws_s3control_access_grants_location.main.access_grants_location_id
  permission                = "READWRITE"

  grantee {
    grantee_type       = "DIRECTORY_USER"
    grantee_identifier = aws_identitystore_user.transfer_users[each.key].user_id
  }
}

# ─────────────────────────────────────────────
# IAM Identity Center — Permission Set
# ─────────────────────────────────────────────

resource "aws_ssoadmin_permission_set" "transfer_users" {
  name             = "TransferWebAppAccess"
  instance_arn     = local.identity_center_arn
  session_duration = "PT8H"
  description      = "Grants access to the Transfer Family Web App"
}

resource "aws_ssoadmin_permission_set_inline_policy" "transfer_users_s3" {
  instance_arn       = local.identity_center_arn
  permission_set_arn = aws_ssoadmin_permission_set.transfer_users.arn

  inline_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3BucketAccess"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = aws_s3_bucket.transfer.arn
      },
      {
        Sid    = "S3ObjectAccess"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:GetObjectVersion"
        ]
        Resource = "${aws_s3_bucket.transfer.arn}/*"
      }
    ]
  })
}

# ─────────────────────────────────────────────
# IAM Identity Center — Users
# ─────────────────────────────────────────────

resource "aws_identitystore_user" "transfer_users" {
  for_each = { for u in var.transfer_users : u.user_name => u }

  identity_store_id = local.identity_store_id
  display_name      = each.value.display_name
  user_name         = each.value.user_name

  name {
    given_name  = each.value.given_name
    family_name = each.value.family_name
  }

  emails {
    value   = each.value.email
    primary = true
  }
}

resource "aws_ssoadmin_account_assignment" "transfer_users" {
  for_each = { for u in var.transfer_users : u.user_name => u }

  instance_arn       = local.identity_center_arn
  permission_set_arn = aws_ssoadmin_permission_set.transfer_users.arn

  principal_id   = aws_identitystore_user.transfer_users[each.key].user_id
  principal_type = "USER"

  target_id   = local.account_id
  target_type = "AWS_ACCOUNT"
}

# Assign each user directly to the Transfer Family Web App SSO application.
# Without this, users see "You do not have access to this application."
resource "aws_ssoadmin_application_assignment" "transfer_users" {
  for_each = { for u in var.transfer_users : u.user_name => u }

  application_arn = aws_transfer_web_app.main.identity_provider_details[0].identity_center_config[0].application_arn
  principal_id    = aws_identitystore_user.transfer_users[each.key].user_id
  principal_type  = "USER"
}

# ─────────────────────────────────────────────
# AWS Transfer Family Web App
# ─────────────────────────────────────────────

resource "aws_transfer_web_app" "main" {
  identity_provider_details {
    identity_center_config {
      instance_arn = local.identity_center_arn
      role         = aws_iam_role.transfer_web_app.arn
    }
  }

  web_app_units {
    provisioned = var.web_app_provisioned_units
  }

  depends_on = [
    aws_iam_role_policy.transfer_s3_access,
    aws_s3_bucket_public_access_block.transfer,
  ]
}
