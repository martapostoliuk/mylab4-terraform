# envs/dev/main.tf
provider "aws" {
  region = "eu-central-1"
}

locals {
  prefix = "postoliuk-marta-15"
}

# ── DynamoDB  (зберігає idempotency_key; запобігає дублям) ───────────────────
module "database" {
  source     = "../../modules/dynamodb"
  table_name = "${local.prefix}-events"
}

# ── SQS FIFO queue ────────────────────────────────────────────────────────────
module "queue" {
  source     = "../../modules/sqs"
  queue_name = "${local.prefix}-events"
}

# ── Lambda (бізнес-логіка: dedup + enqueue) ──────────────────────────────────
module "backend" {
  source              = "../../modules/lambda"
  function_name       = "${local.prefix}-api-handler"
  source_file         = "${path.root}/../../src/app.py"
  dynamodb_table_arn  = module.database.table_arn
  dynamodb_table_name = module.database.table_name
  sqs_queue_arn       = module.queue.queue_arn
  sqs_queue_url       = module.queue.queue_url
}

# ── API Gateway HTTP v2 ───────────────────────────────────────────────────────
module "api" {
  source               = "../../modules/api_gateway"
  api_name             = "${local.prefix}-http-api"
  lambda_invoke_arn    = module.backend.invoke_arn
  lambda_function_name = module.backend.function_name
}

# ── Outputs ───────────────────────────────────────────────────────────────────
output "api_url" {
  description = "Base URL of the deployed API"
  value       = module.api.api_endpoint
}

output "sqs_queue_url" {
  description = "URL of the SQS FIFO queue"
  value       = module.queue.queue_url
}

output "dynamodb_table_name" {
  description = "DynamoDB table storing idempotency keys"
  value       = module.database.table_name
}
