output "aws_region" {
  description = "AWS region used by this lab."
  value       = var.aws_region
}

output "lambda_function_name" {
  description = "Name of the demo Lambda."
  value       = aws_lambda_function.demo.function_name
}

output "lambda_function_arn" {
  description = "ARN of the demo Lambda."
  value       = aws_lambda_function.demo.arn
}

output "lambda_log_group_name" {
  description = "CloudWatch Logs group for the Lambda."
  value       = aws_cloudwatch_log_group.lambda.name
}

output "alarm_name" {
  description = "CloudWatch alarm name."
  value       = aws_cloudwatch_metric_alarm.lambda_errors.alarm_name
}

output "alarm_arn" {
  description = "CloudWatch alarm ARN."
  value       = aws_cloudwatch_metric_alarm.lambda_errors.arn
}

output "sns_topic_arn" {
  description = "SNS topic used for alarm notifications."
  value       = aws_sns_topic.harness.arn
}

output "forwarder_function_name" {
  description = "Name of the forwarder Lambda, if enabled."
  value = try(
    aws_lambda_function.forwarder[0].function_name,
    null
  )
}

output "forwarder_function_arn" {
  description = "ARN of the forwarder Lambda, if enabled."
  value = try(
    aws_lambda_function.forwarder[0].arn,
    null
  )
}

output "harness_subscription_enabled" {
  description = "Whether the Harness subscription is configured."
  value       = var.enable_harness_subscription
}

output "harness_subscription_arn" {
  description = "Harness subscription ARN, if enabled."
  value = try(
    aws_sns_topic_subscription.harness[0].arn,
    null
  )
}
