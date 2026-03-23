# modules/sqs/main.tf
variable "queue_name" {
  description = "Name of the FIFO SQS queue (must end with .fifo)"
  type        = string
}

# Dead-Letter Queue (FIFO)
resource "aws_sqs_queue" "dlq" {
  name                        = "${var.queue_name}-dlq.fifo"
  fifo_queue                  = true
  content_based_deduplication = true

  tags = {
    ManagedBy = "terraform"
  }
}

# Main FIFO queue – uses MessageDeduplicationId for server-side dedup
resource "aws_sqs_queue" "main" {
  name                        = "${var.queue_name}.fifo"
  fifo_queue                  = true
  content_based_deduplication = false   # we pass explicit MessageDeduplicationId

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })

  tags = {
    ManagedBy = "terraform"
  }
}

output "queue_url" {
  value = aws_sqs_queue.main.url
}

output "queue_arn" {
  value = aws_sqs_queue.main.arn
}
