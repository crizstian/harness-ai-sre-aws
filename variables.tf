variable "aws_region" {
  description = "AWS region where the lab will be deployed."
  type        = string
  default     = "us-west-2"
}

variable "name_prefix" {
  description = "Prefix for lab resource names. Use a unique prefix per lab."
  type        = string
  default     = "harness-ai-sre-lab"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,40}$", var.name_prefix))
    error_message = "Use 1-40 characters: letters, numbers, hyphens or underscores."
  }
}

variable "enable_harness_subscription" {
  description = "Create the HTTPS subscription when the Harness webhook is ready."
  type        = bool
  default     = false
}

variable "harness_webhook_url" {
  description = "Harness CloudWatch webhook URL."
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

variable "notify_on_recovery" {
  description = "Publish OK transitions too. Enable after validating Harness recovery mapping."
  type        = bool
  default     = false
}