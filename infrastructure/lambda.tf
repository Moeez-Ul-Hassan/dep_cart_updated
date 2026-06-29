data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "../lambda_etl"
  output_path = "lambda_etl.zip"
}

resource "aws_iam_role" "lambda_role" {
  name = "enterprise_lambda_etl_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "lambda_s3_write" {
  name = "lambda_s3_write_policy"
  role = aws_iam_role.lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:GetObject"
        ]
        Effect   = "Allow"
        Resource = "${aws_s3_bucket.bronze_data_lake.arn}/*"
      },
      {
        Action   = "s3:ListBucket"
        Effect   = "Allow"
        Resource = aws_s3_bucket.bronze_data_lake.arn
      }
    ]
  })
}

resource "aws_vpc_endpoint" "s3_endpoint" {
  vpc_id       = aws_vpc.enterprise_vpc.id
  service_name = "com.amazonaws.us-east-1.s3"
}

resource "aws_vpc_endpoint_route_table_association" "s3_endpoint_route" {
  route_table_id  = aws_vpc.enterprise_vpc.main_route_table_id
  vpc_endpoint_id = aws_vpc_endpoint.s3_endpoint.id
}

resource "aws_lambda_function" "rds_etl" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "rds-to-bronze-etl"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  timeout          = 900  # 15 minutes max
  memory_size      = 1024 # 1 GB RAM for heavy batching
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      DB_HOST   = aws_db_instance.enterprise_db.address
      DB_USER   = "admin"
      DB_PASS   = var.db_password
      DB_NAME   = "cart_db"
      S3_BUCKET = aws_s3_bucket.bronze_data_lake.bucket
    }
  }

  vpc_config {
    subnet_ids         = [aws_subnet.private_subnet_1.id, aws_subnet.private_subnet_2.id]
    security_group_ids = [aws_security_group.app_sg.id]
  }
}

# --- EVENTBRIDGE SCHEDULER (CRON) ---
resource "aws_cloudwatch_event_rule" "daily_etl_trigger" {
  name                = "trigger-rds-to-bronze-daily"
  description         = "Triggers the RDS to S3 ETL Lambda function every midnight UTC"
  schedule_expression = "cron(0 0 * * ? *)" 
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.daily_etl_trigger.name
  target_id = "TriggerLambda"
  arn       = aws_lambda_function.rds_etl.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.rds_etl.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily_etl_trigger.arn
}