# output "instance_id" {
#   description = "ID of the created test EC2 instance"
#   value       = aws_instance.test_instance.id
# }

# output "instance_public_ip" {
#   description = "Public IP address of test instance"
#   value       = aws_instance.test_instance.public_ip
# }

# output "instance_private_ip" {
#   description = "Private IP address of test instance"
#   value       = aws_instance.test_instance.private_ip
# }

# output "patch_baseline_id" {
#   description = "Test patch baseline ID"
#   value       = aws_ssm_patch_baseline.test_baseline.id
# }

# output "maintenance_window_id" {
#   description = "Test maintenance window ID"
#   value       = aws_ssm_maintenance_window.test_window.id
# }

# output "inspector_status" {
#   description = "Inspector enablement status"
#   value       = "EC2 scanning enabled for account ${data.aws_caller_identity.current.account_id}"
# }

# # output "s3_bucket_name" {
# #   description = "S3 bucket for patch logs"
# #   value       = aws_s3_bucket.patch_logs.bucket
# # }




output "existing_instances_found" {
  description = "Existing production instances found"
  value = {
    count     = length(data.aws_instances.production_instances.ids)
    instances = local.instance_info
  }
}

output "patch_baseline_id" {
  description = "Production patch baseline ID"
  value       = aws_ssm_patch_baseline.production_baseline.id
}

output "maintenance_window_id" {
  description = "Production maintenance window ID"
  value       = aws_ssm_maintenance_window.production_window.id
}

output "patch_group_name" {
  description = "Patch group name applied to instances"
  value       = var.patch_group_name
}

output "maintenance_schedule" {
  description = "When maintenance window runs (IST)"
  value       = "4th Saturday of each month at 2:00 AM IST"
}

output "scan_schedule" {
  description = "When patch scans run (IST)"
  value       = "Daily at 6:00 AM IST"
}

output "console_links" {
  description = "AWS Console links for monitoring"
  value = {
    systems_manager_fleet = "https://ap-south-1.console.aws.amazon.com/systems-manager/managed-instances"
    inspector_findings    = "https://ap-south-1.console.aws.amazon.com/inspector/v2/home#/findings"
    patch_manager        = "https://ap-south-1.console.aws.amazon.com/systems-manager/patch-manager/dashboard"
    maintenance_windows   = "https://ap-south-1.console.aws.amazon.com/systems-manager/maintenance-windows"
  }
}

output "next_steps" {
  description = "What happens next"
  value = <<-EOT
    ✅ Found ${length(data.aws_instances.production_instances.ids)} Production instances in ap-south-1
    ✅ Added PatchGroup tags to all instances
    ✅ Created production patch baseline (7-day delay for security patches)
    ✅ Maintenance window: 4th Saturday of each month at 2 AM IST
    ✅ Daily patch scans at 6 AM IST
    
    Manual commands for ap-south-1:
    - Check instances: aws ssm describe-instance-information --region ap-south-1
    - Run immediate scan: aws ssm send-command --document-name "AWS-RunPatchBaseline" --parameters "Operation=Scan" --targets "Key=tag:Environment,Values=Production" --region ap-south-1
    - Check compliance: aws ssm describe-instance-patch-states --region ap-south-1
  EOT
}
