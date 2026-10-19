data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

# Validate that the instance exists in the configured account and region.
data "aws_instance" "monitored" {
  instance_id = var.ec2_instance_id
}

locals {
  alarm_name = "${var.name_prefix}-ec2-high-cpu"

  # Build the ARN ahead of time to avoid a dependency cycle:
  # alarm -> subscription -> topic policy -> alarm.
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

resource "aws_sns_topic" "harness" {
  name         = "${var.name_prefix}-alerts"
  display_name = "Harness AI SRE Alerts"
  fifo_topic   = false
}

data "aws_iam_policy_document" "sns" {
  statement {
    sid    = "AllowCloudWatchAlarmPublish"
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

resource "aws_sns_topic_subscription" "harness" {
  count = var.enable_harness_subscription ? 1 : 0

  topic_arn = aws_sns_topic.harness.arn
  protocol  = "https"
  endpoint  = var.harness_webhook_url

  # Preserve the SNS envelope, including its Message field.
  raw_message_delivery = false

  # This declares endpoint capability; it does NOT confirm on its behalf.
  endpoint_auto_confirms          = true
  confirmation_timeout_in_minutes = 5

  lifecycle {
    precondition {
      condition     = length(trimspace(var.harness_webhook_url)) > 0
      error_message = "Set harness_webhook_url before enabling the subscription."
    }
  }

  depends_on = [
    aws_sns_topic_policy.harness
  ]
}

resource "aws_cloudwatch_metric_alarm" "cpu" {
  alarm_name        = local.alarm_name
  alarm_description = "EC2 CPU utilization above ${var.cpu_threshold}% for two consecutive 5-minute periods."

  namespace   = "AWS/EC2"
  metric_name = "CPUUtilization"
  statistic   = "Average"
  unit        = "Percent"

  period              = 300
  evaluation_periods  = 2
  datapoints_to_alarm  = 2
  threshold           = var.cpu_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    InstanceId = data.aws_instance.monitored.id
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