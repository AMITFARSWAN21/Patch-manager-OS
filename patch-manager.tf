
# # Patch baselines for ALL OS types
# resource "aws_ssm_patch_baseline" "os_baselines" {
#   for_each = var.os_patch_configs

#   name             = "${each.key}-Production-Baseline-${random_string.suffix.result}"
#   description      = "Patch baseline for ${each.key} production instances"
#   operating_system = each.value.operating_system

#   # Ubuntu and other OS types that use approved_patches
#   approved_patches                     = each.value.use_approved_patches ? ["*"] : []
#   approved_patches_compliance_level    = each.value.use_approved_patches ? each.value.compliance_level : "UNSPECIFIED"
#   approved_patches_enable_non_security = each.value.use_approved_patches ? each.value.enable_non_security : false

#   # Other OS types: Use approval_rule
#   dynamic "approval_rule" {
#     for_each = !each.value.use_approved_patches ? [1] : []

#     content {
#       approve_after_days  = each.value.approval_delay
#       compliance_level    = each.value.compliance_level
#       enable_non_security = each.value.enable_non_security

#       dynamic "patch_filter" {
#         for_each = each.value.patch_filters
#         content {
#           key    = patch_filter.key
#           values = patch_filter.value
#         }
#       }
#     }
#   }

#   tags = merge(var.additional_tags, {
#     Name        = "${each.key}-Production-Baseline"
#     Environment = var.target_environment
#     OS          = each.key
#   })
# }

# # Patch groups for ALL OS types
# resource "aws_ssm_patch_group" "os_patch_groups" {
#   for_each = var.os_patch_configs

#   baseline_id = aws_ssm_patch_baseline.os_baselines[each.key].id
#   patch_group = "${each.key}-Production-PatchGroup"
# }

# # Maintenance windows for ALL OS types
# resource "aws_ssm_maintenance_window" "os_maintenance_windows" {
#   for_each = var.os_patch_configs

#   name                       = "${each.key}-Production-MW-${random_string.suffix.result}"
#   description                = "Maintenance window for ${each.key} production instances"
#   schedule                   = each.value.schedule
#   duration                   = each.value.duration
#   cutoff                     = 1
#   allow_unassociated_targets = false

#   tags = merge(var.additional_tags, {
#     Name        = "${each.key}-Production-MaintenanceWindow"
#     Environment = var.target_environment
#     OS          = each.key
#   })
# }

# # Maintenance window targets for ALL OS types
# resource "aws_ssm_maintenance_window_target" "os_targets" {
#   for_each = var.os_patch_configs

#   window_id     = aws_ssm_maintenance_window.os_maintenance_windows[each.key].id
#   name          = "${each.key}-Production-Targets"
#   description   = "${each.key} production instances for patching"
#   resource_type = "INSTANCE"

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
# }

# # Maintenance window tasks for ALL OS types
# resource "aws_ssm_maintenance_window_task" "os_patch_tasks" {
#   for_each = var.os_patch_configs

#   window_id        = aws_ssm_maintenance_window.os_maintenance_windows[each.key].id
#   name             = "${each.key}-Production-PatchTask"
#   description      = "Patch ${each.key} production instances"
#   task_type        = "RUN_COMMAND"
#   task_arn         = "AWS-RunPatchBaseline"
#   service_role_arn = aws_iam_role.maintenance_window_role.arn

#   priority        = 1
#   max_concurrency = each.value.max_concurrency
#   max_errors      = each.value.max_errors

#   targets {
#     key    = "WindowTargetIds"
#     values = [aws_ssm_maintenance_window_target.os_targets[each.key].id]
#   }

#   task_invocation_parameters {
#     run_command_parameters {
#       parameter {
#         name   = "Operation"
#         values = ["Install"]
#       }

#       parameter {
#         name   = "RebootOption"
#         values = ["RebootIfNeeded"]
#       }

#       timeout_seconds = 7200
#     }
#   }
# }


# # Random string for unique naming
# resource "random_string" "suffix" {
#   length  = 8
#   special = false
#   upper   = false
# }

# # IAM role for maintenance window
# resource "aws_iam_role" "maintenance_window_role" {
#   name = var.maintenance_window_role_name

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Action = "sts:AssumeRole"
#         Effect = "Allow"
#         Principal = {
#           Service = "ssm.amazonaws.com"
#         }
#       }
#     ]
#   })

#   tags = var.additional_tags
# }

# # IAM role policy attachment
# resource "aws_iam_role_policy_attachment" "maintenance_window_role_policy" {
#   role       = aws_iam_role.maintenance_window_role.name
#   policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonSSMMaintenanceWindowRole"
# }

# Patch baselines for ALL OS types
resource "aws_ssm_patch_baseline" "os_baselines" {
  for_each = var.os_patch_configs

  name             = "${each.key}-Production-Baseline-${random_string.suffix.result}"
  description      = "Patch baseline for ${each.key} production instances"
  operating_system = each.value.operating_system

  # Ubuntu and other OS types that use approved_patches
  approved_patches                     = each.value.use_approved_patches ? each.value.approved_patches : []
  approved_patches_compliance_level    = each.value.use_approved_patches ? each.value.compliance_level : "UNSPECIFIED"
  approved_patches_enable_non_security = each.value.use_approved_patches ? each.value.enable_non_security : false

  # Patch sources for Ubuntu (and other Linux distros that need custom repos)
  dynamic "source" {
    for_each = each.value.patch_sources
    content {
      name          = source.value.name
      products      = source.value.products
      configuration = source.value.configuration
    }
  }

  # Other OS types: Use approval_rule
  dynamic "approval_rule" {
    for_each = !each.value.use_approved_patches ? [1] : []

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

# Output the patch baseline IDs for reference
output "patch_baseline_ids" {
  description = "Map of OS types to their patch baseline IDs"
  value = {
    for k, v in aws_ssm_patch_baseline.os_baselines : k => v.id
  }
}

# Output the maintenance window IDs for reference
output "maintenance_window_ids" {
  description = "Map of OS types to their maintenance window IDs"
  value = {
    for k, v in aws_ssm_maintenance_window.os_maintenance_windows : k => v.id
  }
}

# Output the patch group names for reference
output "patch_group_names" {
  description = "Map of OS types to their patch group names"
  value = {
    for k, v in aws_ssm_patch_group.os_patch_groups : k => v.patch_group
  }
}
