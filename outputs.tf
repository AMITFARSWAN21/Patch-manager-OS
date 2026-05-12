# # Output instance information for verification
# output "managed_instances" {
#   description = "Information about managed instances"
#   value = {
#     for instance in local.valid_instances : instance.id => {
#       name         = instance.name
#       detected_os  = instance.detected_os
#       ami_name     = instance.ami_name
#       patch_group  = "${instance.detected_os}-Production-PatchGroup"
#       private_ip   = instance.private_ip
#       environment  = instance.environment
#       project      = instance.project
#     }
#   }
# }

# # Output instances that couldn't be classified
# output "unclassified_instances" {
#   description = "Instances that couldn't be classified by OS"
#   value = {
#     for instance in local.instance_info : instance.id => {
#       name        = instance.name
#       ami_name    = instance.ami_name
#       detected_os = instance.detected_os
#       environment = instance.environment
#     }
#     if instance.detected_os == "unknown" || !contains(keys(var.os_patch_configs), instance.detected_os)
#   }
# }

# # Output OS detection summary
# output "os_detection_summary" {
#   description = "Summary of OS detection results"
#   value = {
#     total_instances     = length(local.instance_info)
#     valid_instances     = length(local.valid_instances)
#     ubuntu_count       = length([for i in local.valid_instances : i if i.detected_os == "ubuntu"])
#     windows_count      = length([for i in local.valid_instances : i if i.detected_os == "windows"])
#     amazonlinux_count  = length([for i in local.valid_instances : i if i.detected_os == "amazonlinux"])
#     rhel_count         = length([for i in local.valid_instances : i if i.detected_os == "rhel"])
#     centos_count       = length([for i in local.valid_instances : i if i.detected_os == "centos"])
#     unknown_count      = length([for i in local.instance_info : i if i.detected_os == "unknown"])
#   }
# }

# # Output patch baseline information
# output "patch_baselines" {
#   description = "Created patch baselines"
#   value = {
#     for k, v in aws_ssm_patch_baseline.os_baselines : k => {
#       id   = v.id
#       name = v.name
#       os   = v.operating_system
#     }
#   }
# }

# # Output maintenance window information
# output "maintenance_windows" {
#   description = "Created maintenance windows"
#   value = {
#     for k, v in aws_ssm_maintenance_window.os_maintenance_windows : k => {
#       id       = v.id
#       name     = v.name
#       schedule = v.schedule
#     }
#   }
# }

# # Output patch groups
# output "patch_groups" {
#   description = "Created patch groups"
#   value = {
#     for k, v in aws_ssm_patch_group.os_patch_groups : k => {
#       baseline_id = v.baseline_id
#       patch_group = v.patch_group
#     }
#   }
# }

# # Output IAM role information
# output "iam_role" {
#   description = "IAM role for maintenance windows"
#   value = {
#     name = aws_iam_role.maintenance_window_role.name
#     arn  = aws_iam_role.maintenance_window_role.arn
#   }
# }
