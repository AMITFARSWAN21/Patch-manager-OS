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
        name          = "ubuntu-security"
        products      = ["Ubuntu24.04"]
        configuration = "deb http://security.ubuntu.com/ubuntu noble-security main restricted universe multiverse"
      },
      {
        name          = "ubuntu-updates"
        products      = ["Ubuntu24.04"]
        configuration = "deb http://archive.ubuntu.com/ubuntu noble-updates main restricted universe multiverse"
      },
      {
        name          = "ubuntu-main"
        products      = ["Ubuntu24.04"]
        configuration = "deb http://archive.ubuntu.com/ubuntu noble main restricted universe multiverse"
      }
    ]
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
        "Medium" # ⭐ Amazon Linux uses "Medium" not "Moderate"
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

  rhel = {
    operating_system = "REDHAT_ENTERPRISE_LINUX"
    patch_filters = {
      "CLASSIFICATION" = ["Security", "Bugfix", "Enhancement"]
      "SEVERITY" = [
        "Critical",
        "Important",
        "Moderate" # ⭐ RHEL uses "Moderate"
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

  centos = {
    operating_system = "CENTOS"
    patch_filters = {
      "CLASSIFICATION" = ["Security", "Bugfix", "Enhancement"]
      "SEVERITY" = [
        "Critical",
        "Important",
        "Moderate" # ⭐ CentOS uses "Moderate"
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

  debian = {
    operating_system = "DEBIAN"
    patch_filters = {
      "PRIORITY" = ["Required", "Important", "Standard", "Optional"]
      "SECTION"  = ["*"]
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
