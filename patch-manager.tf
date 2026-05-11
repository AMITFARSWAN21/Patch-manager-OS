# Patch baselines for ALL OS types
resource "aws_ssm_patch_baseline" "os_baselines" {
  for_each = var.os_patch_configs

  name             = "${each.key}-Production-Baseline-${random_string.suffix.result}"
  description      = "Patch baseline for ${each.key} production instances"
  operating_system = each.value.operating_system

  # Ubuntu: Use approved_patches ONLY (no approval_rule)
  approved_patches                     = each.key == "ubuntu" ? ["*"] : []
  approved_patches_compliance_level    = each.key == "ubuntu" ? "HIGH" : "UNSPECIFIED"
  approved_patches_enable_non_security = each.key == "ubuntu" ? true : false

  # Other OS types: Use approval_rule ONLY
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

  tags = merge(var.additional_tags, {
    Name        = "${each.key}-Production-Baseline"
    Environment = var.target_environment
    OS          = each.key
  })
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

  tags = merge(var.additional_tags, {
    Name        = "${each.key}-Production-MaintenanceWindow"
    Environment = var.target_environment
    OS          = each.key
  })
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
    values = var.environment_patterns
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

# Optional: Associations for patch scans (commented out by default)
# resource "aws_ssm_association" "os_patch_scans" {
#   for_each = var.os_patch_configs

#   name                = "AWS-RunPatchBaseline"
#   schedule_expression = "cron(0 */6 * * ? *)"  # Every 6 hours

#   targets {
#     key    = "tag:Environment"
#     values = var.environment_patterns
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
