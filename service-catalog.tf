################################################################################
# AWS Service Catalog - Self-service product portfolio (SharedServices Account)
#
# Ships with two bundled example products (standard-s3-bucket,
# standard-sns-topic - see var.service_catalog_products below) so the portfolio
# is immediately usable, but var.service_catalog_principal_arns still
# defaults to [] - nobody can actually LAUNCH either product until that's
# populated. Everything else (org sharing, StackSets, admin/member roles)
# stays off by default. See modules/service-catalog/*.tf and its README.md.
################################################################################

module "service_catalog" {
  source = "./modules/service-catalog"

  name          = var.service_catalog_portfolio_name
  description   = var.service_catalog_portfolio_description
  provider_name = var.service_catalog_provider_name

  principal_arns          = var.service_catalog_principal_arns
  launch_role_name        = var.service_catalog_launch_role_name
  launch_role_policy_arns = var.service_catalog_launch_role_policy_arns
  products                = var.service_catalog_products

  templates_bucket_name          = var.service_catalog_templates_bucket_name
  attach_example_products_policy = var.service_catalog_attach_example_products_policy

  # CloudFormation StackSet constraint (multi-account/region products)
  enable_stackset_products              = var.service_catalog_enable_stackset_products
  stackset_admin_role_name              = var.service_catalog_stackset_admin_role_name
  stackset_execution_role_name          = var.service_catalog_stackset_execution_role_name
  stackset_target_accounts              = var.service_catalog_stackset_target_accounts
  stackset_target_regions               = var.service_catalog_stackset_target_regions
  stackset_allow_stack_instance_control = var.service_catalog_stackset_allow_stack_instance_control

  # AWS Organizations sharing - share the portfolio to every other account
  enable_organizations_access = var.service_catalog_enable_organizations_access
  share_tag_options           = var.service_catalog_share_tag_options
  share_principals            = var.service_catalog_share_principals
  share_account_ids           = var.service_catalog_share_account_ids

  # Admin role (this hub account)
  create_admin_role    = var.service_catalog_create_admin_role
  admin_role_name      = var.service_catalog_admin_role_name
  admin_principal_arns = var.service_catalog_admin_principal_arns

  # Member role rollout (spoke accounts)
  member_role_name                        = var.service_catalog_member_role_name
  member_role_trusted_principal_arns      = var.service_catalog_member_role_trusted_principal_arns
  enable_member_role_stackset             = var.service_catalog_enable_member_role_stackset
  member_stackset_organizational_unit_ids = var.service_catalog_member_stackset_organizational_unit_ids
  member_stackset_region                  = var.service_catalog_member_stackset_region

  # Cross-account Route 53 custom resource (Option B)
  enable_cross_account_route53_handler         = var.service_catalog_enable_cross_account_route53_handler
  cross_account_route53_handler_function_name  = var.service_catalog_cross_account_route53_handler_function_name
  cross_account_route53_invoker_principal_arns = var.service_catalog_cross_account_route53_invoker_principal_arns

  tags = {
    Purpose = "path-labs-service-catalog"
  }
}

################################################################################
# Variables
################################################################################

variable "service_catalog_portfolio_name" {
  description = "Name of the Service Catalog portfolio"
  type        = string
  default     = "path-labs-service-catalog"
}

variable "service_catalog_portfolio_description" {
  description = "Description of the Service Catalog portfolio"
  type        = string
  default     = "Path Labs self-service product catalog (SharedServices Account)"
}

variable "service_catalog_provider_name" {
  description = "Provider name shown to end users in the Service Catalog portfolio"
  type        = string
  default     = "Path Labs Platform Team"
}

variable "service_catalog_principal_arns" {
  description = "IAM role/user ARNs allowed to launch products from the portfolio. Empty by default - the portfolio grants no launch access until populated."
  type        = list(string)
  default     = []
}

variable "service_catalog_launch_role_name" {
  description = "Name of the IAM role Service Catalog assumes to provision product resources"
  type        = string
  default     = "path-labs-service-catalog-launch-role"
}

variable "service_catalog_launch_role_policy_arns" {
  description = "Managed policy ARNs attached to the Service Catalog launch role, scoped to exactly what your products' CloudFormation templates need to create. Empty by default - the launch role has no permissions until populated."
  type        = list(string)
  default     = []
}

variable "service_catalog_products" {
  description = <<-EOT
    Products to register in the portfolio. Set exactly one of template_file
    (a template bundled under modules/service-catalog/cloudformation/products/,
    auto-uploaded to a module-owned S3 bucket) or template_url (an
    externally-hosted template) per product. Defaults to a bundled example
    catalog spanning storage, database, messaging, security, observability,
    compute, and networking so the module is immediately usable - set to []
    to go back to a fully inert portfolio, or add your own alongside/instead
    of the examples:

    [
      {
        name          = "my-product"
        owner         = "Path Labs Platform Team"
        description   = "..."
        template_url  = "https://my-bucket.s3.amazonaws.com/my-template.yaml"
      }
    ]
  EOT
  type = list(object({
    name            = string
    owner           = string
    description     = string
    template_file   = optional(string)
    template_url    = optional(string)
    constraint_type = optional(string, "LAUNCH")
  }))
  default = [
    # Storage
    {
      name          = "standard-s3-bucket"
      owner         = "Path Labs Platform Team"
      description   = "Private, encrypted, versioned S3 bucket with public access fully blocked"
      template_file = "standard-s3-bucket.yaml"
    },
    # Database
    {
      name          = "standard-dynamodb-table"
      owner         = "Path Labs Platform Team"
      description   = "On-demand DynamoDB table with encryption at rest and point-in-time recovery"
      template_file = "standard-dynamodb-table.yaml"
    },
    # Messaging
    {
      name          = "standard-sns-topic"
      owner         = "Path Labs Platform Team"
      description   = "KMS-encrypted SNS topic for application notifications/alerts"
      template_file = "standard-sns-topic.yaml"
    },
    {
      name          = "standard-sqs-queue"
      owner         = "Path Labs Platform Team"
      description   = "SSE-encrypted SQS queue with a companion dead-letter queue"
      template_file = "standard-sqs-queue.yaml"
    },
    # Security
    {
      name          = "standard-kms-key"
      owner         = "Path Labs Platform Team"
      description   = "Customer-managed KMS key with automatic annual rotation"
      template_file = "standard-kms-key.yaml"
    },
    {
      name          = "standard-secrets-manager-secret"
      owner         = "Path Labs Platform Team"
      description   = "Secrets Manager secret with an AWS-generated random value (no plaintext input)"
      template_file = "standard-secrets-manager-secret.yaml"
    },
    {
      name          = "standard-iam-readonly-role"
      owner         = "Path Labs Platform Team"
      description   = "IAM role restricted to a curated allowlist of read-only managed policies"
      template_file = "standard-iam-readonly-role.yaml"
    },
    # Observability
    {
      name          = "standard-log-group"
      owner         = "Path Labs Platform Team"
      description   = "CloudWatch Logs log group with bounded retention"
      template_file = "standard-log-group.yaml"
    },
    {
      name          = "standard-cloudwatch-alarm"
      owner         = "Path Labs Platform Team"
      description   = "CloudWatch metric alarm that notifies an existing SNS topic on breach"
      template_file = "standard-cloudwatch-alarm.yaml"
    },
    # Compute
    {
      name          = "standard-lambda-function"
      owner         = "Path Labs Platform Team"
      description   = "Lambda function with a placeholder handler and a dedicated logs-only execution role"
      template_file = "standard-lambda-function.yaml"
    },
    {
      name          = "standard-ecr-repository"
      owner         = "Path Labs Platform Team"
      description   = "ECR repository with scan-on-push and immutable tags"
      template_file = "standard-ecr-repository.yaml"
    },
    # Networking
    {
      name          = "standard-vpc"
      owner         = "Path Labs Platform Team"
      description   = "Minimal single-AZ VPC with one public and one private subnet (no NAT by default)"
      template_file = "standard-vpc.yaml"
    },
    {
      name          = "standard-route53-record"
      owner         = "Path Labs Platform Team"
      description   = "DNS record under a curated dropdown of this account's actual domains (path.app.presidio.com)"
      template_file = "standard-route53-record.yaml"
    },
    {
      name          = "standard-cloudfront-distribution"
      owner         = "Path Labs Platform Team"
      description   = "CloudFront distribution fronting an existing S3 bucket via Origin Access Control"
      template_file = "standard-cloudfront-distribution.yaml"
    },
    # Database
    {
      name          = "standard-rds-instance"
      owner         = "Path Labs Platform Team"
      description   = "Cost-conscious single-AZ RDS instance (Postgres/MySQL), encrypted, AWS-managed master password"
      template_file = "standard-rds-instance.yaml"
    },
    # Security
    {
      name          = "standard-acm-certificate"
      owner         = "Path Labs Platform Team"
      description   = "DNS-validated ACM certificate under a curated dropdown of this account's actual domains"
      template_file = "standard-acm-certificate.yaml"
    },
    # Integration / orchestration
    {
      name          = "standard-sfn-state-machine"
      owner         = "Path Labs Platform Team"
      description   = "Step Functions state machine skeleton with a dedicated logs-only execution role"
      template_file = "standard-sfn-state-machine.yaml"
    },
    {
      name          = "standard-eventbridge-schedule"
      owner         = "Path Labs Platform Team"
      description   = "EventBridge scheduled rule that publishes to an existing SNS topic"
      template_file = "standard-eventbridge-schedule.yaml"
    },
    # Compute
    {
      name          = "standard-ecs-cluster"
      owner         = "Path Labs Platform Team"
      description   = "Fargate-only ECS cluster with Container Insights enabled"
      template_file = "standard-ecs-cluster.yaml"
    },
    # Management / config
    {
      name          = "standard-ssm-parameter"
      owner         = "Path Labs Platform Team"
      description   = "Systems Manager Parameter Store parameter (String/StringList/SecureString)"
      template_file = "standard-ssm-parameter.yaml"
    },
    # Observability
    {
      name          = "standard-cloudwatch-dashboard"
      owner         = "Path Labs Platform Team"
      description   = "CloudWatch dashboard from user-supplied widget JSON"
      template_file = "standard-cloudwatch-dashboard.yaml"
    },
  ]
}

variable "service_catalog_templates_bucket_name" {
  description = "Name of the S3 bucket that hosts bundled product templates. Leave null to use the default \"path-labs-service-catalog-templates-<account-id>\"."
  type        = string
  default     = null
}

variable "service_catalog_attach_example_products_policy" {
  description = "Whether to attach the scoped IAM policy the bundled example products (standard-s3-bucket, standard-sns-topic) need to the launch role. No-op if those products aren't in service_catalog_products."
  type        = bool
  default     = true
}

################################################################################
# CloudFormation StackSet constraint (multi-account/region products)
################################################################################

variable "service_catalog_enable_stackset_products" {
  description = "Whether to create the StackSet administration role and STACKSET constraints for products with constraint_type = \"STACKSET\". False by default - no cross-account IAM trust exists until explicitly enabled."
  type        = bool
  default     = false
}

variable "service_catalog_stackset_admin_role_name" {
  description = "Name of the IAM role created in this (hub) account that CloudFormation StackSets assumes to deploy STACKSET-constrained products"
  type        = string
  default     = "path-labs-service-catalog-stackset-admin-role"
}

variable "service_catalog_stackset_execution_role_name" {
  description = "Name of the IAM role that must already exist in every account listed in service_catalog_stackset_target_accounts - deploy modules/service-catalog/cloudformation/stackset-execution-role.yaml there first"
  type        = string
  default     = "path-labs-service-catalog-stackset-execution-role"
}

variable "service_catalog_stackset_target_accounts" {
  description = "Account IDs STACKSET-constrained products may deploy into. Empty by default - populate before setting service_catalog_enable_stackset_products = true."
  type        = list(string)
  default     = []
}

variable "service_catalog_stackset_target_regions" {
  description = "Regions STACKSET-constrained products may deploy into"
  type        = list(string)
  default     = []
}

variable "service_catalog_stackset_allow_stack_instance_control" {
  description = "Whether end users may add/remove individual stack instances (accounts/regions) at provision time. False (NOT_ALLOWED) is the safer default."
  type        = bool
  default     = false
}

################################################################################
# AWS Organizations sharing - share the portfolio to every other account
################################################################################

variable "service_catalog_enable_organizations_access" {
  description = "Whether to enable Service Catalog's AWS Organizations integration in this account and share the portfolio to the entire organization. False by default. Requires this account to be the Organizations management account OR a registered delegated administrator for servicecatalog.amazonaws.com."
  type        = bool
  default     = false
}

variable "service_catalog_share_tag_options" {
  description = "Whether TagOptions associated with the portfolio are also shared to accounts the portfolio is shared with"
  type        = bool
  default     = false
}

variable "service_catalog_share_principals" {
  description = "Whether principal (IAM role/user) associations on the portfolio are also shared to accounts the portfolio is shared with"
  type        = bool
  default     = false
}

variable "service_catalog_share_account_ids" {
  description = "AWS account IDs to share the portfolio with directly (no Organizations management account required). Add every spoke account that needs access."
  type        = list(string)
  default     = ["853973692277"]
}

################################################################################
# Admin role (this hub account) - platform team members who manage the
# portfolio and its products
################################################################################

variable "service_catalog_create_admin_role" {
  description = "Whether to create the Service Catalog administrator IAM role in this (hub) account. False by default - no role exists until explicitly enabled and service_catalog_admin_principal_arns is populated."
  type        = bool
  default     = false
}

variable "service_catalog_admin_role_name" {
  description = "Name of the IAM role granted AWSServiceCatalogAdminFullAccess for managing this portfolio/its products"
  type        = string
  default     = "path-labs-service-catalog-admin-role"
}

variable "service_catalog_admin_principal_arns" {
  description = "IAM role/user ARNs (e.g. an SSO permission set role, or specific platform-team roles) allowed to assume the admin role. Required (non-empty) when service_catalog_create_admin_role = true."
  type        = list(string)
  default     = []
}

################################################################################
# Member role rollout (spoke accounts) - lets end users in every account the
# portfolio is shared with browse and launch products
################################################################################

variable "service_catalog_member_role_name" {
  description = "Name of the IAM role deployed (via modules/service-catalog/cloudformation/member-account-role.yaml) in every member account, granting AWSServiceCatalogEndUserFullAccess"
  type        = string
  default     = "path-labs-service-catalog-member-role"
}

variable "service_catalog_member_role_trusted_principal_arns" {
  description = "Principal ARNs (e.g. an IAM Identity Center permission set role) trusted to assume the member role in each spoke account. Required (non-empty) when service_catalog_enable_member_role_stackset = true."
  type        = list(string)
  default     = []
}

variable "service_catalog_enable_member_role_stackset" {
  description = "Whether to create a SERVICE_MANAGED CloudFormation StackSet that auto-deploys the member role to every account under service_catalog_member_stackset_organizational_unit_ids. False by default - requires AWS Organizations trusted access for CloudFormation StackSets to already be enabled by the Organizations management account."
  type        = bool
  default     = false
}

variable "service_catalog_member_stackset_organizational_unit_ids" {
  description = "Organizational Unit IDs (or the org root ID, to target every account in the organization) the member role StackSet auto-deploys to. Required when service_catalog_enable_member_role_stackset = true."
  type        = list(string)
  default     = []
}

variable "service_catalog_member_stackset_region" {
  description = "Single region the member role StackSet instance is created in (the member role itself is IAM, which is global). Required when service_catalog_enable_member_role_stackset = true."
  type        = string
  default     = null
}

################################################################################
# Cross-account Route 53 custom resource (Option B)
################################################################################

variable "service_catalog_enable_cross_account_route53_handler" {
  description = "Whether to deploy the Lambda-backed CloudFormation custom resource that lets stacks in OTHER accounts manage records in this account's curated Route 53 zone. False by default."
  type        = bool
  default     = false
}

variable "service_catalog_cross_account_route53_handler_function_name" {
  description = "Name of the cross-account Route 53 handler Lambda function. Must match the ServiceToken hardcoded in cloudformation/products/standard-route53-record-cross-account.yaml if changed."
  type        = string
  default     = "path-labs-service-catalog-route53-cross-account-handler"
}

variable "service_catalog_cross_account_route53_invoker_principal_arns" {
  description = "Principal ARNs (typically another account's Service Catalog launch role) allowed to invoke the cross-account Route 53 handler Lambda. Empty by default."
  type        = list(string)
  default     = []
}

################################################################################
# Outputs
################################################################################

output "service_catalog_portfolio_id" {
  description = "ID of the Service Catalog portfolio"
  value       = module.service_catalog.portfolio_id
}

output "service_catalog_portfolio_arn" {
  description = "ARN of the Service Catalog portfolio"
  value       = module.service_catalog.portfolio_arn
}

output "service_catalog_launch_role_arn" {
  description = "ARN of the IAM role Service Catalog assumes to provision products - attach policy_arns via var.service_catalog_launch_role_policy_arns as you add products"
  value       = module.service_catalog.launch_role_arn
}

output "service_catalog_stackset_admin_role_arn" {
  description = "ARN of the StackSet administration role in this account - pass as AdministrationRoleArn when deploying modules/service-catalog/cloudformation/stackset-execution-role.yaml to each target account"
  value       = module.service_catalog.stackset_admin_role_arn
}

output "service_catalog_organization_arn" {
  description = "ARN of the AWS Organization the portfolio is shared with (null unless service_catalog_enable_organizations_access = true)"
  value       = module.service_catalog.organization_arn
}

output "service_catalog_portfolio_share_id" {
  description = "ID of the organization-wide portfolio share (null unless service_catalog_enable_organizations_access = true)"
  value       = module.service_catalog.portfolio_share_id
}

output "service_catalog_admin_role_arn" {
  description = "ARN of the Service Catalog admin role in this (hub) account (null unless service_catalog_create_admin_role = true)"
  value       = module.service_catalog.admin_role_arn
}

output "service_catalog_member_role_stackset_id" {
  description = "ID of the member-account-role StackSet (null unless service_catalog_enable_member_role_stackset = true)"
  value       = module.service_catalog.member_role_stackset_id
}

output "service_catalog_templates_bucket_name" {
  description = "S3 bucket hosting the bundled example product templates"
  value       = module.service_catalog.templates_bucket_name
}

output "service_catalog_account_share_ids" {
  description = "Map of account ID to portfolio share ID for direct account shares"
  value       = module.service_catalog.account_share_ids
}

output "service_catalog_cross_account_route53_handler_arn" {
  description = "ARN of the cross-account Route 53 handler Lambda (null unless service_catalog_enable_cross_account_route53_handler = true)"
  value       = module.service_catalog.cross_account_route53_handler_arn
}
