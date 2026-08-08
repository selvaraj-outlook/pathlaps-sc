################################################################################
# Service Catalog Module - Bundled Product Templates
#
# Hosts CloudFormation templates from cloudformation/products/*.yaml for any
# product that sets template_file (as opposed to an externally-hosted
# template_url). Only created if at least one product actually uses
# template_file - a var.products = [] scaffold never creates this bucket.
################################################################################

data "aws_caller_identity" "current" {}

locals {
  bundled_products = { for p in var.products : p.name => p if p.template_file != null }
  templates_bucket_name = coalesce(
    var.templates_bucket_name,
    "path-labs-service-catalog-templates-${data.aws_caller_identity.current.account_id}"
  )
}

resource "aws_s3_bucket" "templates" {
  count = length(local.bundled_products) > 0 ? 1 : 0

  bucket = local.templates_bucket_name

  tags = var.tags
}

resource "aws_s3_bucket_versioning" "templates" {
  count = length(local.bundled_products) > 0 ? 1 : 0

  bucket = aws_s3_bucket.templates[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "templates" {
  count = length(local.bundled_products) > 0 ? 1 : 0

  bucket = aws_s3_bucket.templates[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "templates" {
  count = length(local.bundled_products) > 0 ? 1 : 0

  bucket = aws_s3_bucket.templates[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "product_template" {
  for_each = local.bundled_products

  bucket = aws_s3_bucket.templates[0].id
  key    = "products/${each.value.template_file}"
  source = "${path.module}/cloudformation/products/${each.value.template_file}"
  etag   = filemd5("${path.module}/cloudformation/products/${each.value.template_file}")

  tags = var.tags
}
