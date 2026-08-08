################################################################################
# Service Catalog Module - Member Account Role Rollout (optional)
#
# Auto-deploys cloudformation/member-account-role.yaml to every account under
# member_stackset_organizational_unit_ids via a SERVICE_MANAGED CloudFormation
# StackSet, so end users in spoke accounts get the IAM role needed to launch
# products shared from this hub account.
#
# Disabled by default (enable_member_role_stackset = false). Turning it on
# requires AWS Organizations trusted access for CloudFormation StackSets to
# already be enabled by the Organizations management account - a one-time,
# separate setting this module cannot itself grant. Until then, deploy
# member-account-role.yaml out-of-band instead (see that file's header).
################################################################################

resource "aws_cloudformation_stack_set" "member_role" {
  count = var.enable_member_role_stackset ? 1 : 0

  name             = "path-labs-service-catalog-member-role"
  description      = "Deploys the Service Catalog end-user role (member-account-role.yaml) across the organization"
  permission_model = "SERVICE_MANAGED"
  capabilities     = ["CAPABILITY_NAMED_IAM"]

  auto_deployment {
    enabled                          = true
    retain_stacks_on_account_removal = false
  }

  template_body = file("${path.module}/cloudformation/member-account-role.yaml")

  parameters = {
    RoleName             = var.member_role_name
    TrustedPrincipalArns = join(",", var.member_role_trusted_principal_arns)
  }

  tags = var.tags
}

resource "aws_cloudformation_stack_set_instance" "member_role" {
  count = var.enable_member_role_stackset ? 1 : 0

  stack_set_name            = aws_cloudformation_stack_set.member_role[0].name
  stack_set_instance_region = var.member_stackset_region

  deployment_targets {
    organizational_unit_ids = var.member_stackset_organizational_unit_ids
  }
}
