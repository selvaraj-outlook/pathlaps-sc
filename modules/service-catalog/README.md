# modules/service-catalog

Reusable Terraform module for an AWS Service Catalog portfolio in the
SharedServices Account (`743165042770`), wired into the root config via
[`terraform/service-catalog.tf`](../../service-catalog.tf).

Every cross-account/sharing/StackSet feature is **off by default**. The
portfolio itself ships with a 12-product bundled example catalog spanning
storage, database, messaging, security, observability, compute, and
networking (see "Bundled example catalog" below), so it's usable out of the
box, but `principal_arns` (who may launch products) still defaults to `[]`,
so applying this module as-is creates the portfolio and products with **no
one able to launch anything** until you populate
`service_catalog_principal_arns`. Nothing here affects the rest of this
repo's state (shared VPC, EKS, RDS, arena-nuke, litellm, custodian) since
none of those resources reference `module.service_catalog`.

> **Before enabling the StackSet or org-sharing pieces below**, note that this
> repo's own [`AGENTS.md`](../../../AGENTS.md) states StackSets and
> org-level/cross-account resources belong in `path-labs-infrastructure`, not
> here. This module was built to keep the whole portfolio in one place per
> explicit request — decide deliberately whether to keep StackSet-touching
> resources (`stackset.tf`, `member-accounts.tf`) here or move them to
> `path-labs-infrastructure` before you turn them on in `main`.

## Files

| File | Purpose |
|------|---------|
| `main.tf` | Portfolio, principal association (`principal_arns`), products, `aws_servicecatalog_product_portfolio_association` |
| `constraints.tf` | LAUNCH-role + `LAUNCH` constraint for single-account products (`constraint_type = "LAUNCH"`, the default) |
| `stackset.tf` | StackSet administration role (this account) + `STACKSET` constraint for products with `constraint_type = "STACKSET"` — deploys a product's CFN template across `stackset_target_accounts`/`stackset_target_regions` |
| `sharing.tf` | `aws_servicecatalog_organizations_access` + org-wide `aws_servicecatalog_portfolio_share`, plus the hub-account **admin role** (`AWSServiceCatalogAdminFullAccess`) |
| `member-accounts.tf` | Optional `SERVICE_MANAGED` CloudFormation StackSet that auto-deploys the **member role** to every spoke account |
| `cloudformation/member-account-role.yaml` | End-user IAM role (`AWSServiceCatalogEndUserFullAccess`) deployed into every spoke account so people there can browse/launch shared products |
| `cloudformation/stackset-execution-role.yaml` | Execution role deployed into each `STACKSET` target account, trusted by the `stackset.tf` admin role |
| `templates-bucket.tf` | S3 bucket + uploads for any product using `template_file` (bundled templates under `cloudformation/products/`) instead of an external `template_url` |
| `cloudformation/products/*.yaml` | The 12 bundled example product templates — see table below |
| `variables.tf` / `outputs.tf` | Inputs and outputs for all of the above |

## Bundled example catalog

All 21 default to `constraint_type = "LAUNCH"` (provisioned in this hub
account). Registered by default in `service_catalog_products` in
[`terraform/service-catalog.tf`](../../service-catalog.tf); set that
variable to `[]` (or drop individual entries) to trim it down.

| Category | Product | Template | Creates |
|----------|---------|----------|---------|
| Storage | `standard-s3-bucket` | `standard-s3-bucket.yaml` | Encrypted, versioned, public-access-blocked S3 bucket |
| Database | `standard-dynamodb-table` | `standard-dynamodb-table.yaml` | On-demand DynamoDB table, SSE + point-in-time recovery |
| Database | `standard-rds-instance` | `standard-rds-instance.yaml` | Single-AZ RDS instance (Postgres/MySQL), encrypted, AWS-managed master password, existing VPC/subnets picked via native CFN dropdowns |
| Messaging | `standard-sns-topic` | `standard-sns-topic.yaml` | KMS-encrypted SNS topic |
| Messaging | `standard-sqs-queue` | `standard-sqs-queue.yaml` | SSE SQS queue + dead-letter queue |
| Security | `standard-kms-key` | `standard-kms-key.yaml` | Customer-managed KMS key, rotation enabled |
| Security | `standard-secrets-manager-secret` | `standard-secrets-manager-secret.yaml` | Secrets Manager secret, AWS-generated value (no plaintext input) |
| Security | `standard-iam-readonly-role` | `standard-iam-readonly-role.yaml` | IAM role restricted to a curated read-only managed-policy allowlist |
| Security | `standard-acm-certificate` | `standard-acm-certificate.yaml` | DNS-validated ACM cert, auto-validates via the same curated hosted-zone allowlist as `standard-route53-record` |
| Observability | `standard-log-group` | `standard-log-group.yaml` | CloudWatch Logs log group, bounded retention |
| Observability | `standard-cloudwatch-alarm` | `standard-cloudwatch-alarm.yaml` | CloudWatch metric alarm → existing SNS topic |
| Observability | `standard-cloudwatch-dashboard` | `standard-cloudwatch-dashboard.yaml` | CloudWatch dashboard from user-supplied widget JSON (no permissions on any other resource) |
| Integration | `standard-sfn-state-machine` | `standard-sfn-state-machine.yaml` | Step Functions skeleton (single Pass state) + dedicated logs-only execution role |
| Integration | `standard-eventbridge-schedule` | `standard-eventbridge-schedule.yaml` | Scheduled EventBridge rule → existing SNS topic |
| Compute | `standard-lambda-function` | `standard-lambda-function.yaml` | Lambda function + dedicated logs-only execution role |
| Compute | `standard-ecr-repository` | `standard-ecr-repository.yaml` | ECR repo, scan-on-push, immutable tags |
| Compute | `standard-ecs-cluster` | `standard-ecs-cluster.yaml` | Fargate-only ECS cluster, Container Insights enabled |
| Networking | `standard-vpc` | `standard-vpc.yaml` | Minimal single-AZ VPC, 1 public + 1 private subnet, no NAT by default |
| Networking | `standard-cloudfront-distribution` | `standard-cloudfront-distribution.yaml` | CloudFront distribution fronting an existing S3 bucket via Origin Access Control |
| Networking/DNS | `standard-route53-record` | `standard-route53-record.yaml` | DNS record under a **curated dropdown of domains this account actually owns** (`DomainName` `AllowedValues`, currently just `path.app.presidio.com`) — never a free-text hosted zone ID |
| Management | `standard-ssm-parameter` | `standard-ssm-parameter.yaml` | SSM Parameter Store parameter (String/StringList/SecureString) |
| Networking/DNS (cross-account) | `standard-route53-record-cross-account` | `standard-route53-record-cross-account.yaml` | Same DNS record capability as `standard-route53-record`, but launchable from **another account** — see "Cross-account Route 53" below. **Not in the default `service_catalog_products` list** (deliberately not wired into root `terraform/service-catalog.tf`) — register it yourself when you're ready to use it. |

Three products output guidance instead of fully wiring cross-resource
permissions themselves, because the target resource may not be owned by
this stack: `standard-cloudfront-distribution` (add a bucket policy on the
origin bucket allowing the distribution's OAC) and
`standard-eventbridge-schedule` (add an SNS topic policy allowing
`events.amazonaws.com`) both say so in their template `Description`/comments
— read the `Outputs` before assuming the wiring is automatic.

## Cross-account Route 53 (Option B)

`standard-route53-record.yaml` only works when launched IN this hub account
— a native `AWS::Route53::RecordSet` can only touch a zone owned by the
account the CloudFormation stack runs in, and a shared Service Catalog
portfolio's `LAUNCH` constraint requires a `LocalRoleName` role that exists
*in the launching account*, not this one. If Account A needs to add DNS
records under this hub's zone without owning a delegated subdomain (the
`stackset.tf`/subdomain-delegation alternative), that's what
`cross-account-dns.tf` + `standard-route53-record-cross-account.yaml`
are for: a Lambda in this hub account does the actual Route 53 write, and
Account A's stack invokes it as a `Custom::Route53Record` resource instead
of touching Route53 directly.

**Everything here is off by default** — `enable_cross_account_route53_handler
= false` means no Lambda, no execution role, and no cross-account trust
exists at all until you opt in.

To actually use it:
1. Set `enable_cross_account_route53_handler = true` (creates the Lambda +
   its execution role, scoped to the same one curated hosted zone as
   `standard-route53-record`).
2. Add Account A's local launch/execution role ARN to
   `cross_account_route53_invoker_principal_arns` — nothing can invoke the
   Lambda until its ARN is explicitly listed here.
3. In Account A (outside this repo entirely — this module only manages the
   hub account): grant that same local role `lambda:InvokeFunction` on the
   hub Lambda's ARN (module output `cross_account_route53_handler_arn`),
   and register `standard-route53-record-cross-account.yaml` as a product
   there (either in Account A's own portfolio, or by registering it in
   THIS hub portfolio and relying on the org-wide sharing already built in
   `sharing.tf` — either works, since the Lambda ARN is hardcoded in the
   template rather than depending on which account launched it).

**Defense in depth**: three independent layers gate what this can touch —
(a) the resource-based Lambda permission controls *who* can invoke it at
all, (b) the Lambda's own IAM execution role is scoped to only the one
allowlisted zone ARN, and (c) the Lambda code itself
(`lambda/route53_cross_account_handler/index.py`) hardcodes the same zone
ID as a belt-and-suspenders application-level check. All three (plus
`StandardRoute53RecordProduct` in `constraints.tf`) must be updated
together when onboarding a new domain — see `AGENTS.md`.

**This was never invoked/tested in this session** (no `terraform apply`,
no live Lambda invocation) — see the Verification caveat in `AGENTS.md`
before relying on it.

**Adding a second domain to `standard-route53-record`**: that hosted zone
must already exist in this account. Then update, together, in the same
change: the template's `DomainName` `AllowedValues` + `DomainHostedZones`
mapping, AND the `StandardRoute53RecordProduct` statement's `Resource` list
in `constraints.tf` (add the new zone ARN — never widen it to
`arn:aws:route53:::hostedzone/*`). Skipping the IAM side means the product
launches but its CloudFormation stack fails with `AccessDenied`, which is
the intended fail-safe, not a bug.

**Security note on the IAM-role-creating products**
(`standard-iam-readonly-role`, `standard-lambda-function`,
`standard-sfn-state-machine`): the shared launch role's
`iam:AttachRolePolicy` permission is restricted via an `iam:PolicyARN`
condition (`local.allowed_managed_policy_arns` in `constraints.tf`) to the
exact managed policies those templates are allowed to attach — it cannot be
used to attach `AdministratorAccess` or any other policy outside that
allowlist. `standard-sfn-state-machine.yaml`'s execution role instead gets a
**fixed, template-authored inline policy** (`iam:PutRolePolicy`, not
`AttachRolePolicy`) — there's no IAM condition that can restrict *inline
policy content*, so that grant relies on the same trust boundary as the rest
of this module ("who can edit templates in this repo", not "who can launch
products"). If you add a product whose inline policy content comes from a
CFN Parameter instead of being hardcoded, do not reuse that Sid's resource
pattern — that would let a launching end user write an arbitrary inline
policy.

**Aggregate blast-radius note**: all `LAUNCH`-type products share ONE launch
role (`aws_iam_role.launch`), split across three customer-managed policies
(`launch_example_products`, `launch_example_products_iam_compute`,
`launch_example_products_extra` in `constraints.tf` — split mainly to stay
under the 6,144-char single-policy limit, not for a strict thematic
reason). Scoped per-service, but in aggregate that role can create
S3/DynamoDB/RDS/SNS/SQS/KMS/Logs/Secrets/ACM/ECR/ECS/IAM-roles/Lambda/Step
Functions/EventBridge/CloudFront/Route53(one zone)/VPC/SSM/CloudWatch
resources. If that aggregate is too broad for your risk tolerance, split
products across multiple portfolios/launch roles rather than registering
everything in one `module.service_catalog` call. Also note: **IAM roles cap
out at 10 attached managed policies** (root `AGENTS.md` documents hitting
this on `GitLabRunnerRole` before) — the three example-product policies plus
whatever you pass via `launch_role_policy_arns` share that same 10-policy
budget on `aws_iam_role.launch`.

## Provisioning models this module supports

| Model | Where resources are created | Constraint type | Requires |
|-------|------------------------------|------------------|----------|
| Single-account launch | This (hub) account, via `launch_role` | `LAUNCH` (default) | `launch_role_policy_arns` scoped to the product |
| Multi-account/region StackSet | Every account in `stackset_target_accounts` | `STACKSET` | `enable_stackset_products = true`, `cloudformation/stackset-execution-role.yaml` pre-deployed in each target account |

## Sharing the portfolio to other accounts

1. Set `enable_organizations_access = true` — requires this account to be
   the AWS Organizations **management account** or a registered
   **delegated administrator** for `servicecatalog.amazonaws.com`; otherwise
   the API call fails. This is an org-level setting this module cannot grant
   itself.
2. That also creates an org-wide `aws_servicecatalog_portfolio_share`
   (`type = "ORGANIZATION"`), so every account in the org can see the
   portfolio.
3. Each spoke account still needs an IAM principal permitted to actually
   launch products — deploy `cloudformation/member-account-role.yaml` there
   (manually, or automatically via `enable_member_role_stackset = true` if
   this account already has AWS Organizations trusted access enabled for
   CloudFormation StackSets).

## Admin vs. member role

- **Admin role** (`create_admin_role`, `sharing.tf`) — lives in **this** hub
  account. Platform-team members assume it to manage the portfolio/products
  (`AWSServiceCatalogAdminFullAccess`). Requires `admin_principal_arns`.
- **Member role** (`member-accounts.tf` / `cloudformation/member-account-role.yaml`)
  — lives in **every spoke account** the portfolio is shared with. End users
  there assume it to browse/launch shared products
  (`AWSServiceCatalogEndUserFullAccess`). Requires
  `member_role_trusted_principal_arns`.

## Variable names at root

All module variables are passed through `service-catalog.tf` using the
`service_catalog_*` prefix. The three cross-account Route 53 variables
(`service_catalog_enable_cross_account_route53_handler`,
`service_catalog_cross_account_route53_handler_function_name`,
`service_catalog_cross_account_route53_invoker_principal_arns`) are
declared in `service-catalog.tf` and wired to the module but default to
off/empty — safe to ignore unless you're enabling Option B DNS.

## Where to add products

Edit the `service_catalog_products` variable's `default` in
[`terraform/service-catalog.tf`](../../service-catalog.tf) — this repo has
no `*.tfvars` convention (see root `AGENTS.md`), every other feature
(`arena_nuke_*`, `litellm_*`, etc.) sets its real values directly as
variable defaults, so this module follows the same pattern.

Two ways to back a product:

**Bundled template** (recommended for anything owned by this repo) — drop a
`.yaml`/`.json` CloudFormation template in
`modules/service-catalog/cloudformation/products/` and reference it by
filename via `template_file`. The module uploads it to a module-owned S3
bucket automatically:

```hcl
service_catalog_products = [
  {
    name          = "standard-s3-bucket"
    owner         = "Path Labs Platform Team"
    description   = "Private, encrypted, versioned S3 bucket with public access fully blocked"
    template_file = "standard-s3-bucket.yaml"
  },
  {
    name          = "standard-sns-topic"
    owner         = "Path Labs Platform Team"
    description   = "KMS-encrypted SNS topic for application notifications/alerts"
    template_file = "standard-sns-topic.yaml"
  },
]
```

**Externally-hosted template** — if the template already lives somewhere
else (another S3 bucket, another repo's pipeline), reference it directly
with `template_url` instead of `template_file` (set exactly one of the two):

```hcl
{
  name         = "my-product"
  owner        = "Path Labs Platform Team"
  description  = "..."
  template_url = "https://my-bucket.s3.amazonaws.com/my-template.yaml"
}
```

Add `constraint_type = "STACKSET"` to either shape for a multi-account
product (see the table above).

`LAUNCH`-type products need IAM permissions on the shared launch role to
actually create their resources. The two bundled examples already have a
scoped policy for exactly what they create
(`aws_iam_policy.launch_example_products` in `constraints.tf`, toggled via
`attach_example_products_policy` / `service_catalog_attach_example_products_policy`,
default `true`). For your own bundled/external products, populate
`service_catalog_launch_role_policy_arns` with policies scoped to exactly
what that product's template creates — never attach `AdministratorAccess`
or another broad policy there.

**Reminder:** adding a product here doesn't let anyone launch it — that
still requires `service_catalog_principal_arns` (this account) and/or the
member-role rollout (spoke accounts) to be populated.

## Not yet covered

TagOptions, service actions, budget associations, and provisioning-artifact
versioning (adding a new template version to an existing product) aren't
implemented — add them the same way as the existing resources if needed
(`aws_servicecatalog_tag_option`, `aws_servicecatalog_service_action`,
`aws_servicecatalog_budget_resource_association`,
`aws_servicecatalog_provisioning_artifact`).
