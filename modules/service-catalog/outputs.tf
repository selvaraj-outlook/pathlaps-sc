################################################################################
# Service Catalog Module - Outputs
################################################################################

output "portfolio_id" {
  description = "ID of the Service Catalog portfolio"
  value       = aws_servicecatalog_portfolio.this.id
}

output "portfolio_arn" {
  description = "ARN of the Service Catalog portfolio"
  value       = aws_servicecatalog_portfolio.this.arn
}

output "launch_role_arn" {
  description = "ARN of the IAM role Service Catalog assumes to provision products"
  value       = aws_iam_role.launch.arn
}

output "product_ids" {
  description = "Map of product name to Service Catalog product ID"
  value       = { for k, p in aws_servicecatalog_product.this : k => p.id }
}

output "templates_bucket_name" {
  description = "Name of the S3 bucket hosting bundled product templates (null if no product uses template_file)"
  value       = try(aws_s3_bucket.templates[0].id, null)
}

################################################################################
# StackSet constraint (stackset.tf)
################################################################################

output "stackset_admin_role_arn" {
  description = "ARN of the StackSet administration role in this (hub) account - pass this as AdministrationRoleArn when deploying cloudformation/stackset-execution-role.yaml to each stackset_target_accounts entry"
  value       = var.enable_stackset_products ? aws_iam_role.stackset_admin[0].arn : null
}

################################################################################
# Organizations sharing + admin role (sharing.tf)
################################################################################

output "organization_arn" {
  description = "ARN of the AWS Organization the portfolio is shared with (null unless enable_organizations_access = true)"
  value       = var.enable_organizations_access ? data.aws_organizations_organization.this[0].arn : null
}

output "portfolio_share_id" {
  description = "ID of the organization-wide portfolio share (null unless enable_organizations_access = true)"
  value       = var.enable_organizations_access ? aws_servicecatalog_portfolio_share.organization[0].id : null
}

output "account_share_ids" {
  description = "Map of account ID to portfolio share ID for direct account shares"
  value       = { for k, v in aws_servicecatalog_portfolio_share.account : k => v.id }
}

output "admin_role_arn" {
  description = "ARN of the Service Catalog admin role in this (hub) account (null unless create_admin_role = true)"
  value       = var.create_admin_role ? aws_iam_role.admin[0].arn : null
}

################################################################################
# Member account role rollout (member-accounts.tf)
################################################################################

output "member_role_stackset_id" {
  description = "ID of the member-account-role StackSet (null unless enable_member_role_stackset = true)"
  value       = var.enable_member_role_stackset ? aws_cloudformation_stack_set.member_role[0].id : null
}

################################################################################
# Cross-account Route 53 custom resource (cross-account-dns.tf)
################################################################################

output "cross_account_route53_handler_arn" {
  description = "ARN of the cross-account Route53 handler Lambda (null unless enable_cross_account_route53_handler = true) - this is the ServiceToken value cloudformation/products/standard-route53-record-cross-account.yaml hardcodes"
  value       = var.enable_cross_account_route53_handler ? aws_lambda_function.route53_cross_account_handler[0].arn : null
}
