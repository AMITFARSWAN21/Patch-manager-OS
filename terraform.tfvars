aws_region         = "ap-south-1"
target_environment = "Production"

os_patch_configs = {
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
    schedule             = "cron(0 0/30 * 1/1 * ? *)" # Every 30 minutes
    duration             = 2
    max_concurrency      = "100%"
    max_errors           = "0%"
    enable_non_security  = true
    use_approved_patches = true
    # ADDED: Explicit patch approval for Ubuntu - includes your CVEs
    approved_patches = ["*"]
    # ADDED: Custom patch sources for Ubuntu
    patch_sources        = []  
  }
  windows = {
    operating_system = "WINDOWS"
    patch_filters = {
      "CLASSIFICATION" = [
        "CriticalUpdates",
        "SecurityUpdates",
        "Updates"
      ]
      "MSRC_SEVERITY" = [
        "Critical",
        "Important",
        "Moderate"
      ]
    }
    compliance_level     = "CRITICAL"
    approval_delay       = 0
    schedule             = "cron(0 0/30 * 1/1 * ? *)" # Every 30 minutes
    duration             = 4
    max_concurrency      = "50%"
    max_errors           = "10%"
    enable_non_security  = false
    use_approved_patches = false
    # ADDED: Required fields for consistency
    approved_patches = []
    patch_sources    = []
  }

  amazonlinux = {
    operating_system = "AMAZON_LINUX_2023"
    patch_filters = {
      "CLASSIFICATION" = ["Security", "Bugfix", "Enhancement"]
      "SEVERITY" = [
        "Critical",
        "Important",
        "Medium" 
      ]
    }
    compliance_level     = "HIGH"
    approval_delay       = 0
    schedule             = "cron(0 0/30 * 1/1 * ? *)" # Every 30 minutes
    duration             = 2
    max_concurrency      = "100%"
    max_errors           = "0%"
    enable_non_security  = true
    use_approved_patches = false
    # ADDED: Required fields for consistency
    approved_patches = []
    patch_sources    = []
  }
}

environment_patterns = ["Production", "prod", "PROD", "production"]

additional_tags = {
  ManagedBy = "Terraform"
  Purpose   = "PatchManagement"
  Owner     = "DevOps"
}


vpc_cidr            = "10.0.0.0/16"
private_subnet_cidr = "10.0.1.0/24"
availability_zone   = "ap-south-1a"
public_subnet_cidr = "10.0.2.0/24"