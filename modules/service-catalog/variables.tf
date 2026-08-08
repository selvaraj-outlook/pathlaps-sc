################################################################################
# Service Catalog Module - Variables
################################################################################

variable "name" {
  description = "Name of the Service Catalog portfolio"
  type        = string
}

variable "description" {
  description = "Description of the Service Catalog portfolio"
  type        = string
}

variable "provider_name" {
  description = "Provider name shown to end users in the Service Catalog portfolio"
  type        = string
}

variable "principal_arns" {
  description = "IAM role/user ARNs allowed to launch products from the portfolio. Empty by default - the portfolio grants no launch access until populated."
  type        = list(string)
  default     = []
}

variable "launch_role_name" {
  description = "Name of the IAM role Service Catalog assumes to provision product resources"
  type        = string
}

variable "launch_role_policy_arns" {
  description = "Managed policy ARNs attached to the Service Catalog launch role, scoped to exactly what your products' CloudFormation templates need to create. Empty by default - the launch role has no permissions until populated."
  type        = list(string)
  default     = []
}

variable "products" {
  description = "Products to register in the portfolio. Leave empty ([]) until a CloudFormation template exists to back a product. Set exactly one of template_file (a template bundled under cloudformation/products/, auto-uploaded to the templates bucket) or template_url (an externally-hosted template). constraint_type selects how the product is provisioned: \"LAUNCH\" (default, this account via launch_role) or \"STACKSET\" (multi-account/region via CloudFormation StackSets - see stackset.tf, requires enable_stackset_products = true)."
  type = list(object({
    name            = string
    owner           = string
    description     = string
    template_file   = optional(string)
    template_url    = optional(string)
    constraint_type = optional(string, "LAUNCH")
  }))
  default = []

  validation {
    condition     = alltrue([for p in var.products : contains(["LAUNCH", "STACKSET"], p.constraint_type)])
    error_message = "constraint_type must be either \"LAUNCH\" or \"STACKSET\"."
  }

  validation {
    condition     = alltrue([for p in var.products : (p.template_file != null) != (p.template_url != null)])
    error_message = "Each product must set exactly one of template_file or template_url, not both and not neither."
  }
}

variable "templates_bucket_name" {
  description = "Name of the S3 bucket that hosts bundled product templates (cloudformation/products/*.yaml, referenced via a product's template_file). Leave null to use the default \"path-labs-service-catalog-templates-<account-id>\". Only created if at least one product sets template_file."
  type        = string
  default     = null
}

variable "attach_example_products_policy" {
  description = "Whether to attach a least-privilege IAM policy to the launch role scoped to exactly what the bundled example products (standard-s3-bucket, standard-sns-topic) create. Has no effect if those products aren't in var.products. True by default so the bundled examples work out of the box."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to Service Catalog resources"
  type        = map(string)
  default     = {}
}

################################################################################
# CloudFormation StackSet constraint (multi-account/region products)
################################################################################

variable "enable_stackset_products" {
  description = "Whether to create the StackSet administration role and STACKSET constraints for products with constraint_type = \"STACKSET\". False by default - no cross-account IAM trust exists until explicitly enabled."
  type        = bool
  default     = false
}

variable "stackset_admin_role_name" {
  description = "Name of the IAM role created in THIS (hub) account that CloudFormation StackSets assumes to deploy STACKSET-constrained products. Trusts cloudformation.amazonaws.com and may assume stackset_execution_role_name in each target account."
  type        = string
  default     = "path-labs-service-catalog-stackset-admin-role"
}

variable "stackset_execution_role_name" {
  description = "Name (not ARN - StackSets looks this up by name in each target account) of the IAM role that must already exist in every account listed in stackset_target_accounts. This module does NOT create it - deploy cloudformation/stackset-execution-role.yaml in each target account (e.g. via an Organizations StackSet or the same out-of-band mechanism used for modules/arena-nuke's execution role)."
  type        = string
  default     = "path-labs-service-catalog-stackset-execution-role"
}

variable "stackset_target_accounts" {
  description = "Account IDs STACKSET-constrained products may deploy into. Empty by default - populate before setting enable_stackset_products = true."
  type        = list(string)
  default     = []
}

variable "stackset_target_regions" {
  description = "Regions STACKSET-constrained products may deploy into."
  type        = list(string)
  default     = []
}

variable "stackset_allow_stack_instance_control" {
  description = "Whether end users may add/remove individual stack instances (accounts/regions) at provision time, beyond stackset_target_accounts/stackset_target_regions. False (NOT_ALLOWED) is the safer default."
  type        = bool
  default     = false
}

################################################################################
# AWS Organizations sharing - share the portfolio from this (hub) account to
# every other account in the organization
################################################################################

variable "enable_organizations_access" {
  description = "Whether to enable Service Catalog's AWS Organizations integration in this account and share the portfolio to the entire organization. False by default. Requires this account to be the Organizations management account OR a registered delegated administrator for servicecatalog.amazonaws.com - otherwise the AWS API call fails."
  type        = bool
  default     = false
}

variable "share_tag_options" {
  description = "Whether TagOptions associated with the portfolio are also shared to accounts the portfolio is shared with"
  type        = bool
  default     = false
}

variable "share_principals" {
  description = "Whether principal (IAM role/user) associations on the portfolio are also shared to accounts the portfolio is shared with"
  type        = bool
  default     = false
}

variable "share_account_ids" {
  description = "List of AWS account IDs to share this portfolio with directly (account-to-account share, no Organizations management account required). Each account must accept the share and have an IAM principal granted launch access."
  type        = list(string)
  default     = []
}

################################################################################
# Admin role (hub account) - platform team members who manage the portfolio
# and its products
################################################################################

variable "create_admin_role" {
  description = "Whether to create the Service Catalog administrator IAM role in this (hub) account. False by default - no role exists until explicitly enabled and admin_principal_arns is populated."
  type        = bool
  default     = false
}

variable "admin_role_name" {
  description = "Name of the IAM role granted AWSServiceCatalogAdminFullAccess for managing this portfolio/its products"
  type        = string
  default     = "path-labs-service-catalog-admin-role"
}

variable "admin_principal_arns" {
  description = "IAM role/user ARNs (e.g. an SSO permission set role, or specific platform-team roles) allowed to assume admin_role_name. Required (non-empty) when create_admin_role = true."
  type        = list(string)
  default     = []

  validation {
    condition     = !var.create_admin_role || length(var.admin_principal_arns) > 0
    error_message = "admin_principal_arns must contain at least one ARN when create_admin_role = true."
  }
}

################################################################################
# Member role (spoke accounts) - deployed to every account the portfolio is
# shared with, so end users there can browse and launch shared products.
# NOT created by this module (this module only manages the hub account) -
# see cloudformation/member-account-role.yaml. enable_member_role_stackset
# below optionally deploys that template org-wide via a Terraform-managed
# CloudFormation StackSet, IF this account already has AWS Organizations
# trusted access enabled for CloudFormation StackSets (a one-time, separate
# management-account setting - not something this module can turn on).
################################################################################

variable "member_role_name" {
  description = "Name of the IAM role deployed (via cloudformation/member-account-role.yaml) in every member account, granting AWSServiceCatalogEndUserFullAccess"
  type        = string
  default     = "path-labs-service-catalog-member-role"
}

variable "member_role_trusted_principal_arns" {
  description = "Principal ARNs (e.g. an IAM Identity Center permission set role, or a specific federated role pattern) trusted to assume member_role_name in each spoke account. Required (non-empty) when enable_member_role_stackset = true."
  type        = list(string)
  default     = []
}

variable "enable_member_role_stackset" {
  description = "Whether to create a SERVICE_MANAGED CloudFormation StackSet that auto-deploys cloudformation/member-account-role.yaml to every account under member_stackset_organizational_unit_ids. False by default - deploy that template out-of-band (e.g. a manually-run StackSet from the Organizations management account) until this and its prerequisites are ready."
  type        = bool
  default     = false
}

variable "member_stackset_organizational_unit_ids" {
  description = "Organizational Unit IDs (or the org root ID, to target every account in the organization) the member role StackSet auto-deploys to. Required when enable_member_role_stackset = true."
  type        = list(string)
  default     = []
}

variable "member_stackset_region" {
  description = "Single region the member role StackSet instance is created in (the member role itself is IAM, which is global, so one region is sufficient). Required when enable_member_role_stackset = true."
  type        = string
  default     = null
}

################################################################################
# Cross-account Route 53 custom resource (Option B - see cross-account-dns.tf
# and the "Cross-account Route 53" section of README.md)
################################################################################

variable "enable_cross_account_route53_handler" {
  description = "Whether to deploy the Lambda-backed CloudFormation custom resource that lets stacks in OTHER accounts manage records in this account's curated Route53 zone. False by default - no Lambda, no execution role, no cross-account trust exists until explicitly enabled."
  type        = bool
  default     = false
}

variable "cross_account_route53_handler_function_name" {
  description = "Name of the cross-account Route53 handler Lambda function. Must match the hardcoded function name in cloudformation/products/standard-route53-record-cross-account.yaml's ServiceToken if you change this from the default."
  type        = string
  default     = "path-labs-service-catalog-route53-cross-account-handler"
}

variable "cross_account_route53_invoker_principal_arns" {
  description = "Principal ARNs (typically another account's Service Catalog launch role) allowed to invoke the cross-account Route53 handler Lambda. Empty by default - no other account can invoke it until populated, even when enable_cross_account_route53_handler = true."
  type        = list(string)
  default     = []
}
