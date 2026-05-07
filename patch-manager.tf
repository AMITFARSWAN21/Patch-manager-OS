resource "aws_ssm_patch_baseline" "production_baseline" {
  name             = "Production-Patch-Baseline-${random_string.suffix.result}"
  description      = "Patch baseline for production Ubuntu instances"
  operating_system = "UBUNTU"

  approval_rule {
    approve_after_days  = 0
    compliance_level    = "HIGH"
    enable_non_security = true

    patch_filter {
      key    = "PRIORITY"
      values = ["Required", "Important", "Standard", "Optional", "Extra"]
    }

    # FIXED: Use "*" instead of "All" for Ubuntu SECTION
    patch_filter {
      key    = "SECTION"
      values = ["*"]
    }
  }

  tags = {
    Name = "Production-Patch-Baseline"
    Environment = "Production"
  }
}

# Register production patch baseline with Production patch group
resource "aws_ssm_patch_group" "production_group" {
  baseline_id = aws_ssm_patch_baseline.production_baseline.id
  patch_group = var.patch_group_name
}

# Production Maintenance Window - FIXED TIMING
resource "aws_ssm_maintenance_window" "production_window" {
  name              = "Production-Maintenance-Window-${random_string.suffix.result}"
  description       = "Maintenance window for production instances"
  schedule          = "rate(10 minutes)"  # CHANGED: Every hour for testing
  duration          = 2
  cutoff            = 0
  allow_unassociated_targets = false

  tags = {
    Name = "Production-Maintenance-Window"
    Environment = "Production"
  }
}

# Production Maintenance Window Target
resource "aws_ssm_maintenance_window_target" "production_target" {
  name          = "Production-Targets"
  description   = "Production instances for patching"
  resource_type = "INSTANCE"
  window_id     = aws_ssm_maintenance_window.production_window.id

  targets {
    key    = "tag:Environment"
    values = [var.target_environment]
  }

  targets {
    key    = "tag:PatchGroup"
    values = [var.patch_group_name]
  }
}

# Production Maintenance Window Task for Patching
resource "aws_ssm_maintenance_window_task" "production_patch_task" {
  window_id        = aws_ssm_maintenance_window.production_window.id
  name             = "Production-Patch-Task"
  description      = "Patch production instances"
  task_type        = "RUN_COMMAND"
  task_arn         = "AWS-RunPatchBaseline"
  service_role_arn = aws_iam_role.maintenance_window_role.arn
  priority         = 1
  max_concurrency  = "100%"  # CHANGED: Patch all at once for testing
  max_errors       = "0%"    # CHANGED: Stop on any error for testing

  targets {
    key    = "WindowTargetIds"
    values = [aws_ssm_maintenance_window_target.production_target.id]
  }

  task_invocation_parameters {
    run_command_parameters {
      parameter {
        name   = "Operation"
        values = ["Install"]
      }
      parameter {
        name   = "RebootOption"
        values = ["RebootIfNeeded"]
      }
    }
  }
}

# Production Patch Scan Association - AGGRESSIVE FOR TESTING
resource "aws_ssm_association" "production_patch_scan" {
  name             = "AWS-RunPatchBaseline"
   schedule_expression = "rate(30 minutes)"  # Every 30 minutes for testing

  targets {
    key    = "tag:Environment"
    values = [var.target_environment]
  }

  parameters = {
    Operation = "Scan"
  }

  depends_on = [aws_ec2_tag.patch_group_tag]
}



# Windows Patch Baseline
resource "aws_ssm_patch_baseline" "windows_production_baseline" {
  name             = "Windows-Production-Patch-Baseline-${random_string.suffix.result}"
  description      = "Patch baseline for production Windows instances"
  operating_system = "WINDOWS"

  approval_rule {
    approve_after_days = 0
    compliance_level   = "CRITICAL"

    patch_filter {
      key    = "CLASSIFICATION"
      values = ["CriticalUpdates", "SecurityUpdates", "Updates", "UpdateRollups"]
    }

    patch_filter {
      key    = "MSRC_SEVERITY"
      values = ["Critical", "Important", "Moderate", "Low"]
    }
  }

  tags = {
    Name        = "Windows-Production-Patch-Baseline"
    Environment = "Production"
    OS          = "Windows"
  }
}
# Register Windows patch baseline with Windows patch group
resource "aws_ssm_patch_group" "windows_production_group" {
  baseline_id = aws_ssm_patch_baseline.windows_production_baseline.id
  patch_group = "Windows-Production-PatchGroup"
}

# Windows Maintenance Window — 10 minutes for testing
resource "aws_ssm_maintenance_window" "windows_production_window" {
  name        = "Windows-Production-Maintenance-Window-${random_string.suffix.result}"
  description = "Maintenance window for Windows production instances"
  schedule    = "rate(10 minutes)"
  duration    = 2
  cutoff      = 0
  allow_unassociated_targets = false

  tags = {
    Name        = "Windows-Production-Maintenance-Window"
    Environment = "Production"
    OS          = "Windows"
  }
}

# Windows Maintenance Window Target
# Targets directly by Environment and OS tags — no extra tags needed
resource "aws_ssm_maintenance_window_target" "windows_production_target" {
  window_id     = aws_ssm_maintenance_window.windows_production_window.id
  name          = "Windows-Production-Targets"
  description   = "Windows production instances for patching"
  resource_type = "INSTANCE"

  targets {
    key    = "tag:Environment"
    values = [var.target_environment]
  }

  targets {
    key    = "tag:OS"
    values = ["Windows"]
  }
}

# Windows Maintenance Window Task
resource "aws_ssm_maintenance_window_task" "windows_production_patch_task" {
  window_id        = aws_ssm_maintenance_window.windows_production_window.id
  name             = "Windows-Production-Patch-Task"
  description      = "Patch Windows production instances"
  task_type        = "RUN_COMMAND"
  task_arn         = "AWS-RunPatchBaseline"
  service_role_arn = aws_iam_role.maintenance_window_role.arn
  priority         = 1
  max_concurrency  = "20%"
  max_errors       = "10%"

  targets {
    key    = "WindowTargetIds"
    values = [aws_ssm_maintenance_window_target.windows_production_target.id]
  }

  task_invocation_parameters {
    run_command_parameters {
      parameter {
        name   = "Operation"
        values = ["Install"]
      }
      parameter {
        name   = "RebootOption"
        values = ["RebootIfNeeded"]
      }
    }
  }
}

# Windows Patch Scan Association — 5 minutes for testing
# Targets directly by Environment and OS tags — no extra tags needed
resource "aws_ssm_association" "windows_production_patch_scan" {
  name                = "AWS-RunPatchBaseline"
   schedule_expression = "rate(30 minutes)"

  targets {
    key    = "tag:Environment"
    values = [var.target_environment]
  }

  targets {
    key    = "tag:OS"
    values = ["Windows"]
  }

  parameters = {
    Operation = "Scan"
  }
}