# --- 1. THE NEW BRONZE DATA LAKE (S3) ---
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "bronze_data_lake" {
  bucket        = "enterprise-cart-bronze-${random_id.bucket_suffix.hex}"
  force_destroy = true # Allows Terraform to delete it easily later if needed
}

# --- 2. IAM PERMISSIONS FOR KINESIS ---
# Allows Kinesis to assume a role in your account
resource "aws_iam_role" "firehose_role" {
  name = "cart_api_firehose_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "firehose.amazonaws.com" }
    }]
  })
}

# Grants Kinesis permission to write files into your S3 Bucket
resource "aws_iam_role_policy" "firehose_s3_policy" {
  name = "firehose_s3_write_policy"
  role = aws_iam_role.firehose_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = [
        "s3:AbortMultipartUpload",
        "s3:GetBucketLocation",
        "s3:GetObject",
        "s3:ListBucket",
        "s3:ListBucketMultipartUploads",
        "s3:PutObject"
      ]
      Effect = "Allow"
      Resource = [
        aws_s3_bucket.bronze_data_lake.arn,
        "${aws_s3_bucket.bronze_data_lake.arn}/*"
      ]
    }]
  })
}

# --- 3. AMAZON KINESIS FIREHOSE ---
resource "aws_kinesis_firehose_delivery_stream" "event_stream" {
  name        = "cart-events-firehose"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn   = aws_iam_role.firehose_role.arn
    bucket_arn = aws_s3_bucket.bronze_data_lake.arn

    # Automatically organizes folders by Year/Month/Day/Hour!
    prefix              = "raw_events/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/"
    error_output_prefix = "errors/!{firehose:error-output-type}/"

    # Firehose will wait until it collects 5MB of data OR 60 seconds pass before uploading a file
    buffering_size     = 5
    buffering_interval = 60
  }
}

output "firehose_stream_name" {
  value = aws_kinesis_firehose_delivery_stream.event_stream.name
}
output "new_bronze_bucket" {
  value = aws_s3_bucket.bronze_data_lake.bucket
}

# --- EC2 VIP PASS FOR KINESIS (Formalized from Manual Console Creation) ---
resource "aws_iam_role" "ec2_kinesis_role" {
  name = "EC2-Cart-Firehose-Role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "kinesis_attach" {
  role       = aws_iam_role.ec2_kinesis_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonKinesisFirehoseFullAccess"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "EC2-Cart-Firehose-Profile"
  role = aws_iam_role.ec2_kinesis_role.name
}