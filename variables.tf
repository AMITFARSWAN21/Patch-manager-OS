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

variable "environment_patterns" {
  description = "Environment tag patterns to match"
  type        = list(string)
  default     = ["Production", "prod", "PROD", "production"]
}

variable "os_patch_configs" {
  description = "Patch management configurations"

  type = map(object({
    operating_system     = string
    patch_filters        = map(list(string))
    compliance_level     = string
    approval_delay       = number
    schedule             = string
    duration             = number
    max_concurrency      = string
    max_errors           = string
    enable_non_security  = bool
    use_approved_patches = bool
    approved_patches     = list(string)
    patch_sources = list(object({
      name          = string
      products      = list(string)
      configuration = string
    }))
  }))

  default = {
    ubuntu = {
      operating_system = "UBUNTU"
      patch_filters = {
        "PRIORITY" = ["Required", "Important", "Standard", "Optional", "Extra"]
        "SECTION"  = ["*"]
      }
      compliance_level     = "HIGH"
      approval_delay       = 0
      schedule             = "cron(0 0/30 * 1/1 * ? *)"
      duration             = 2
      max_concurrency      = "100%"
      max_errors           = "0%"
      enable_non_security  = true
      use_approved_patches = true
      approved_patches     = ["*"]
      patch_sources = [
        {
          name          = "ubuntu22-security"
          products      = ["Ubuntu22.04"]
          configuration = "deb http://security.ubuntu.com/ubuntu jammy-security main restricted universe multiverse"
        },
        {
          name          = "ubuntu22-updates"
          products      = ["Ubuntu22.04"]
          configuration = "deb http://archive.ubuntu.com/ubuntu jammy-updates main restricted universe multiverse"
        },
        {
          name          = "ubuntu22-main"
          products      = ["Ubuntu22.04"]
          configuration = "deb http://archive.ubuntu.com/ubuntu jammy main restricted universe multiverse"
        },
        {
          name          = "ubuntu24-security"
          products      = ["Ubuntu24.04"]
          configuration = "deb http://security.ubuntu.com/ubuntu noble-security main restricted universe multiverse"
        },
        {
          name          = "ubuntu24-updates"
          products      = ["Ubuntu24.04"]
          configuration = "deb http://archive.ubuntu.com/ubuntu noble-updates main restricted universe multiverse"
        },
        {
          name          = "ubuntu24-main"
          products      = ["Ubuntu24.04"]
          configuration = "deb http://archive.ubuntu.com/ubuntu noble main restricted universe multiverse"
        }
      ]
    }

    windows = {
      operating_system = "WINDOWS"
      patch_filters = {
        "CLASSIFICATION" = ["CriticalUpdates", "SecurityUpdates", "Updates"]
        "MSRC_SEVERITY"  = ["Critical", "Important", "Moderate"]
      }
      compliance_level     = "CRITICAL"
      approval_delay       = 0
      schedule             = "cron(0 0/30 * 1/1 * ? *)"
      duration             = 4
      max_concurrency      = "50%"
      max_errors           = "10%"
      enable_non_security  = false
      use_approved_patches = false
      approved_patches     = []
      patch_sources        = []
    }

    amazonlinux = {
      operating_system = "AMAZON_LINUX_2023"
      patch_filters = {
        "CLASSIFICATION" = ["Security", "Bugfix", "Enhancement"]
        "SEVERITY"       = ["Critical", "Important", "Medium"]
      }
      compliance_level     = "HIGH"
      approval_delay       = 0
      schedule             = "cron(0 0/30 * 1/1 * ? *)"
      duration             = 2
      max_concurrency      = "100%"
      max_errors           = "0%"
      enable_non_security  = true
      use_approved_patches = false
      approved_patches     = []
      patch_sources        = []
    }
  }
}

variable "maintenance_window_role_name" {
  description = "Name for the maintenance window IAM role"
  type        = string
  default     = "SSM-MaintenanceWindow-Role"
}

variable "additional_tags" {
  description = "Additional tags to apply to patch management resources"
  type        = map(string)
  default = {
    ManagedBy = "Terraform"
    Purpose   = "PatchManagement"
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "availability_zone" {
  description = "Availability zone for subnets"
  type        = string
  default     = "ap-south-1a"
}

variable "public_subnet_cidr" {
  description = "CIDR for public subnet where WSUS server lives"
  type        = string
  default     = "10.0.2.0/24"
}