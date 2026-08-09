# GitHub Actions OIDC Setup

One-time setup to connect this repo's GitHub Actions pipelines to AWS
account `743165042770` without storing long-lived credentials.

---

## Step 1 — Deploy the OIDC role into AWS

```bash
aws cloudformation deploy \
  --stack-name github-actions-oidc-role \
  --template-file .github/oidc-role.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
      GitHubOrg=selvaraj-outlook \
      GitHubRepo=pathlaps-sc \
      GitHubOwnerId=261786377 \
      GitHubRepoId=1328032007 \
  --profile coda-sharedservices \
  --region us-east-1
```

> GitHub's OIDC `sub` claim is prefixed with the numeric owner/repo IDs
> (`repo:OWNER@OWNERID/REPO@REPOID:...`), not just the names — the trust
> policy must match on the ID-suffixed form or every assume-role call is
> denied. Find the IDs with:
> `gh api repos/selvaraj-outlook/pathlaps-sc --jq '{owner_id: .owner.id, repo_id: .id}'`

Get the role ARN from the stack output:

```bash
aws cloudformation describe-stacks \
  --stack-name github-actions-oidc-role \
  --query "Stacks[0].Outputs[?OutputKey=='RoleArn'].OutputValue" \
  --output text \
  --profile coda-sharedservices \
  --region us-east-1
```

---

## Step 2 — Store the role ARN as a GitHub secret

```bash
gh secret set GH_ACTIONS_ROLE_ARN \
  --body "arn:aws:iam::743165042770:role/github-actions-pathlaps-sc" \
  --repo selvaraj-outlook/pathlaps-sc
```

Or via the GitHub UI:
`Settings → Secrets and variables → Actions → New repository secret`
- Name: `GH_ACTIONS_ROLE_ARN`
- Value: the ARN from Step 1

---

## Step 3 — Create the `production` environment with required reviewers

1. Go to `Settings → Environments → New environment`
2. Name it `production`
3. Under **Required reviewers** add yourself (or your team)
4. Save

This means the Apply workflow pauses at the `plan` job and waits for a
human to approve before `apply` runs.

---

## Step 4 — Update versions.tf to remove the local profile

Once OIDC is working, the `profile` line in `versions.tf` must be removed
(GitHub Actions runners don't have AWS CLI profiles configured):

```hcl
provider "aws" {
  region = "us-east-1"
  # profile = "coda-sharedservices"  ← remove this for CI
  # In CI, credentials come from the OIDC role via environment variables
}
```

Use a variable or conditional instead if you want both local and CI to work:

```hcl
variable "aws_profile" {
  type    = string
  default = ""   # empty = use environment credentials (CI)
}

provider "aws" {
  region  = "us-east-1"
  profile = var.aws_profile != "" ? var.aws_profile : null
}
```

Then locally: `terraform plan -var="aws_profile=coda-sharedservices"`

---

## How the pipeline works

```
PR opened / push to branch
        │
        ├── fmt-check      (no AWS creds)
        ├── validate        (no AWS creds)
        └── plan            (assumes OIDC role, posts plan as PR comment)

PR merged to main
        │
        └── (nothing automatic - apply is MANUAL only)

Manual trigger: Actions → Terraform Apply → Run workflow
        │
        ├── gate            (checks branch=main, input=APPLY)
        ├── plan            (fresh plan, waits for "production" env approval)
        └── apply           (applies the plan)
```
