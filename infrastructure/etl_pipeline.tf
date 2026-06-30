# 1. IAM Role for Step Functions to access Athena and S3
resource "aws_iam_role" "step_functions_role" {
  name = "sfn-athena-etl-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "states.amazonaws.com" }
    }]
  })
}

# Grant Step Functions permission to run Athena queries and write S3 logs
resource "aws_iam_role_policy" "step_functions_athena_policy" {
  name = "sfn-athena-etl-policy"
  role = aws_iam_role.step_functions_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "athena:StartQueryExecution",
          "athena:GetQueryExecution",
          "athena:GetQueryResults",
          "athena:StopQueryExecution"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:PutObject",
          "s3:GetBucketAcl"
        ]
        Resource = [
          "arn:aws:s3:::enterprise-cart-bronze-dc2db008",
          "arn:aws:s3:::enterprise-cart-bronze-dc2db008/*",
          "arn:aws:s3:::enterprise-cart-athena-results-dc2db008",
          "arn:aws:s3:::enterprise-cart-athena-results-dc2db008/*"
        ]
      }
    ]
  })
}

# 2. The Step Functions State Machine
resource "aws_sfn_state_machine" "etl_pipeline" {
  name     = "BronzeToSilverETL"
  role_arn = aws_iam_role.step_functions_role.arn
  # Reads the JSON file locally
  definition = file("${path.module}/data_pipeline_sql/etl_state_machine.asl.json")
}

# 3. IAM Role for EventBridge to trigger Step Functions
resource "aws_iam_role" "eventbridge_role" {
  name = "eventbridge-trigger-sfn-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "eventbridge_sfn_policy" {
  name = "eventbridge-trigger-sfn-policy"
  role = aws_iam_role.eventbridge_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "states:StartExecution"
      Resource = aws_sfn_state_machine.etl_pipeline.arn
    }]
  })
}

# 4. The EventBridge Cron Schedule (Runs daily at Midnight UTC)
resource "aws_cloudwatch_event_rule" "nightly_etl" {
  name                = "Nightly-Bronze-To-Silver-ETL"
  description         = "Triggers the Athena ETL pipeline every night at midnight"
  schedule_expression = "cron(0 0 * * ? *)"
}

resource "aws_cloudwatch_event_target" "trigger_sfn" {
  rule      = aws_cloudwatch_event_rule.nightly_etl.name
  target_id = "TriggerETLStateMachine"
  arn       = aws_sfn_state_machine.etl_pipeline.arn
  role_arn  = aws_iam_role.eventbridge_role.arn
}