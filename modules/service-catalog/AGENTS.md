# AGENTS.md - modules/service-catalog

> Technical context for AI agents working on this module.

---

## What this module is

An AWS Service Catalog portfolio for the SharedServices Account
(`743165042770`), built as a **safe-by-default scaffold**: every
cross-account, sharing, or StackSet capability is gated behind a boolean
variable that defaults to `false`/empty, so applying this module with no
overrides touches nothing else in this repo's single Terraform state (shared
VPC, EKS, RDS, arena-nuke, litellm, custodian — none of them reference
`module.service_catalog`, so a `plan` here never diffs them).

The portfolio itself is **not** fully inert by default, though: it ships
with 21 bundled example products spanning most major AWS service categories
(see `templates-bucket.tf` + `cloudformation/products/`, and the table in
`README.md`) so the module is immediately demonstrable. The safety backstop
is `principal_arns` (`service_catalog_principal_arns` at root), which still
defaults to `[]` — the products exist and their launch role has scoped
permissions, but no principal can actually invoke `ProvisionProduct` until
that's populated.

Root wiring: [`terraform/service-catalog.tf`](../../service-catalog.tf)
(`module "service_catalog"` + `service_catalog_*` passthrough
variables/outputs, following the same co-located
module-call+variables+outputs pattern as `arena-nuke.tf`/`litellm.tf`).

---

## Architecture

```
┌────────────────────────────────────────────────────────────────────────┐
│  SHARED SERVICES ACCOUNT (743165042770) - hub, managed by THIS module   │
│    - aws_servicecatalog_portfolio                                       │
│    - aws_servicecatalog_product (+ aws_servicecatalog_product_portfolio_association)       │
│    - launch role (LAUNCH constraint)      - admin role                  │
│    - stackset_admin role (STACKSET constraint)                          │
│    - aws_servicecatalog_organizations_access + portfolio_share          │
└────────────────────────────────────────────────────────────────────────┘
        │ LAUNCH: assumes launch role,        │ STACKSET: stackset_admin
        │ creates resources in THIS account   │ assumes execution role in
        │                                     ▼ each target account
        │                    ┌──────────────────────────────────────────┐
        │                    │  STACKSET TARGET ACCOUNTS                 │
        │                    │    - stackset-execution-role.yaml (CFN,   │
        │                    │      deployed out-of-band, NOT by this    │
        │                    │      module - trusts stackset_admin)      │
        │                    └──────────────────────────────────────────┘
        ▼
┌────────────────────────────────────────────────────────────────────────┐
│  EVERY ORG MEMBER ACCOUNT (if enable_organizations_access = true)       │
│    - member-account-role.yaml (CFN, AWSServiceCatalogEndUserFullAccess) │
│    - deployed either out-of-band or via member-accounts.tf's            │
│      SERVICE_MANAGED StackSet (enable_member_role_stackset)             │
│    - end users here assume it to browse/launch products shared          │
│      from the hub                                                       │
└────────────────────────────────────────────────────────────────────────┘
```

---

## IMPORTANT - conflicts with this repo's stated conventions

The root [`AGENTS.md`](../../../AGENTS.md) ("What This Repo Does NOT
Manage" in `README.md`) states:

> SCPs, tag policies, budgets, permission sets, **StackSets** →
> `path-labs-infrastructure`

`stackset.tf` and `member-accounts.tf` in this module create
`aws_cloudformation_stack_set*` resources **in this repo**, which conflicts
with that convention. This was done deliberately, on explicit request, to
keep the whole Service Catalog surface in one module. **Do not silently
extend the StackSet pieces further** (more StackSets, more org-wide
resources) without first confirming with whoever owns this repo whether
they should actually live in `path-labs-infrastructure` instead — that repo
already owns the org-level StackSet that deploys `path-labs-custodian-role`
(see root `AGENTS.md`'s Cloud Custodian architecture diagram) and may be the
more consistent home for these too.

---

## File responsibilities

| File | Purpose |
|------|---------|
| `main.tf` | Portfolio, principal association, products, `aws_servicecatalog_product_portfolio_association` (note: resource type is `product_portfolio`, not `portfolio_product`). Always created; grants nothing until `principal_arns`/`products` are populated. |
| `constraints.tf` | Launch role (assumed by `servicecatalog.amazonaws.com`) + `LAUNCH` constraint, one per product with `constraint_type = "LAUNCH"` |
| `stackset.tf` | StackSet admin role (assumed by `cloudformation.amazonaws.com`, may assume the execution role in target accounts) + `STACKSET` constraint, one per product with `constraint_type = "STACKSET"`. Gated by `enable_stackset_products`. |
| `sharing.tf` | `aws_servicecatalog_organizations_access` (account-level toggle, argument is `enabled = true` — **not** `enable`) + `aws_servicecatalog_portfolio_share` (`type = "ORGANIZATION"`, shares to the whole org in one resource) + hub-account admin role. Gated by `enable_organizations_access` / `create_admin_role`. |
| `member-accounts.tf` | `SERVICE_MANAGED` CloudFormation StackSet that auto-deploys `cloudformation/member-account-role.yaml` org-wide. Gated by `enable_member_role_stackset`. |
| `cloudformation/member-account-role.yaml` | IAM role for spoke-account end users (`AWSServiceCatalogEndUserFullAccess`). Never created by Terraform directly — this repo only manages the hub account. |
| `cloudformation/stackset-execution-role.yaml` | IAM role for `STACKSET`-product target accounts, trusted by `stackset.tf`'s admin role. Same out-of-band deployment story as the member role. |
| `templates-bucket.tf` | S3 bucket (`local.templates_bucket_name`, default `path-labs-service-catalog-templates-<account-id>`) + `aws_s3_object` uploads for products using `template_file`. `count`/`for_each` gated on `local.bundled_products` being non-empty — a products list with only `template_url` entries never creates this bucket. |
| `cloudformation/products/*.yaml` | 21 bundled example templates, referenced by filename via a product's `template_file` — full list + IAM Sid cross-reference in `README.md` |
| `cross-account-dns.tf` | Option B for cross-account Route53 (see README.md's "Cross-account Route 53" section): Lambda + execution role + per-invoker `aws_lambda_permission`, gated by `enable_cross_account_route53_handler`. Wired into root `terraform/service-catalog.tf` via `service_catalog_enable_cross_account_route53_handler`, `service_catalog_cross_account_route53_handler_function_name`, and `service_catalog_cross_account_route53_invoker_principal_arns` (all default to off/empty). |
| `lambda/route53_cross_account_handler/index.py` | The actual cross-account Route53 handler code — CFN custom-resource protocol (stdlib `urllib` for the response callback, `boto3` for Route53), hardcodes its own zone allowlist independently of `constraints.tf` (see that file's docstring for why). |

**IAM policy layout for the bundled products** (all in `constraints.tf`,
all attached to the single `aws_iam_role.launch`, all gated by
`var.attach_example_products_policy`):
- `aws_iam_policy.launch_example_products` — storage/data/messaging/observability/DNS (S3, SNS, SQS, DynamoDB, KMS, Logs, Secrets Manager, ECR, CloudWatch Alarms, Route53 — the two Route53 statements, `StandardRoute53RecordProduct` + `...ChangeStatus`, are the ones with a hardcoded single-zone `Resource`).
- `aws_iam_policy.launch_example_products_iam_compute` — IAM-role-creating products (`standard-iam-readonly-role`, `standard-lambda-function`, `standard-sfn-state-machine`) plus `standard-vpc`. Read this one first when auditing what the launch role can do to IAM itself. Contains the `iam:AttachRolePolicy` grant restricted via `iam:PolicyARN` condition to `local.allowed_managed_policy_arns`.
- `aws_iam_policy.launch_example_products_extra` — RDS, CloudFront, EventBridge, ACM, SSM, ECS, CloudWatch Dashboard. Added as a third policy purely to stay under the 6,144-char single-policy size limit; the split point is about policy-body size, not a thematic boundary.

**When adding a new bundled product that needs IAM permissions**: prefer
extending whichever of the three policies has headroom (rough budget: stay
under ~5,500 chars of policy JSON per resource to leave margin) over adding
a fourth policy — `aws_iam_role.launch` is also capped at **10 total
attached managed policies** (the three `launch_example_products*` policies
plus whatever the caller passes via `launch_role_policy_arns` all share that
budget; root `AGENTS.md` documents hitting this exact ceiling before on
`GitLabRunnerRole`). If you do need a fourth policy, that's the moment to
budget remaining headroom explicitly rather than adding a fifth/sixth later
without checking.

**Gotcha**: `main.tf`'s `provisioning_artifact_parameters.template_url`
picks between the bundled-S3 URL and an external `template_url` with a
ternary keyed on `each.value.template_file != null` — a **per-product**
condition, not the same condition that gates the bucket's `count`
(`length(local.bundled_products) > 0`, a **global** condition). If a caller
someday ships a `products` list where every entry uses `template_url` (no
`template_file` at all), the bucket's `count` becomes 0, and indexing
`aws_s3_bucket.templates[0]` for those `template_url` iterations would
error even though that branch is never actually selected — Terraform's `?:`
does not short-circuit evaluation errors in the unchosen branch. This is
why that expression is wrapped in `try(..., null)`. **Keep that `try()`
if you touch this expression again.**

**IMPORTANT gotcha if you enable `enable_cross_account_route53_handler`**:
`.gitlab-ci.yml` (root of this repo, deliberately NOT touched by this
change) only carries `modules/arena-nuke/lambda/.build/` forward from the
`plan` job to the `apply` job as a pipeline artifact — see the comment
block above that line in `.gitlab-ci.yml`. `cross-account-dns.tf`'s
`archive_file` writes its zip to
`modules/service-catalog/lambda/.build/route53_cross_account_handler.zip`,
which is a **different path**, not covered by that artifact list. Applying
this through the existing CI pipeline as-is will fail in the `apply` job
with the exact same "no such file or directory" failure mode arena-nuke's
comment already documents (the `plan` job builds the zip in its own
ephemeral container; `apply` runs in a fresh one and never rebuilds it).
Someone will need to add that second path to `.gitlab-ci.yml`'s `plan` job
artifacts list before `enable_cross_account_route53_handler = true` can
ever actually apply through CI — that edit was intentionally left out of
this change per an explicit "don't touch other files" instruction, not
because it's optional.

---

## Known gaps / things not yet built

- **TagOptions** (`aws_servicecatalog_tag_option` /
  `_tag_option_resource_association`) — not implemented. Add if products
  need enforced tagging.
- **Service actions** (`aws_servicecatalog_service_action`) — not
  implemented (e.g. self-service stop/start/restart on provisioned
  products).
- **Provisioning artifact versioning** — `main.tf` only ever creates a
  single artifact named `"v1"` per product. Adding a second template
  version to an existing product needs a separate
  `aws_servicecatalog_provisioning_artifact` resource; this module doesn't
  have one yet.
- **Budget association** (`aws_servicecatalog_budget_resource_association`)
  — not implemented.

## Verification status

`terraform fmt`, `terraform validate`, and `terraform plan` have all been
run successfully against this module with AWS provider `6.58.0`. The plan
produces **96 resources to add, 0 to change, 0 to destroy**.

**Provider-level bugs found and fixed during this session:**

| Bug | File | Fix |
|-----|------|-----|
| Wrong resource type `aws_servicecatalog_portfolio_product_association` (does not exist) | `main.tf` | Renamed to `aws_servicecatalog_product_portfolio_association` |
| Wrong argument `enable = true` on `aws_servicecatalog_organizations_access` | `sharing.tf` | Changed to `enabled = true` |

**Providers declared** (`versions.tf` at root and in this module):
- `hashicorp/aws >= 5.0.0` (locked at `6.58.0`)
- `hashicorp/archive >= 2.0.0` (locked at `2.8.0`, required by `cross-account-dns.tf`)

**Still unverified at the CloudFormation level** — none of the bundled
product templates were run through `aws cloudformation validate-template`
or `cfn-lint`. Worth double-checking before relying on them in production:
- `standard-rds-instance.yaml` — `ManageMasterUserPassword: true` +
  `MasterUsername` together, and the `DBInstance.MasterUserSecret.SecretArn`
  `Fn::GetAtt` path.
- `standard-ssm-parameter.yaml` — native `SecureString` support on
  `AWS::SSM::Parameter` (was a known CloudFormation gap for a long time;
  confirm current support).
- `standard-acm-certificate.yaml` — DNS auto-validation via
  `DomainValidationOptions[].HostedZoneId` blocks until DNS validation
  propagates (can take several minutes).
- `standard-cloudfront-distribution.yaml` — `CachePolicyId:
  658327ea-f89d-4fab-a63d-7e88639e58f6` is AWS's Managed-CachingOptimized
  policy ID — verify it's still current if CloudFront launches fail.
- `cross-account-dns.tf` / `lambda/route53_cross_account_handler/index.py` /
  `standard-route53-record-cross-account.yaml` — the CFN custom-resource
  protocol implementation has **never actually been invoked**. Test
  Create/Update/Delete before relying on it in production.
