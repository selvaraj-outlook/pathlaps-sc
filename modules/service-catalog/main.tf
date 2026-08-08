################################################################################
# Service Catalog Module - Portfolio, Products, Principal Access
#
# Scaffold: the portfolio is always created, but grants no launch access and
# lists no products until var.principal_arns / var.products are populated by
# the caller - see terraform/service-catalog.tf.
################################################################################

resource "aws_servicecatalog_portfolio" "this" {
  name          = var.name
  description   = var.description
  provider_name = var.provider_name

  tags = var.tags
}

resource "aws_servicecatalog_principal_portfolio_association" "this" {
  for_each = toset(var.principal_arns)

  portfolio_id  = aws_servicecatalog_portfolio.this.id
  principal_arn = each.value
}

resource "aws_servicecatalog_product" "this" {
  for_each = { for p in var.products : p.name => p }

  name        = each.value.name
  owner       = each.value.owner
  description = each.value.description
  type        = "CLOUD_FORMATION_TEMPLATE"

  provisioning_artifact_parameters {
    name = "v1"
    type = "CLOUD_FORMATION_TEMPLATE"
    # try() guards the bundled-template branch: when no product uses
    # template_file, aws_s3_bucket.templates has count = 0, and indexing
    # [0] would error even for products that never select this branch -
    # Terraform's ?: does not short-circuit evaluation errors.
    template_url = each.value.template_file != null ? try(
      "https://${aws_s3_bucket.templates[0].bucket_regional_domain_name}/${aws_s3_object.product_template[each.key].key}",
      null
    ) : each.value.template_url
  }

  tags = var.tags
}

resource "aws_servicecatalog_product_portfolio_association" "this" {
  for_each = aws_servicecatalog_product.this

  portfolio_id = aws_servicecatalog_portfolio.this.id
  product_id   = each.value.id
}
