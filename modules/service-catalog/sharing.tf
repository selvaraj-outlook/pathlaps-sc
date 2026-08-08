################################################################################
# Service Catalog Module - AWS Organizations Sharing + Admin Role
#
# Lets this (hub/SharedServices) account share the portfolio to every other
# account in the AWS Organization, and defines the admin role platform-team
# members assume in THIS account to manage the portfolio/products. The
# corresponding end-user (member) role for the SPOKE accounts is in
# member-accounts.tf / cloudformation/member-account-role.yaml.
################################################################################

# Account-level toggle: lets Service Catalog share portfolios using AWS
# Organizations principals (ORGANIZATION / ORGANIZATIONAL_UNIT /
# ORGANIZATION_MEMBER_ACCOUNT) instead of one aws_servicecatalog_portfolio_share
# per account. Requires this account to be the Organizations management
# account or a delegated administrator for servicecatalog.amazonaws.com.
resource "aws_servicecatalog_organizations_access" "this" {
  count = var.enable_organizations_access ? 1 : 0

  enabled = true
}

data "aws_organizations_organization" "this" {
  count = var.enable_organizations_access ? 1 : 0
}

# Shares the portfolio with every account in the organization in one shot.
resource "aws_servicecatalog_portfolio_share" "organization" {
  count = var.enable_organizations_access ? 1 : 0

  portfolio_id      = aws_servicecatalog_portfolio.this.id
  type              = "ORGANIZATION"
  principal_id      = data.aws_organizations_organization.this[0].arn
  share_tag_options = var.share_tag_options
  share_principals  = var.share_principals

  depends_on = [aws_servicecatalog_organizations_access.this]
}

# ------------------------------------------------------------------------------
# Direct account-to-account shares
# One aws_servicecatalog_portfolio_share per entry in var.share_account_ids.
# Does NOT require this account to be the Organizations management account -
# works from any account as long as the target account ID is known.
# ------------------------------------------------------------------------------
resource "aws_servicecatalog_portfolio_share" "account" {
  for_each = toset(var.share_account_ids)

  portfolio_id      = aws_servicecatalog_portfolio.this.id
  type              = "ACCOUNT"
  principal_id      = each.value
  share_tag_options = var.share_tag_options
  share_principals  = var.share_principals
}

# ------------------------------------------------------------------------------
# Admin role (this account) - platform team members who manage the portfolio
# ------------------------------------------------------------------------------

data "aws_iam_policy_document" "admin_assume_role" {
  count = var.create_admin_role ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = var.admin_principal_arns
    }
  }
}

resource "aws_iam_role" "admin" {
  count = var.create_admin_role ? 1 : 0

  name               = var.admin_role_name
  assume_role_policy = data.aws_iam_policy_document.admin_assume_role[0].json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "admin" {
  count = var.create_admin_role ? 1 : 0

  role       = aws_iam_role.admin[0].name
  policy_arn = "arn:aws:iam::aws:policy/AWSServiceCatalogAdminFullAccess"
}
