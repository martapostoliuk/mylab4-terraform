import json
import boto3
import os
import uuid
from datetime import datetime, timezone
from botocore.exceptions import ClientError

TABLE_NAME = os.environ.get("TABLE_NAME")
QUEUE_URL  = os.environ.get("QUEUE_URL")

dynamodb = boto3.resource("dynamodb")
sqs      = boto3.client("sqs")
table    = dynamodb.Table(TABLE_NAME)


def respond(status_code: int, body: dict) -> dict:
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body, ensure_ascii=False),
    }


def handler(event, context):
    try:
        http_method = event.get("requestContext", {}).get("httpMethod") or \
                      event.get("httpMethod", "")

        # ── GET /events  →  list all stored events ───────────────────────────
        if http_method == "GET":
            result = table.scan()
            return respond(200, {"events": result.get("Items", [])})

        # ── POST /events  →  deduplicate & enqueue ───────────────────────────
        if http_method == "POST":
            raw_body = event.get("body") or "{}"
            body = json.loads(raw_body)

            idempotency_key = body.get("idempotency_key")
            if not idempotency_key:
                return respond(400, {"error": "idempotency_key is required"})

            payload = body.get("payload", {})

            # ── Check DynamoDB for duplicate ──────────────────────────────────
            try:
                table.put_item(
                    Item={
                        "id": idempotency_key,
                        "payload":    json.dumps(payload),
                        "received_at": datetime.now(timezone.utc).isoformat(),
                        "status": "queued",
                    },
                    # Fail if the key already exists  → duplicate
                    ConditionExpression="attribute_not_exists(id)",
                )
            except ClientError as e:
                if e.response["Error"]["Code"] == "ConditionalCheckFailedException":
                    return respond(200, {
                        "status": "duplicate",
                        "idempotency_key": idempotency_key,
                        "message": "Event already processed. Skipped."
                    })
                raise  # re-raise unexpected errors

            # ── Place unique event into SQS ───────────────────────────────────
            sqs.send_message(
                QueueUrl=QUEUE_URL,
                MessageBody=json.dumps({
                    "idempotency_key": idempotency_key,
                    "payload": payload,
                }),
                MessageGroupId="events",          # required for FIFO queues
                MessageDeduplicationId=idempotency_key,
            )

            return respond(201, {
                "status": "queued",
                "idempotency_key": idempotency_key,
                "message": "Event accepted and placed in queue."
            })

        # ── Method not allowed ────────────────────────────────────────────────
        return respond(405, {"error": "Method Not Allowed"})

    except Exception as exc:
        print(f"Unhandled error: {exc}")
        return respond(500, {"error": "Internal Server Error"})
