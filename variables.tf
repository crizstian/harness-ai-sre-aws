variable "aws_region" {
  description = "Region containing the EC2 instance and CloudWatch alarm."
  type        = string
  default     = "us-west-2"
}

variable "name_prefix" {
  description = "Prefix used for AWS resource names."
  type        = string
  default     = "harness-ai-sre"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,60}$", var.name_prefix))
    error_message = "Use 1-60 characters: letters, numbers, hyphens or underscores."
  }
}

variable "ec2_instance_id" {
  description = "Existing EC2 instance to monitor in aws_region."
  type        = string

  validation {
    condition     = can(regex("^i-[0-9a-f]+$", var.ec2_instance_id))
    error_message = "Provide a valid EC2 instance ID."
  }
}

variable "enable_harness_subscription" {
  description = "Create the HTTPS subscription when the Harness webhook is available."
  type        = bool
  default     = false
}

variable "harness_webhook_url" {
  description = "Harness CloudWatch webhook URL. Required when subscription is enabled."
  type        = string
  sensitive   = true
  default     = ""

  validation {
    condition = (
      var.harness_webhook_url == "" ||
      can(regex("^https://[^[:space:]]+$", var.harness_webhook_url))
    )
    error_message = "Provide an HTTPS URL without spaces, or leave it empty."
  }
}

variable "cpu_threshold" {
  description = "CPU utilization percentage above which the alarm triggers."
  type        = number
  default     = 80

  validation {
    condition     = var.cpu_threshold > 0 && var.cpu_threshold <= 100
    error_message = "cpu_threshold must be greater than 0 and at most 100."
  }
}

variable "notify_on_recovery" {
  description = "Also publish OK transitions. Enable after validating Harness recovery mapping."
  type        = bool
  default     = false
}