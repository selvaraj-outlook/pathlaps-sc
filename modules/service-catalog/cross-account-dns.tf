################################################################################
# Service Catalog Module - Cross-Account Route 53 Custom Resource (Option B)
#
# Lets a CloudFormation stack running in ANOTHER account invoke a Lambda
# HERE (the hub account) to manage records in the one curated hosted zone
# this module already trusts (same zone as StandardRoute53RecordProduct in
# constraints.tf). This is the "centralize DNS in the hub, no subdomain
# delegation" option - see the "Cross-account Route 53" section of README.md
# for the tradeoffs against delegating a subdomain per account instead.
#
# Off by default (enable_cross_account_route53_handler = false): no Lambda,
# no execution role, no cross-account trust exists until explicitly enabled.
# Even then, no OTHER account can invoke it until
# cross_account_route53_invoker_principal_arns is populated with the
# specific principal ARN(s) allowed to call it.
################################################################################

data "archive_file" "route53_cross_account_handler" {
  count = var.enable_cross_account_route53_handler ? 1 : 0

  type        = "zip"
  source_dir  = "${path.module}/lambda/route53_cross_account_handler"
  output_path = "${path.module}/lambda/.build/route53_cross_account_handler.zip"
}

data "aws_iam_policy_document" "route53_cross_account_handler_assume_role" {
  count = var.enable_cross_account_route53_handler ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "route53_cross_account_handler" {
  count = var.enable_cross_account_route53_handler ? 1 : 0

  name               = "${var.cross_account_route53_handler_function_name}-role"
  assume_role_policy = data.aws_iam_policy_document.route53_cross_account_handler_assume_role[0].json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "route53_cross_account_handler_logs" {
  count = var.enable_cross_account_route53_handler ? 1 : 0

  role       = aws_iam_role.route53_cross_account_handler[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Same hosted-zone allowlist as StandardRoute53RecordProduct in
# constraints.tf, and ALLOWED_HOSTED_ZONE_IDS in
# lambda/route53_cross_account_handler/index.py - all three must be updated
# together when a new domain is onboarded (see README.md).
resource "aws_iam_role_policy" "route53_cross_account_handler_permissions" {
  count = var.enable_cross_account_route53_handler ? 1 : 0

  name = "Route53ChangeAllowlistedZone"
  role = aws_iam_role.route53_cross_account_handler[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ChangeAllowlistedHostedZone"
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets",
          "route53:ListResourceRecordSets",
          "route53:GetHostedZone",
        ]
        Resource = ["arn:aws:route53:::hostedzone/Z048880320A4YLK98LLYY"]
      },
      {
        Sid      = "ChangeStatus"
        Effect   = "Allow"
        Action   = "route53:GetChange"
        Resource = "arn:aws:route53:::change/*"
      },
    ]
  })
}

resource "aws_lambda_function" "route53_cross_account_handler" {
  count = var.enable_cross_account_route53_handler ? 1 : 0

  function_name    = var.cross_account_route53_handler_function_name
  role             = aws_iam_role.route53_cross_account_handler[0].arn
  handler          = "index.handler"
  runtime          = "python3.12"
  timeout          = 30
  filename         = data.archive_file.route53_cross_account_handler[0].output_path
  source_code_hash = data.archive_file.route53_cross_account_handler[0].output_base64sha256

  tags = var.tags
}

# One statement per trusted invoker - each entry is a specific principal ARN
# (typically another account's Service Catalog launch role), not a bare
# account ID, to keep this as narrow as the rest of the module's IAM design.
resource "aws_lambda_permission" "route53_cross_account_handler_invoke" {
  for_each = var.enable_cross_account_route53_handler ? toset(var.cross_account_route53_invoker_principal_arns) : toset([])

  # statement_id must be unique per invoker and alphanumeric-ish; derive a
  # short stable suffix from the principal ARN rather than trying to
  # sanitize the whole ARN into one.
  statement_id  = "AllowInvoke${substr(md5(each.value), 0, 16)}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.route53_cross_account_handler[0].function_name
  principal     = each.value
}
