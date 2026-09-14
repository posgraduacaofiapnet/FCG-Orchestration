#!/usr/bin/env bash
set -euo pipefail

QUEUE_NAME=fcg-notifications-queue
FUNCTION_NAME=fcg-notifications
TABLE_NAME=fcg-notification-idempotency
ARTIFACT=/opt/code/localstack/artifacts/fcg-notifications.zip

awslocal sqs create-queue --queue-name "$QUEUE_NAME" >/dev/null

if ! awslocal dynamodb describe-table --table-name "$TABLE_NAME" >/dev/null 2>&1; then
  awslocal dynamodb create-table \
    --table-name "$TABLE_NAME" \
    --attribute-definitions AttributeName=EventId,AttributeType=S \
    --key-schema AttributeName=EventId,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST >/dev/null
fi

if ! awslocal lambda get-function --function-name "$FUNCTION_NAME" >/dev/null 2>&1; then
  awslocal lambda create-function \
    --function-name "$FUNCTION_NAME" \
    --runtime dotnet8 \
    --handler 'FCG.Notifications.Function::FCG.Notifications.Function.Function::FunctionHandler' \
    --role arn:aws:iam::000000000000:role/fcg-local-lambda-role \
    --timeout 30 \
    --memory-size 256 \
    --zip-file "fileb://$ARTIFACT" \
    --environment "Variables={IDEMPOTENCY_TABLE_NAME=$TABLE_NAME,IDEMPOTENCY_RETENTION_DAYS=7,DYNAMODB_SERVICE_URL=http://localstack:4566}" >/dev/null
fi

awslocal lambda wait function-active-v2 --function-name "$FUNCTION_NAME"

QUEUE_ARN=$(awslocal sqs get-queue-attributes \
  --queue-url "http://localstack:4566/queue/us-east-1/000000000000/$QUEUE_NAME" \
  --attribute-names QueueArn \
  --query 'Attributes.QueueArn' \
  --output text)

if ! awslocal lambda list-event-source-mappings \
  --function-name "$FUNCTION_NAME" \
  --event-source-arn "$QUEUE_ARN" \
  --query 'EventSourceMappings[0].UUID' \
  --output text | grep -vq '^None$'; then
  awslocal lambda create-event-source-mapping \
    --function-name "$FUNCTION_NAME" \
    --event-source-arn "$QUEUE_ARN" \
    --batch-size 10 \
    --function-response-types ReportBatchItemFailures >/dev/null
fi

touch /tmp/phase3-ready
