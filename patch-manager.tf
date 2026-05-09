# Patch baselines for ALL OS types (no instance filtering)
resource "aws_ssm_patch_baseline" "os_baselines" {
  for_each = var.os_patch_configs

  name             = "${each.key}-Production-Baseline-${random_string.suffix.result}"
  description      = "Patch baseline for ${each.key} production instances"
  operating_system = each.value.operating_system

  # Ubuntu: Use approved_patches ONLY (no approval_rule)
  approved_patches                     = each.key == "ubuntu" ? ["*"] : []
  approved_patches_compliance_level    = each.key == "ubuntu" ? "HIGH" : "UNSPECIFIED"
  approved_patches_enable_non_security = each.key == "ubuntu" ? true : false

  # Windows/Amazon Linux: Use approval_rule ONLY
  dynamic "approval_rule" {
    for_each = each.key != "ubuntu" ? [1] : []

    content {
      approve_after_days  = each.value.approval_delay
      compliance_level    = each.value.compliance_level
      enable_non_security = each.value.enable_non_security

      dynamic "patch_filter" {
        for_each = each.value.patch_filters
        content {
          key    = patch_filter.key
          values = patch_filter.value
        }
      }
    }
  }

  tags = {
    Name        = "${each.key}-Production-Baseline"
    Environment = var.target_environment
    OS          = each.key
  }
}

# Patch groups for ALL OS types
resource "aws_ssm_patch_group" "os_patch_groups" {
  for_each = var.os_patch_configs

  baseline_id = aws_ssm_patch_baseline.os_baselines[each.key].id
  patch_group = "${each.key}-Production-PatchGroup"
}

# Maintenance windows for ALL OS types
resource "aws_ssm_maintenance_window" "os_maintenance_windows" {
  for_each = var.os_patch_configs

  name                       = "${each.key}-Production-MW-${random_string.suffix.result}"
  description                = "Maintenance window for ${each.key} production instances"
  schedule                   = each.value.schedule
  duration                   = each.value.duration
  cutoff                     = 1
  allow_unassociated_targets = false

  tags = {
    Name        = "${each.key}-Production-MaintenanceWindow"
    Environment = var.target_environment
    OS          = each.key
  }
}

# Maintenance window targets for ALL OS types
resource "aws_ssm_maintenance_window_target" "os_targets" {
  for_each = var.os_patch_configs

  window_id     = aws_ssm_maintenance_window.os_maintenance_windows[each.key].id
  name          = "${each.key}-Production-Targets"
  description   = "${each.key} production instances for patching"
  resource_type = "INSTANCE"

  targets {
    key    = "tag:Environment"
    values = [var.target_environment]
  }

  targets {
    key    = "tag:OS"
    values = [each.key]
  }

  targets {
    key    = "tag:AutoPatch"
    values = ["true"]
  }
}

# Maintenance window tasks for ALL OS types
resource "aws_ssm_maintenance_window_task" "os_patch_tasks" {
  for_each = var.os_patch_configs

  window_id        = aws_ssm_maintenance_window.os_maintenance_windows[each.key].id
  name             = "${each.key}-Production-PatchTask"
  description      = "Patch ${each.key} production instances"
  task_type        = "RUN_COMMAND"
  task_arn         = "AWS-RunPatchBaseline"
  service_role_arn = aws_iam_role.maintenance_window_role.arn

  priority        = 1
  max_concurrency = each.value.max_concurrency
  max_errors      = each.value.max_errors

  targets {
    key    = "WindowTargetIds"
    values = [aws_ssm_maintenance_window_target.os_targets[each.key].id]
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

      timeout_seconds = 7200
    }
  }
}

# Associations for daily patch scans for ALL OS types
# resource "aws_ssm_association" "os_patch_scans" {
#   for_each = var.os_patch_configs

#   name                = "AWS-RunPatchBaseline"
#   # schedule_expression = each.value.scan_schedule

#   targets {
#     key    = "tag:Environment"
#     values = [var.target_environment]
#   }

#   targets {
#     key    = "tag:OS"
#     values = [each.key]
#   }

#   targets {
#     key    = "tag:AutoPatch"
#     values = ["true"]
#   }

#   parameters = {
#     Operation = "Scan"
#   }

#   compliance_severity = "HIGH"
# }

# Data source to check existing instances (for informational purposes only)
data "aws_instances" "os_instances" {
  for_each = var.os_patch_configs

  filter {
    name   = "tag:Environment"
    values = [var.target_environment]
  }

  filter {
    name   = "tag:OS"
    values = [each.key]
  }

  filter {
    name   = "instance-state-name"
    values = ["running"]
  }
}

# Output to show instance discovery results (informational only)
output "instance_discovery" {
  description = "Instance discovery results by OS type"
  value = {
    for k, v in data.aws_instances.os_instances : k => {
      instance_count     = length(v.ids)
      instance_ids       = v.ids
      baseline_exists    = contains(keys(aws_ssm_patch_baseline.os_baselines), k)
      maintenance_window_exists = contains(keys(aws_ssm_maintenance_window.os_maintenance_windows), k)
    }
  }
}

# Output patch baseline information for ALL OS types
output "patch_baselines" {
  description = "Created patch baselines"
  value = {
    for k, v in aws_ssm_patch_baseline.os_baselines : k => {
      id   = v.id
      name = v.name
      os   = v.operating_system
    }
  }
}

# Output maintenance window information for ALL OS types
output "maintenance_windows" {
  description = "Created maintenance windows"
  value = {
    for k, v in aws_ssm_maintenance_window.os_maintenance_windows : k => {
      id       = v.id
      name     = v.name
      schedule = v.schedule
    }
  }
}

# Output patch groups for ALL OS types
output "patch_groups" {
  description = "Created patch groups"
  value = {
    for k, v in aws_ssm_patch_group.os_patch_groups : k => {
      baseline_id = v.baseline_id
      patch_group = v.patch_group
    }
  }
}

# Random string for unique naming (if not already defined)
# resource "random_string" "suffix" {
#   length  = 8
#   special = false
#   upper   = false
# }
