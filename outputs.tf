# output "patch_management_summary" {
#   description = "Complete patch management setup summary"

#   value = {
#     for os_key, config in var.os_patch_configs : os_key => {

#       baseline_id   = aws_ssm_patch_baseline.os_baselines[os_key].id

#       baseline_name = aws_ssm_patch_baseline.os_baselines[os_key].name

#       patch_group = "${os_key}-Production-PatchGroup"

#       maintenance_window =aws_ssm_maintenance_window.os_maintenance_windows[os_key].id

#       schedule         = config.schedule
#       scan_schedule    = config.scan_schedule
#       operating_system = config.operating_system
#     }
#   }
# }

# output "instances_by_os" {
#   description = "Instances grouped by OS"

#   value = {

#     total_instances = length(local.instance_info)

#     instances_detail = local.instance_info

#     by_os = {

#       ubuntu_instances = [
#         for instance in local.instance_info : instance
#         if instance.os == "ubuntu"
#       ]

#       amazonlinux_instances = [
#         for instance in local.instance_info : instance
#         if instance.os == "amazonlinux"
#       ]

#       windows_instances = [
#         for instance in local.instance_info : instance
#         if instance.os == "windows"
#       ]
#     }
#   }
# }

# output "verification_commands" {
#   description = "Commands to verify patch management"

#   value = <<-EOT

# # Ubuntu patch scan
# aws ssm send-command --document-name "AWS-RunPatchBaseline" --parameters "Operation=Scan" --targets "Key=tag:OS,Values=ubuntu" --region ${var.aws_region}

# # Ubuntu patch install
# aws ssm send-command --document-name "AWS-RunPatchBaseline" --parameters "Operation=Install" --targets "Key=tag:OS,Values=ubuntu" --region ${var.aws_region}

# # Amazon Linux patch scan
# aws ssm send-command --document-name "AWS-RunPatchBaseline" --parameters "Operation=Scan" --targets "Key=tag:OS,Values=amazonlinux" --region ${var.aws_region}

# # Amazon Linux patch install
# aws ssm send-command --document-name "AWS-RunPatchBaseline" --parameters "Operation=Install" --targets "Key=tag:OS,Values=amazonlinux" --region ${var.aws_region}

# # Windows patch scan
# aws ssm send-command --document-name "AWS-RunPatchBaseline" --parameters "Operation=Scan" --targets "Key=tag:OS,Values=windows" --region ${var.aws_region}

# # Windows patch install
# aws ssm send-command --document-name "AWS-RunPatchBaseline" --parameters "Operation=Install" --targets "Key=tag:OS,Values=windows" --region ${var.aws_region}

# # Check compliance
# aws ssm describe-instance-patch-states --region ${var.aws_region}

# EOT
# }

# output "console_links" {
#   description = "AWS Console links"

#   value = {

#     patch_manager =
#     "https://${var.aws_region}.console.aws.amazon.com/systems-manager/patch-manager/dashboard"

#     fleet_manager =
#     "https://${var.aws_region}.console.aws.amazon.com/systems-manager/managed-instances"

#     maintenance_windows =
#     "https://${var.aws_region}.console.aws.amazon.com/systems-manager/maintenance-windows"

#     inspector_findings =
#     "https://${var.aws_region}.console.aws.amazon.com/inspector/v2/home#/findings"
#   }
# }