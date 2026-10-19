output "aws_region" {
  description = "AWS deployment region."
  value       = var.aws_region
}

output "sns_topic_arn" {
  description = "SNS topic receiving CloudWatch notifications."
  value       = aws_sns_topic.harness.arn
}

output "alarm_name" {
  description = "CloudWatch alarm name."
  value       = aws_cloudwatch_metric_alarm.cpu.alarm_name
}

output "alarm_arn" {
  description = "CloudWatch alarm ARN."
  value       = aws_cloudwatch_metric_alarm.cpu.arn
}

output "monitored_instance_id" {
  description = "EC2 instance monitored by the alarm."
  value       = data.aws_instance.monitored.id
}

output "harness_subscription_enabled" {
  description = "Whether the HTTPS subscription is configured."
  value       = var.enable_harness_subscription
}

output "harness_subscription_arn" {
  description = "HTTPS subscription ARN, if enabled."
  value = try(
    aws_sns_topic_subscription.harness[0].arn,
    null
  )
}