################################################################################
# Service Catalog Module - CloudFormation StackSet Constraint
#
# Backs products whose constraint_type = "STACKSET" (see variables.tf/main.tf):
# Service Catalog deploys that product's CloudFormation template as a
# StackSet across stackset_target_accounts / stackset_target_regions, instead
# of a single LAUNCH-role deployment in this account.
#
# Two IAM roles are required (standard AWS CloudFormation StackSet
# self-managed-permissions pattern):
#   - Administration role (created here, in THIS/hub account): trusted by
#     cloudformation.amazonaws.com, allowed to assume the execution role in
#     each target account.
#   - Execution role (created in EACH TARGET account, NOT by this module -
#     see cloudformation/stackset-execution-role.yaml, deployed the same
#     out-of-band way modules/arena-nuke's execution role is deployed to
#     sandbox accounts): trusts the administration role, holds the actual
#     permissions needed to create the STACKSET product's resources.
################################################################################

data "aws_iam_policy_document" "stackset_admin_assume_role" {
  count = var.enable_stackset_products ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["cloudformation.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "stackset_admin_assume_execution_role" {
  count = var.enable_stackset_products ? 1 : 0

  statement {
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = ["arn:aws:iam::*:role/${var.stackset_execution_role_name}"]
  }
}

resource "aws_iam_role" "stackset_admin" {
  count = var.enable_stackset_products ? 1 : 0

  name               = var.stackset_admin_role_name
  assume_role_policy = data.aws_iam_policy_document.stackset_admin_assume_role[0].json

  tags = var.tags
}

resource "aws_iam_role_policy" "stackset_admin_assume_execution" {
  count = var.enable_stackset_products ? 1 : 0

  name   = "AssumeStackSetExecutionRole"
  role   = aws_iam_role.stackset_admin[0].id
  policy = data.aws_iam_policy_document.stackset_admin_assume_execution_role[0].json
}

resource "aws_servicecatalog_constraint" "stackset" {
  for_each = var.enable_stackset_products ? {
    for p in var.products : p.name => p
    if p.constraint_type == "STACKSET"
  } : {}

  description  = "StackSet deployment for ${each.key}"
  portfolio_id = aws_servicecatalog_portfolio.this.id
  product_id   = aws_servicecatalog_product.this[each.key].id
  type         = "STACKSET"

  parameters = jsonencode({
    AccountList          = var.stackset_target_accounts
    RegionList           = var.stackset_target_regions
    AdminRole            = aws_iam_role.stackset_admin[0].arn
    ExecutionRole        = var.stackset_execution_role_name
    StackInstanceControl = var.stackset_allow_stack_instance_control ? "ALLOWED" : "NOT_ALLOWED"
  })

  depends_on = [aws_servicecatalog_product_portfolio_association.this]
}
