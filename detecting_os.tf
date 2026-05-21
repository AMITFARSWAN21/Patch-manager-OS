# Data source to find existing EC2 instances
data "aws_instances" "production_instances" {
  filter {
    name   = "tag:Environment"
    values = var.environment_patterns
  }

  filter {
    name   = "instance-state-name"
    values = ["running"]
  }
}

# Get detailed information for each instance
data "aws_instance" "production_details" {
  for_each    = toset(data.aws_instances.production_instances.ids)
  instance_id = each.value
}

# Use external data source to get SSM inventory information via AWS CLI
data "external" "ssm_inventory" {
  for_each = toset(data.aws_instances.production_instances.ids)

  program = ["powershell", "-Command", <<-EOT
    $instanceId = "${each.value}"
    
    try {
      $inventoryJson = aws ssm list-inventory-entries --instance-id $instanceId --type-name "AWS:InstanceInformation" --output json 2>$null
      
      if ($LASTEXITCODE -eq 0 -and $inventoryJson) {
        $inventory = $inventoryJson | ConvertFrom-Json
        
        if ($inventory.Entries -and $inventory.Entries.Count -gt 0) {
          $entry = $inventory.Entries[0]
          $result = @{
            platform_type    = if ($entry.PlatformType)    { $entry.PlatformType }    else { "unknown" }
            platform_name    = if ($entry.PlatformName)    { $entry.PlatformName }    else { "unknown" }
            platform_version = if ($entry.PlatformVersion) { $entry.PlatformVersion } else { "unknown" }
            computer_name    = if ($entry.ComputerName)    { $entry.ComputerName }    else { "unknown" }
            agent_version    = if ($entry.AgentVersion)    { $entry.AgentVersion }    else { "unknown" }
            ssm_managed      = "true"
          }
        } else {
          $result = @{
            platform_type    = "unknown"
            platform_name    = "unknown"
            platform_version = "unknown"
            computer_name    = "unknown"
            agent_version    = "unknown"
            ssm_managed      = "false"
          }
        }
      } else {
        $result = @{
          platform_type    = "unknown"
          platform_name    = "unknown"
          platform_version = "unknown"
          computer_name    = "unknown"
          agent_version    = "unknown"
          ssm_managed      = "false"
        }
      }
    } catch {
      $result = @{
        platform_type    = "unknown"
        platform_name    = "unknown"
        platform_version = "unknown"
        computer_name    = "unknown"
        agent_version    = "unknown"
        ssm_managed      = "false"
      }
    }
    
    $result | ConvertTo-Json -Compress
  EOT
  ]
}

locals {
  instance_info = {
    for id in data.aws_instances.production_instances.ids :
    id => {
      id             = id
      name           = lookup(data.aws_instance.production_details[id].tags, "Name", "Unnamed")
      private_ip     = data.aws_instance.production_details[id].private_ip
      public_ip      = data.aws_instance.production_details[id].public_ip
      az             = data.aws_instance.production_details[id].availability_zone
      ami_id         = data.aws_instance.production_details[id].ami

      ssm_managed          = data.external.ssm_inventory[id].result.ssm_managed == "true"
      ssm_platform_type    = data.external.ssm_inventory[id].result.platform_type
      ssm_platform_name    = data.external.ssm_inventory[id].result.platform_name
      ssm_platform_version = data.external.ssm_inventory[id].result.platform_version
      ssm_computer_name    = data.external.ssm_inventory[id].result.computer_name
      ssm_agent_version    = data.external.ssm_inventory[id].result.agent_version

      detected_os = (
        lookup(data.aws_instance.production_details[id].tags, "OS", "") != "" ? lower(lookup(data.aws_instance.production_details[id].tags, "OS", "")) :

        data.external.ssm_inventory[id].result.ssm_managed == "true" ? (
          lower(data.external.ssm_inventory[id].result.platform_type) == "windows" ? "windows" :

          lower(data.external.ssm_inventory[id].result.platform_type) == "linux" ? (
            can(regex("(?i)(amazon.*linux|amzn)", data.external.ssm_inventory[id].result.platform_name)) ? "amazonlinux" :
            can(regex("(?i)(ubuntu)",             data.external.ssm_inventory[id].result.platform_name)) ? "ubuntu"      :
            can(regex("(?i)(red.*hat|rhel)",      data.external.ssm_inventory[id].result.platform_name)) ? "rhel"        :
            can(regex("(?i)(centos)",             data.external.ssm_inventory[id].result.platform_name)) ? "centos"      :
            can(regex("(?i)(debian)",             data.external.ssm_inventory[id].result.platform_name)) ? "debian"      :
            can(regex("(?i)(suse|sles)",          data.external.ssm_inventory[id].result.platform_name)) ? "suse"        :
            can(regex("(?i)(oracle)",             data.external.ssm_inventory[id].result.platform_name)) ? "oracle"      :
            can(regex("(?i)(rocky)",              data.external.ssm_inventory[id].result.platform_name)) ? "rocky"       :
            can(regex("(?i)(alma)",               data.external.ssm_inventory[id].result.platform_name)) ? "alma"        :
            "linux"
          ) :

          lower(data.external.ssm_inventory[id].result.platform_type) == "macos" ? "macos" :
          "unknown"
        ) :
        "unknown"
      )

      detection_confidence = (
        lookup(data.aws_instance.production_details[id].tags, "OS", "") != ""        ? "manual"       :
        data.external.ssm_inventory[id].result.ssm_managed == "true"                 ? "high"         :
        "undetectable"
      )

      environment = lookup(data.aws_instance.production_details[id].tags, "Environment", "unknown")
      project     = lookup(data.aws_instance.production_details[id].tags, "Project", "unknown")
      owner       = lookup(data.aws_instance.production_details[id].tags, "Owner", "unknown")
    }
  }

  # Only valid instances — known OS + in os_patch_configs + SSM managed
  valid_instances = {
    for id, instance in local.instance_info :
    id => instance
    if instance.detected_os != "unknown" &&
       contains(keys(var.os_patch_configs), instance.detected_os) &&
       instance.detection_confidence != "undetectable"
  }

  # Instances needing review
  review_instances = {
    for id, instance in local.instance_info :
    id => instance
    if instance.detected_os == "unknown" ||
       !contains(keys(var.os_patch_configs), instance.detected_os) ||
       instance.detection_confidence == "undetectable"
  }
}

# Tag: PatchGroup
resource "aws_ec2_tag" "patch_group_tag" {
  for_each    = local.valid_instances
  resource_id = each.value.id
  key         = "PatchGroup"
  value       = "${each.value.detected_os}-Production-PatchGroup"
}

# Tag: AutoPatch
resource "aws_ec2_tag" "auto_patch_tag" {
  for_each    = local.valid_instances
  resource_id = each.value.id
  key         = "AutoPatch"
  value       = "true"
}

# Tag: OS
resource "aws_ec2_tag" "os_tag" {
  for_each    = local.valid_instances
  resource_id = each.value.id
  key         = "OS"
  value       = each.value.detected_os
}

# Tag: OSDetectionConfidence
resource "aws_ec2_tag" "detection_confidence_tag" {
  for_each    = local.valid_instances
  resource_id = each.value.id
  key         = "OSDetectionConfidence"
  value       = each.value.detection_confidence
}

# Tags: SSM platform details
resource "aws_ec2_tag" "ssm_platform_type_tag" {
  for_each    = { for id, i in local.valid_instances : id => i if i.ssm_managed }
  resource_id = each.value.id
  key         = "SSMPlatformType"
  value       = each.value.ssm_platform_type
}

resource "aws_ec2_tag" "ssm_platform_name_tag" {
  for_each    = { for id, i in local.valid_instances : id => i if i.ssm_managed }
  resource_id = each.value.id
  key         = "SSMPlatformName"
  value       = each.value.ssm_platform_name
}

resource "aws_ec2_tag" "ssm_platform_version_tag" {
  for_each    = { for id, i in local.valid_instances : id => i if i.ssm_managed }
  resource_id = each.value.id
  key         = "SSMPlatformVersion"
  value       = each.value.ssm_platform_version
}

# Outputs
output "instances_needing_review" {
  description = "Instances skipped due to missing SSM management or unsupported OS"
  value = [
    for id, instance in local.review_instances : {
      id                   = instance.id
      name                 = instance.name
      detected_os          = instance.detected_os
      detection_confidence = instance.detection_confidence
      ssm_managed          = instance.ssm_managed
      ssm_platform_type    = instance.ssm_platform_type
      ssm_platform_name    = instance.ssm_platform_name
      ssm_platform_version = instance.ssm_platform_version
      reason = (
        !instance.ssm_managed                                           ? "Instance not managed by SSM — install and register the SSM agent" :
        instance.detected_os == "unknown"                               ? "OS could not be identified from SSM inventory data"               :
        !contains(keys(var.os_patch_configs), instance.detected_os)     ? "OS type '${instance.detected_os}' is not in var.os_patch_configs"  :
        "Undetectable — no SSM inventory and no manual OS tag"
      )
    }
  ]
}

output "os_detection_summary" {
  description = "Summary of SSM-only OS detection results"
  value = {
    total_instances        = length(local.instance_info)
    valid_instances        = length(local.valid_instances)
    review_needed          = length(local.review_instances)
    ssm_managed_count      = length([for id, i in local.instance_info : i if i.ssm_managed])
    ssm_managed_percentage = length(local.instance_info) > 0 ? (length([for id, i in local.instance_info : i if i.ssm_managed]) * 100 / length(local.instance_info)) : 0

    by_os = {
      for os in distinct([for id, i in local.valid_instances : i.detected_os]) :
      os => length([for id, i in local.valid_instances : i if i.detected_os == os])
    }

    by_confidence = {
      for conf in distinct([for id, i in local.instance_info : i.detection_confidence]) :
      conf => length([for id, i in local.instance_info : i if i.detection_confidence == conf])
    }
  }
}

output "ssm_inventory_details" {
  description = "SSM inventory details for all instances"
  value = {
    for id, instance in local.instance_info : id => {
      name                 = instance.name
      ssm_managed          = instance.ssm_managed
      ssm_platform_type    = instance.ssm_platform_type
      ssm_platform_name    = instance.ssm_platform_name
      ssm_platform_version = instance.ssm_platform_version
      ssm_computer_name    = instance.ssm_computer_name
      ssm_agent_version    = instance.ssm_agent_version
      detected_os          = instance.detected_os
      detection_confidence = instance.detection_confidence
    }
  }
}

output "patch_group_assignments" {
  description = "Final patch group assignments"
  value = {
    for id, instance in local.valid_instances : id => {
      name                 = instance.name
      os                   = instance.detected_os
      patch_group          = "${instance.detected_os}-Production-PatchGroup"
      confidence           = instance.detection_confidence
      ssm_managed          = instance.ssm_managed
      ssm_platform_name    = instance.ssm_platform_name
      ssm_platform_version = instance.ssm_platform_version
    }
  }
}