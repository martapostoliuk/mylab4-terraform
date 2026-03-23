# modules/lambda/main.tf

variable "function_name"       { type = string }
variable "source_file"         { type = string }
variable "dynamodb_table_arn"  { type = string }
variable "dynamodb_table_name" { type = string }
variable "sqs_queue_arn"       { type = string }
variable "sqs_queue_url"       { type = string }

# ── Package source code into a ZIP ───────────────────────────────────────────
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = var.source_file
  output_path = "${path.module}/app.zip"
}

# ── IAM Execution Role (unique per function — Least Privilege) ───────────────
resource "aws_iam_role" "lambda_exec" {
  name = "${var.function_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# Basic CloudWatch Logs
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Granular DynamoDB policy (ConditionalPutItem for deduplication)
resource "aws_iam_role_policy" "dynamodb_access" {
  name = "dynamodb-access"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:PutItem",
        "dynamodb:GetItem",
        "dynamodb:Scan",
        "dynamodb:Query",
      ]
      Resource = var.dynamodb_table_arn
    }]
  })
}

# SQS send-message policy
resource "aws_iam_role_policy" "sqs_access" {
  name = "sqs-send"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sqs:SendMessage"]
      Resource = var.sqs_queue_arn
    }]
  })
}

# ── Lambda function ───────────────────────────────────────────────────────────
resource "aws_lambda_function" "api_handler" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = var.function_name
  role             = aws_iam_role.lambda_exec.arn
  handler          = "app.handler"
  runtime          = "python3.12"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout          = 15

  environment {
    variables = {
      TABLE_NAME = var.dynamodb_table_name
      QUEUE_URL  = var.sqs_queue_url
    }
  }

  tags = {
    ManagedBy = "terraform"
  }
}

output "invoke_arn"     { value = aws_lambda_function.api_handler.invoke_arn }
output "function_name"  { value = aws_lambda_function.api_handler.function_name }
