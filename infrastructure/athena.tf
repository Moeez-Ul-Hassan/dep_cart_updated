# 1. S3 Bucket for Athena Query Results
resource "aws_s3_bucket" "athena_results" {
  bucket        = "enterprise-cart-athena-results-${random_id.bucket_suffix.hex}"
  force_destroy = true
}

# 2. Athena Workgroup
resource "aws_athena_workgroup" "analytics_workgroup" {
  name = "enterprise-analytics"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.bucket}/output/"
    }
  }
}

# 3. Create the Database Logically (Bypasses Glue Crawler)
resource "aws_athena_database" "cart_analytics" {
  name   = "enterprise_cart_db"
  bucket = aws_s3_bucket.athena_results.id
}