# =============================================================================
# MAIN TERRAFORM CONFIGURATION — conectamos-platform
# Target: AWS S3 + CloudFront (Flutter Web static hosting)
# Account: conectamos-ai (AWS_AI_KEY) — TODO: migrar a cuenta prod/dev cuando
#   se bootstrappeen AWS_PROD_KEY / AWS_DEV_KEY. Ver reference-aws-accounts.
# =============================================================================

locals {
  is_production    = terraform.workspace == "platform-frontend"
  workspace_suffix = local.is_production ? "-prod" : "-dev"
  bucket_name      = "conectamos-platform${local.workspace_suffix}-ai"
  custom_domain    = local.is_production ? "platform.conectamos.ai" : "platform-dev.conectamos.ai"
}

# =============================================================================
# S3 — static assets bucket
# =============================================================================

resource "aws_s3_bucket" "app" {
  bucket = local.bucket_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "app" {
  bucket = aws_s3_bucket.app.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Versioning: keep the last 3 versions — helps with fast rollback
resource "aws_s3_bucket_versioning" "app" {
  bucket = aws_s3_bucket.app.id
  versioning_configuration {
    status = "Enabled"
  }
}

# =============================================================================
# CLOUDFRONT — CDN + HTTPS
# =============================================================================

resource "aws_cloudfront_origin_access_control" "app" {
  name                              = local.bucket_name
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ACM certificate — only when a custom domain is configured.
# CloudFront requires certs in us-east-1 regardless of distribution region.
resource "aws_acm_certificate" "app" {
  domain_name       = local.custom_domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# Blocks until the certificate reaches ISSUED state.
# First deploy: add the CNAME from acm_certificate_validation_records output to Cloudflare,
# then this resource will unblock and CloudFront creation will proceed.
resource "aws_acm_certificate_validation" "app" {
  certificate_arn = aws_acm_certificate.app.arn
}

resource "aws_cloudfront_distribution" "app" {
  enabled             = true
  default_root_object = "index.html"
  price_class         = "PriceClass_100" # US + Europe — cheapest tier, enough for MX
  aliases             = [local.custom_domain]

  origin {
    domain_name              = aws_s3_bucket.app.bucket_regional_domain_name
    origin_id                = "s3-${local.bucket_name}"
    origin_access_control_id = aws_cloudfront_origin_access_control.app.id
  }

  default_cache_behavior {
    target_origin_id       = "s3-${local.bucket_name}"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    # AWS Managed Policy: CachingOptimized (respects Cache-Control headers)
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  }

  # SPA routing: Flutter router handles all paths — serve index.html for S3 403/404
  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }
  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.app.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  depends_on = [aws_acm_certificate_validation.app]

  lifecycle {
    prevent_destroy = true
  }
}

# =============================================================================
# S3 BUCKET POLICY — allow CloudFront OAC to read objects
# =============================================================================

resource "aws_s3_bucket_policy" "app" {
  bucket = aws_s3_bucket.app.id
  policy = data.aws_iam_policy_document.s3_allow_cloudfront.json

  depends_on = [aws_s3_bucket_public_access_block.app]
}

data "aws_iam_policy_document" "s3_allow_cloudfront" {
  statement {
    sid     = "AllowCloudFrontServicePrincipal"
    effect  = "Allow"
    actions = ["s3:GetObject"]
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    resources = ["${aws_s3_bucket.app.arn}/*"]
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.app.arn]
    }
  }
}
