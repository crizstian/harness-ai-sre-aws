data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

locals {
  function_name      = "${var.name_prefix}-demo"
  forwarder_name     = "${var.name_prefix}-forwarder"
  alarm_name         = "${var.name_prefix}-lambda-errors"
  log_group_name     = "/aws/lambda/${local.function_name}"
  forwarder_log_group = "/aws/lambda/${local.forwarder_name}"

  # Constructed independently to avoid a dependency cycle.
  alarm_arn = join("", [
    "arn:",
    data.aws_partition.current.partition,
    ":cloudwatch:",
    var.aws_region,
    ":",
    data.aws_caller_identity.current.account_id,
    ":alarm:",
    local.alarm_name
  ])
}

# =============================================================================
# Demo Lambda (success / deliberate failure)
# =============================================================================

resource "aws_cloudwatch_log_group" "lambda" {
  name              = local.log_group_name
  retention_in_days = 7
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect = "Allow"

    actions = [
      "sts:AssumeRole"
    ]

    principals {
      type = "Service"

      identifiers = [
        "lambda.amazonaws.com"
      ]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${var.name_prefix}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

data "aws_iam_policy_document" "lambda_logs" {
  statement {
    sid    = "WriteFunctionLogs"
    effect = "Allow"

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = [
      "${aws_cloudwatch_log_group.lambda.arn}:*"
    ]
  }
}

resource "aws_iam_role_policy" "lambda_logs" {
  name   = "${var.name_prefix}-write-logs"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_logs.json
}

data "archive_file" "lambda" {
  type        = "zip"
  output_path = "${path.module}/lambda-demo.zip"

  source {
    filename = "lambda_function.py"

    content = <<-PYTHON
      import json
      import logging

      logger = logging.getLogger()
      logger.setLevel(logging.INFO)


      def lambda_handler(event, context):
          if not isinstance(event, dict):
              raise ValueError("Expected a JSON object")

          logger.info(
              "Demo invocation: %s",
              json.dumps({
                  "request_id": context.aws_request_id,
                  "event": event
              })
          )

          if event.get("fail", False) is True:
              logger.error("Deliberate failure for Harness AI SRE lab")
              raise RuntimeError(
                  "Harness AI SRE demo: intentional Lambda failure"
              )

          return {
              "statusCode": 200,
              "body": json.dumps({
                  "message": "Harness AI SRE demo: successful invocation",
                  "request_id": context.aws_request_id
              })
          }
    PYTHON
  }
}

resource "aws_lambda_function" "demo" {
  function_name = local.function_name
  description   = "Harness AI SRE lab: success or deliberate failure."

  role    = aws_iam_role.lambda.arn
  runtime = "python3.12"
  handler = "lambda_function.lambda_handler"

  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256

  memory_size = 128
  timeout     = 10

  depends_on = [
    aws_iam_role_policy.lambda_logs,
    aws_cloudwatch_log_group.lambda
  ]
}

# =============================================================================
# SNS Topic + Alarm
# =============================================================================

resource "aws_sns_topic" "harness" {
  name         = "${var.name_prefix}-alerts"
  display_name = "Harness AI SRE Lab"
  fifo_topic   = false
}

data "aws_iam_policy_document" "sns" {
  statement {
    sid    = "AllowLabAlarmPublish"
    effect = "Allow"

    actions = [
      "sns:Publish"
    ]

    resources = [
      aws_sns_topic.harness.arn
    ]

    principals {
      type = "Service"

      identifiers = [
        "cloudwatch.amazonaws.com"
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"

      values = [
        data.aws_caller_identity.current.account_id
      ]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"

      values = [
        local.alarm_arn
      ]
    }
  }
}

resource "aws_sns_topic_policy" "harness" {
  arn    = aws_sns_topic.harness.arn
  policy = data.aws_iam_policy_document.sns.json
}

# =============================================================================
# Forwarder Lambda (SNS → Harness webhook with Content-Type: application/json)
# =============================================================================

resource "aws_cloudwatch_log_group" "forwarder" {
  name              = local.forwarder_log_group
  retention_in_days = 7
}

resource "aws_iam_role" "forwarder" {
  name               = "${var.name_prefix}-forwarder-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

data "aws_iam_policy_document" "forwarder_logs" {
  statement {
    sid    = "WriteForwarderLogs"
    effect = "Allow"

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = [
      "${aws_cloudwatch_log_group.forwarder.arn}:*"
    ]
  }
}

resource "aws_iam_role_policy" "forwarder_logs" {
  name   = "${var.name_prefix}-forwarder-write-logs"
  role   = aws_iam_role.forwarder.id
  policy = data.aws_iam_policy_document.forwarder_logs.json
}

data "archive_file" "forwarder" {
  type        = "zip"
  output_path = "${path.module}/lambda-forwarder.zip"

  source {
    filename = "forwarder.py"

    content = <<-PYTHON
      import json
      import logging
      import urllib.request

      logger = logging.getLogger()
      logger.setLevel(logging.INFO)

      import os
      WEBHOOK_URL = os.environ["HARNESS_WEBHOOK_URL"]


      def lambda_handler(event, context):
          for record in event.get("Records", []):
              message = record.get("Sns", {}).get("Message", "")

              try:
                  payload = json.loads(message)
              except (json.JSONDecodeError, TypeError):
                  payload = {"raw": message}

              body = json.dumps(payload).encode("utf-8")

              logger.info(
                  "Forwarding to Harness: %s",
                  json.dumps({
                      "alarm_name": payload.get("AlarmName"),
                      "state": payload.get("NewStateValue"),
                      "bytes": len(body)
                  })
              )

              req = urllib.request.Request(
                  WEBHOOK_URL,
                  data=body,
                  headers={"Content-Type": "application/json"},
                  method="POST"
              )

              with urllib.request.urlopen(req, timeout=10) as resp:
                  logger.info("Harness responded: %d", resp.status)

          return {"statusCode": 200}
    PYTHON
  }
}

resource "aws_lambda_function" "forwarder" {
  count = var.enable_harness_subscription ? 1 : 0

  function_name = local.forwarder_name
  description   = "Forwards SNS CloudWatch alerts to Harness with Content-Type: application/json."

  role    = aws_iam_role.forwarder.arn
  runtime = "python3.12"
  handler = "forwarder.lambda_handler"

  filename         = data.archive_file.forwarder.output_path
  source_code_hash = data.archive_file.forwarder.output_base64sha256

  memory_size = 128
  timeout     = 15

  environment {
    variables = {
      HARNESS_WEBHOOK_URL = var.harness_webhook_url
    }
  }

  depends_on = [
    aws_iam_role_policy.forwarder_logs,
    aws_cloudwatch_log_group.forwarder
  ]
}

resource "aws_lambda_permission" "sns_invoke_forwarder" {
  count = var.enable_harness_subscription ? 1 : 0

  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.forwarder[0].function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.harness.arn
}

resource "aws_sns_topic_subscription" "harness" {
  count = var.enable_harness_subscription ? 1 : 0

  topic_arn = aws_sns_topic.harness.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.forwarder[0].arn

  depends_on = [
    aws_lambda_permission.sns_invoke_forwarder,
    aws_sns_topic_policy.harness
  ]
}

# =============================================================================
# CloudWatch Alarm
# =============================================================================

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name = local.alarm_name

  alarm_description = "Harness lab: at least one Lambda error in a one-minute period."

  namespace   = "AWS/Lambda"
  metric_name = "Errors"
  statistic   = "Sum"
  unit        = "Count"

  period              = 60
  evaluation_periods  = 1
  datapoints_to_alarm  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"

  treat_missing_data = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.demo.function_name
  }

  actions_enabled = true

  alarm_actions = [
    aws_sns_topic.harness.arn
  ]

  ok_actions = var.notify_on_recovery ? [
    aws_sns_topic.harness.arn
  ] : []

  insufficient_data_actions = []

  depends_on = [
    aws_sns_topic_policy.harness,
    aws_sns_topic_subscription.harness
  ]
}
