variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "target_environment" {
  description = "Environment tag value to target existing instances"
  type        = string
  default     = "Production"
}


variable "os_patch_configs" {
  description = "Patch management configurations"
  
  type = map(object({
    operating_system     = string
    patch_filters        = map(list(string))
    compliance_level     = string
    approval_delay       = number
    schedule             = string
    # scan_schedule        = string
    duration             = number
    max_concurrency      = string
    max_errors           = string
    enable_non_security  = bool
  }))

  default = {

    ubuntu = {
      operating_system = "UBUNTU"

      patch_filters = {
        "PRIORITY" = [
          "Required",
          "Important",
          "Standard",
          "Optional",
          "Extra"
        ]

        "SECTION" = ["*"]
      }

      compliance_level     = "HIGH"
      approval_delay       = 0
      schedule      = "rate(1 hour)"
      #  scan_schedule = "rate(30 minutes)"
      duration             = 2
      max_concurrency      = "100%"
      max_errors           = "0%"
      enable_non_security  = true
    }

    windows = {
      operating_system = "WINDOWS"

      patch_filters = {
        "CLASSIFICATION" = [
          "CriticalUpdates",
          "SecurityUpdates",
          "Updates",
          "UpdateRollups"
        ]

        "MSRC_SEVERITY" = [
          "Critical",
          "Important",
          "Moderate",
          "Low"
        ]
      }

      compliance_level     = "CRITICAL"
      approval_delay       = 0
     schedule      = "rate(1 hour)"
      # scan_schedule = "rate(30 minutes)"
      duration             = 4
      max_concurrency      = "50%"
      max_errors           = "10%"
      enable_non_security  = false
    }

    amazonlinux = {
      operating_system = "AMAZON_LINUX_2023"

      patch_filters = {
        "CLASSIFICATION" = ["Security"]
        "SEVERITY"       = ["Critical", "Important", "Medium"]
      }

      compliance_level     = "HIGH"
      approval_delay       = 0
     schedule      = "rate(1 hour)"
# scan_schedule = "rate(30 minutes)"
      duration             = 2
      max_concurrency      = "100%"
      max_errors           = "0%"
      enable_non_security  = true
    }
  }
}