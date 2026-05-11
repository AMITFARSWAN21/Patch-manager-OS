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
  description = "Environment tag patterns to match (for existing instances with different naming)"
  type        = list(string)
  default     = ["Production", "prod", "PROD", "production"]
}

variable "os_detection_rules" {
  description = "Rules to detect OS from AMI names and instance names"
  type = object({
    ami_patterns = map(list(string))
    name_patterns = map(list(string))
  })
  
  default = {
    ami_patterns = {
      ubuntu      = ["ubuntu", "Ubuntu", "canonical"]
      windows     = ["Windows", "windows", "WIN", "win", "microsoft"]
      amazonlinux = ["amzn", "amazon", "Amazon", "al2023", "al2", "amazon-linux"]
      rhel        = ["rhel", "RHEL", "red-hat", "redhat"]
      centos      = ["centos", "CentOS", "CENTOS"]
    }
    name_patterns = {
      ubuntu      = ["ubuntu", "web", "app", "nginx", "apache"]
      windows     = ["win", "WIN", "windows", "iis", "sql", "ad", "dc"]
      amazonlinux = ["amzn", "amazon", "linux", "nat", "bastion"]
      rhel        = ["rhel", "red-hat", "enterprise"]
      centos      = ["centos", "cent"]
    }
  }
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
  }))

  default = {
    ubuntu = {
      operating_system = "UBUNTU"
      patch_filters = {
        "PRIORITY" = ["Required", "Important", "Standard", "Optional", "Extra"]
        "SECTION" = ["*"]
      }
      compliance_level     = "HIGH"
      approval_delay       = 0
      schedule            = "rate(30 minutes)"  # ← CHANGED: Every 30 minutes for testing
      duration            = 1                   # ← CHANGED: 1 hour duration
      max_concurrency     = "50%"
      max_errors          = "10%"
      enable_non_security = true
    }

    windows = {
      operating_system = "WINDOWS"
      patch_filters = {
        "CLASSIFICATION" = ["CriticalUpdates", "SecurityUpdates", "Updates", "UpdateRollups"]
        "MSRC_SEVERITY" = ["Critical", "Important", "Moderate", "Low"]
      }
      compliance_level     = "CRITICAL"
      approval_delay       = 0
      schedule            = "rate(30 minutes)"  # ← CHANGED: Every 30 minutes for testing
      duration            = 1                   # ← CHANGED: 1 hour duration
      max_concurrency     = "25%"
      max_errors          = "15%"
      enable_non_security = false
    }

    amazonlinux = {
      operating_system = "AMAZON_LINUX_2023"
      patch_filters = {
        "CLASSIFICATION" = ["Security", "Bugfix", "Enhancement"]
        "SEVERITY"       = ["Critical", "Important", "Medium"]
      }
      compliance_level     = "HIGH"
      approval_delay       = 0
      schedule            = "rate(30 minutes)"  # ← CHANGED: Every 30 minutes for testing
      duration            = 1                   # ← CHANGED: 1 hour duration
      max_concurrency     = "75%"
      max_errors          = "5%"
      enable_non_security = true
    }

    rhel = {
      operating_system = "REDHAT_ENTERPRISE_LINUX"
      patch_filters = {
        "CLASSIFICATION" = ["Security", "Bugfix", "Enhancement"]
        "SEVERITY"       = ["Critical", "Important", "Medium"]
      }
      compliance_level     = "HIGH"
      approval_delay       = 0
      schedule            = "rate(30 minutes)"  # ← CHANGED: Every 30 minutes for testing
      duration            = 1                   # ← CHANGED: 1 hour duration
      max_concurrency     = "50%"
      max_errors          = "10%"
      enable_non_security = true
    }

    centos = {
      operating_system = "CENTOS"
      patch_filters = {
        "CLASSIFICATION" = ["Security", "Bugfix", "Enhancement"]
        "SEVERITY"       = ["Critical", "Important", "Medium"]
      }
      compliance_level     = "HIGH"
      approval_delay       = 0
      schedule            = "rate(30 minutes)"  # ← CHANGED: Every 30 minutes for testing
      duration            = 1                   # ← CHANGED: 1 hour duration
      max_concurrency     = "50%"
      max_errors          = "10%"
      enable_non_security = true
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
