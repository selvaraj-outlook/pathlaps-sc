################################################################################
# Service Catalog Module - Launch Role + Constraint
#
# Service Catalog assumes this role (not the end user's own identity) to
# actually create a product's resources, so the end user needs no permissions
# beyond "launch products in this portfolio". Keep launch_role_policy_arns
# scoped to exactly what the registered products' CloudFormation templates
# create - never attach broad/admin policies here.
################################################################################

locals {
  # Must exactly match cloudformation/products/standard-iam-readonly-role.yaml's
  # ManagedPolicyName AllowedValues (plus the fixed Lambda basic-execution
  # policy standard-lambda-function.yaml always attaches) - this is the
  # complete set of managed policies the launch role is ever allowed to
  # attach via iam:AttachRolePolicy below. Adding a policy here without also
  # adding it to that template's AllowedValues (or vice versa) breaks that
  # product; adding an overly-broad policy here reopens the privilege-
  # escalation path the iam:PolicyARN condition exists to close.
  allowed_managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole",
    "arn:aws:iam::aws:policy/ReadOnlyAccess",
    "arn:aws:iam::aws:policy/ViewOnlyAccess",
    "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess",
    "arn:aws:iam::aws:policy/AmazonDynamoDBReadOnlyAccess",
    "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess",
    "arn:aws:iam::aws:policy/AWSCloudFormationReadOnlyAccess",
  ]
}

data "aws_iam_policy_document" "launch_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["servicecatalog.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "launch" {
  name               = var.launch_role_name
  assume_role_policy = data.aws_iam_policy_document.launch_assume_role.json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "launch" {
  for_each = toset(var.launch_role_policy_arns)

  role       = aws_iam_role.launch.name
  policy_arn = each.value
}

# Least-privilege permissions for the bundled example products (data/storage/
# messaging/observability services - see cloudformation/products/*.yaml).
# No-op for any product not present in var.products. Split into two policies
# (this one + launch_example_products_iam_compute below) to stay well under
# the 6,144-char limit on a single customer-managed IAM policy - the root
# AGENTS.md documents hitting this limit before on ArenaNukeManagementPolicy.
resource "aws_iam_policy" "launch_example_products" {
  count = var.attach_example_products_policy ? 1 : 0

  name        = "${var.launch_role_name}-example-products"
  description = "Scoped permissions for the bundled Service Catalog example products (storage/data/messaging/observability)"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "StandardS3BucketProduct"
        Effect = "Allow"
        Action = [
          "s3:CreateBucket",
          "s3:DeleteBucket",
          "s3:PutBucketVersioning",
          "s3:PutEncryptionConfiguration",
          "s3:PutBucketPublicAccessBlock",
          "s3:PutBucketTagging",
          "s3:GetBucketTagging",
        ]
        Resource = "arn:aws:s3:::*"
      },
      {
        Sid    = "StandardSnsTopicProduct"
        Effect = "Allow"
        Action = [
          "sns:CreateTopic",
          "sns:DeleteTopic",
          "sns:SetTopicAttributes",
          "sns:GetTopicAttributes",
          "sns:TagResource",
        ]
        Resource = "arn:aws:sns:*:*:*"
      },
      {
        Sid    = "StandardSqsQueueProduct"
        Effect = "Allow"
        Action = [
          "sqs:CreateQueue",
          "sqs:DeleteQueue",
          "sqs:SetQueueAttributes",
          "sqs:GetQueueAttributes",
          "sqs:TagQueue",
        ]
        Resource = "arn:aws:sqs:*:*:*"
      },
      {
        Sid    = "StandardDynamodbTableProduct"
        Effect = "Allow"
        Action = [
          "dynamodb:CreateTable",
          "dynamodb:DeleteTable",
          "dynamodb:DescribeTable",
          "dynamodb:TagResource",
          "dynamodb:UpdateContinuousBackups",
          "dynamodb:DescribeContinuousBackups",
        ]
        Resource = "arn:aws:dynamodb:*:*:table/*"
      },
      {
        Sid    = "StandardKmsKeyProduct"
        Effect = "Allow"
        Action = [
          "kms:CreateKey",
          "kms:CreateAlias",
          "kms:DeleteAlias",
          "kms:EnableKeyRotation",
          "kms:DescribeKey",
          "kms:GetKeyPolicy",
          "kms:GetKeyRotationStatus",
          "kms:PutKeyPolicy",
          "kms:TagResource",
          "kms:ScheduleKeyDeletion",
        ]
        # KMS CreateKey has no ARN to scope to before the key exists - AWS's
        # own examples for this action use Resource "*".
        Resource = "*"
      },
      {
        Sid    = "StandardLogGroupProduct"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:DeleteLogGroup",
          "logs:PutRetentionPolicy",
          "logs:TagResource",
          "logs:DescribeLogGroups",
        ]
        Resource = "arn:aws:logs:*:*:log-group:*"
      },
      {
        Sid    = "StandardSecretsManagerSecretProduct"
        Effect = "Allow"
        Action = [
          "secretsmanager:CreateSecret",
          "secretsmanager:DeleteSecret",
          "secretsmanager:TagResource",
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetResourcePolicy",
        ]
        Resource = "arn:aws:secretsmanager:*:*:secret:*"
      },
      {
        Sid    = "StandardEcrRepositoryProduct"
        Effect = "Allow"
        Action = [
          "ecr:CreateRepository",
          "ecr:DeleteRepository",
          "ecr:TagResource",
          "ecr:PutImageScanningConfiguration",
          "ecr:PutImageTagMutability",
          "ecr:DescribeRepositories",
        ]
        Resource = "arn:aws:ecr:*:*:repository/*"
      },
      {
        Sid    = "StandardCloudwatchAlarmProduct"
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricAlarm",
          "cloudwatch:DeleteAlarms",
          "cloudwatch:DescribeAlarms",
          "cloudwatch:TagResource",
        ]
        Resource = "arn:aws:cloudwatch:*:*:alarm:*"
      },
      {
        # Scoped to the exact hosted zone(s) in
        # cloudformation/products/standard-route53-record.yaml's
        # DomainHostedZones mapping - NOT "*". Adding a domain to that
        # template's AllowedValues/mapping without also adding its zone ARN
        # here means the product's own CFN deployment fails with
        # AccessDenied, which is the intended fail-safe (never widen this to
        # "arn:aws:route53:::hostedzone/*").
        Sid    = "StandardRoute53RecordProduct"
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets",
          "route53:ListResourceRecordSets",
          "route53:GetHostedZone",
        ]
        Resource = ["arn:aws:route53:::hostedzone/Z048880320A4YLK98LLYY"]
      },
      {
        Sid      = "StandardRoute53RecordProductChangeStatus"
        Effect   = "Allow"
        Action   = "route53:GetChange"
        Resource = "arn:aws:route53:::change/*"
      },
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "launch_example_products" {
  count = var.attach_example_products_policy ? 1 : 0

  role       = aws_iam_role.launch.name
  policy_arn = aws_iam_policy.launch_example_products[0].arn
}

# Second policy: IAM-role-creating and account-wide-networking example
# products (standard-iam-readonly-role.yaml, standard-lambda-function.yaml,
# standard-vpc.yaml). Kept SEPARATE from the policy above (not just for size)
# so the more sensitive iam:CreateRole/iam:AttachRolePolicy grant is easy to
# find and audit on its own.
#
# SECURITY NOTE: iam:AttachRolePolicy is restricted via an iam:PolicyARN
# condition to the exact managed-policy ARNs the bundled templates are
# allowed to attach (AWSLambdaBasicExecutionRole + the curated read-only
# allowlist baked into standard-iam-readonly-role.yaml's ManagedPolicyName
# AllowedValues) - this closes the obvious privilege-escalation path where a
# product could otherwise attach AdministratorAccess via this same launch
# role. If you add a product that needs to attach a different managed
# policy, add its ARN to allowed_managed_policy_arns below rather than
# widening the condition to "*".
resource "aws_iam_policy" "launch_example_products_iam_compute" {
  count = var.attach_example_products_policy ? 1 : 0

  name        = "${var.launch_role_name}-example-products-iam-compute"
  description = "Scoped permissions for the bundled IAM-role-creating and compute/networking example products"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CreateProductExecutionRoles"
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:GetRole",
          "iam:TagRole",
        ]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/*"
      },
      {
        Sid      = "AttachOnlyAllowlistedManagedPolicies"
        Effect   = "Allow"
        Action   = ["iam:AttachRolePolicy", "iam:DetachRolePolicy"]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/*"
        Condition = {
          ArnEquals = {
            "iam:PolicyARN" = local.allowed_managed_policy_arns
          }
        }
      },
      {
        Sid      = "PassProductExecutionRoleToOwningServiceOnly"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/*-execution-role"
        Condition = {
          StringEquals = {
            # lambda.amazonaws.com: standard-lambda-function.yaml
            # states.amazonaws.com: standard-sfn-state-machine.yaml
            "iam:PassedToService" = ["lambda.amazonaws.com", "states.amazonaws.com"]
          }
        }
      },
      {
        # standard-sfn-state-machine.yaml's execution role has one FIXED,
        # template-authored inline policy (CloudWatch Logs delivery actions
        # only) - end users can't influence its content through any CFN
        # Parameter, so this grant (unlike AttachRolePolicy above) has no
        # equivalent content-based IAM condition to restrict it with. The
        # trust boundary here is "who can edit templates in this repo", the
        # same as everywhere else in this module - not "who can launch
        # products". Do not reuse this Sid's resource pattern for a product
        # whose inline policy content IS user-parameterized.
        Sid    = "PutInlinePolicyOnProductExecutionRoles"
        Effect = "Allow"
        Action = [
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:GetRolePolicy",
        ]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/*-execution-role"
      },
      {
        Sid    = "StandardSfnStateMachineProduct"
        Effect = "Allow"
        Action = [
          "states:CreateStateMachine",
          "states:DeleteStateMachine",
          "states:DescribeStateMachine",
          "states:UpdateStateMachine",
          "states:TagResource",
        ]
        Resource = "arn:aws:states:*:*:stateMachine:*"
      },
      {
        Sid    = "StandardLambdaFunctionProduct"
        Effect = "Allow"
        Action = [
          "lambda:CreateFunction",
          "lambda:DeleteFunction",
          "lambda:GetFunction",
          "lambda:TagResource",
          "lambda:UpdateFunctionConfiguration",
        ]
        Resource = "arn:aws:lambda:*:*:function:*"
      },
      {
        Sid    = "StandardVpcProduct"
        Effect = "Allow"
        Action = [
          "ec2:CreateVpc", "ec2:DeleteVpc", "ec2:ModifyVpcAttribute", "ec2:DescribeVpcs",
          "ec2:CreateSubnet", "ec2:DeleteSubnet", "ec2:ModifySubnetAttribute", "ec2:DescribeSubnets",
          "ec2:CreateInternetGateway", "ec2:DeleteInternetGateway", "ec2:AttachInternetGateway", "ec2:DetachInternetGateway", "ec2:DescribeInternetGateways",
          "ec2:CreateRouteTable", "ec2:DeleteRouteTable", "ec2:CreateRoute", "ec2:DeleteRoute", "ec2:AssociateRouteTable", "ec2:DisassociateRouteTable", "ec2:DescribeRouteTables",
          "ec2:AllocateAddress", "ec2:ReleaseAddress", "ec2:DescribeAddresses",
          "ec2:CreateNatGateway", "ec2:DeleteNatGateway", "ec2:DescribeNatGateways",
          "ec2:CreateTags",
        ]
        # EC2 networking actions largely don't support resource-level ARN
        # scoping before the resource exists - this mirrors the "*" pattern
        # this repo already uses for KMS CreateKey above.
        Resource = "*"
      },
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "launch_example_products_iam_compute" {
  count = var.attach_example_products_policy ? 1 : 0

  role       = aws_iam_role.launch.name
  policy_arn = aws_iam_policy.launch_example_products_iam_compute[0].arn
}

# Third policy: remaining bundled example products (database, CDN,
# integration, certificates, config, containers) added after the first two
# policies were already sized close to comfortable - kept separate mainly to
# leave headroom under the 6,144-char single-policy limit, not for a
# thematic reason like the IAM/compute split above.
resource "aws_iam_policy" "launch_example_products_extra" {
  count = var.attach_example_products_policy ? 1 : 0

  name        = "${var.launch_role_name}-example-products-extra"
  description = "Scoped permissions for the bundled Service Catalog example products (database/CDN/integration/certificates/config/containers)"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "StandardRdsInstanceProduct"
        Effect = "Allow"
        Action = [
          "rds:CreateDBInstance",
          "rds:DeleteDBInstance",
          "rds:DescribeDBInstances",
          "rds:AddTagsToResource",
          "rds:CreateDBSubnetGroup",
          "rds:DeleteDBSubnetGroup",
          "rds:DescribeDBSubnetGroups",
        ]
        Resource = "*"
      },
      {
        # standard-rds-instance.yaml creates its own dedicated security group
        # rather than reusing an existing one, so these EC2 SG actions have
        # no ARN to scope to before the group exists - same "*" pattern used
        # for VPC/KMS creation above.
        Sid    = "StandardRdsInstanceProductSecurityGroup"
        Effect = "Allow"
        Action = [
          "ec2:CreateSecurityGroup",
          "ec2:DeleteSecurityGroup",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:DescribeSecurityGroups",
        ]
        Resource = "*"
      },
      {
        Sid    = "StandardCloudfrontDistributionProduct"
        Effect = "Allow"
        Action = [
          "cloudfront:CreateDistribution",
          "cloudfront:DeleteDistribution",
          "cloudfront:GetDistribution",
          "cloudfront:UpdateDistribution",
          "cloudfront:TagResource",
          "cloudfront:CreateOriginAccessControl",
          "cloudfront:DeleteOriginAccessControl",
          "cloudfront:GetOriginAccessControl",
        ]
        # CloudFront distributions/OACs have no ARN to scope to before they
        # exist, and CreateDistribution in particular only supports "*".
        Resource = "*"
      },
      {
        Sid    = "StandardEventbridgeScheduleProduct"
        Effect = "Allow"
        Action = [
          "events:PutRule",
          "events:DeleteRule",
          "events:PutTargets",
          "events:RemoveTargets",
          "events:DescribeRule",
          "events:TagResource",
        ]
        Resource = "arn:aws:events:*:*:rule/*"
      },
      {
        # Reuses the exact same hosted-zone allowlist as
        # StandardRoute53RecordProduct above - ACM's DNS auto-validation
        # calls route53:ChangeResourceRecordSets on that already-granted zone,
        # no additional Route53 grant needed here.
        Sid    = "StandardAcmCertificateProduct"
        Effect = "Allow"
        Action = [
          "acm:RequestCertificate",
          "acm:DeleteCertificate",
          "acm:DescribeCertificate",
          "acm:AddTagsToCertificate",
        ]
        Resource = "arn:aws:acm:*:*:certificate/*"
      },
      {
        Sid    = "StandardSsmParameterProduct"
        Effect = "Allow"
        Action = [
          "ssm:PutParameter",
          "ssm:DeleteParameter",
          "ssm:AddTagsToResource",
          "ssm:GetParameters",
        ]
        Resource = "arn:aws:ssm:*:*:parameter/*"
      },
      {
        Sid    = "StandardEcsClusterProduct"
        Effect = "Allow"
        Action = [
          "ecs:CreateCluster",
          "ecs:DeleteCluster",
          "ecs:DescribeClusters",
          "ecs:TagResource",
          "ecs:PutClusterCapacityProviders",
        ]
        Resource = "arn:aws:ecs:*:*:cluster/*"
      },
      {
        Sid    = "StandardCloudwatchDashboardProduct"
        Effect = "Allow"
        Action = [
          "cloudwatch:PutDashboard",
          "cloudwatch:DeleteDashboards",
          "cloudwatch:GetDashboard",
        ]
        # CloudWatch dashboard ARNs omit the region segment.
        Resource = "arn:aws:cloudwatch::*:dashboard/*"
      },
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "launch_example_products_extra" {
  count = var.attach_example_products_policy ? 1 : 0

  role       = aws_iam_role.launch.name
  policy_arn = aws_iam_policy.launch_example_products_extra[0].arn
}

resource "aws_servicecatalog_constraint" "launch" {
  for_each = {
    for p in var.products : p.name => p
    if p.constraint_type == "LAUNCH"
  }

  description  = "Launch role for ${each.key}"
  portfolio_id = aws_servicecatalog_portfolio.this.id
  product_id   = aws_servicecatalog_product.this[each.key].id
  type         = "LAUNCH"

  parameters = jsonencode({
    RoleArn = aws_iam_role.launch.arn
  })

  # Wait for the product-portfolio association to be fully propagated on the
  # AWS side before creating the constraint. Without this, CreateConstraint
  # races the association and returns ResourceNotFoundException when Terraform
  # creates products and constraints in parallel.
  depends_on = [aws_servicecatalog_product_portfolio_association.this]
}
