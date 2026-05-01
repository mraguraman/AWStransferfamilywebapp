output "web_app_url" {
  description = "Browser URL to share with users for file upload / download"
  value       = aws_transfer_web_app.main.access_endpoint
}

output "web_app_id" {
  description = "Transfer Family Web App ID"
  value       = aws_transfer_web_app.main.web_app_id
}

output "web_app_arn" {
  description = "Transfer Family Web App ARN"
  value       = aws_transfer_web_app.main.arn
}

output "s3_bucket_name" {
  description = "S3 bucket where uploaded files are stored"
  value       = aws_s3_bucket.transfer.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.transfer.arn
}

output "identity_center_instance_arn" {
  description = "ARN of the IAM Identity Center instance used"
  value       = local.identity_center_arn
}

output "transfer_web_app_iam_role_arn" {
  description = "IAM role ARN assigned to the Transfer Web App"
  value       = aws_iam_role.transfer_web_app.arn
}

output "created_users" {
  description = "Usernames of IAM Identity Center users created by Terraform"
  value       = [for u in aws_identitystore_user.transfer_users : u.user_name]
}
