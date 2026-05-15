# Data source to find existing EC2 instances with flexible environment matching
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
  count       = length(data.aws_instances.production_instances.ids)
  instance_id = data.aws_instances.production_instances.ids[count.index]
}

# Use external data source to get SSM inventory information via AWS CLI
data "external" "ssm_inventory" {
  count = length(data.aws_instances.production_instances.ids)

  program = ["powershell", "-Command", <<-EOT
    $instanceId = "${data.aws_instances.production_instances.ids[count.index]}"
    
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
  instance_info = [
    for i, instance in data.aws_instance.production_details : {
      id             = instance.id
      name           = lookup(instance.tags, "Name", "Unnamed")
      private_ip     = instance.private_ip
      public_ip      = instance.public_ip
      az             = instance.availability_zone
      ami_id         = instance.ami

      ssm_managed          = data.external.ssm_inventory[i].result.ssm_managed == "true"
      ssm_platform_type    = data.external.ssm_inventory[i].result.platform_type
      ssm_platform_name    = data.external.ssm_inventory[i].result.platform_name
      ssm_platform_version = data.external.ssm_inventory[i].result.platform_version
      ssm_computer_name    = data.external.ssm_inventory[i].result.computer_name
      ssm_agent_version    = data.external.ssm_inventory[i].result.agent_version

      # OS Detection: SSM inventory only
      # Priority 1: Manual OS tag override
      # Priority 2: SSM inventory data
      # No fallbacks — if not SSM managed, instance goes to review
      detected_os = (
        lookup(instance.tags, "OS", "") != "" ? lower(lookup(instance.tags, "OS", "")) :

        data.external.ssm_inventory[i].result.ssm_managed == "true" ? (
          lower(data.external.ssm_inventory[i].result.platform_type) == "windows" ? "windows" :

          lower(data.external.ssm_inventory[i].result.platform_type) == "linux" ? (
            can(regex("(?i)(amazon.*linux|amzn)", data.external.ssm_inventory[i].result.platform_name)) ? "amazonlinux" :
            can(regex("(?i)(ubuntu)",             data.external.ssm_inventory[i].result.platform_name)) ? "ubuntu"      :
            can(regex("(?i)(red.*hat|rhel)",      data.external.ssm_inventory[i].result.platform_name)) ? "rhel"        :
            can(regex("(?i)(centos)",             data.external.ssm_inventory[i].result.platform_name)) ? "centos"      :
            can(regex("(?i)(debian)",             data.external.ssm_inventory[i].result.platform_name)) ? "debian"      :
            can(regex("(?i)(suse|sles)",          data.external.ssm_inventory[i].result.platform_name)) ? "suse"        :
            can(regex("(?i)(oracle)",             data.external.ssm_inventory[i].result.platform_name)) ? "oracle"      :
            can(regex("(?i)(rocky)",              data.external.ssm_inventory[i].result.platform_name)) ? "rocky"       :
            can(regex("(?i)(alma)",               data.external.ssm_inventory[i].result.platform_name)) ? "alma"        :
            "linux"
          ) :

          lower(data.external.ssm_inventory[i].result.platform_type) == "macos" ? "macos" :
          "unknown"
        ) :

        # Not SSM managed and no manual tag → unknown, goes to review
        "unknown"
      )

      # Confidence: only two levels now — manual or high (SSM) or unknown (not managed)
      detection_confidence = (
        lookup(instance.tags, "OS", "") != ""                        ? "manual"  :
        data.external.ssm_inventory[i].result.ssm_managed == "true" ? "high"    :
        "undetectable"
      )

      environment = lookup(instance.tags, "Environment", "unknown")
      project     = lookup(instance.tags, "Project", "unknown")
      owner       = lookup(instance.tags, "Owner", "unknown")
    }
  ]

  # Only instances with SSM-based or manual OS detection
  valid_instances = [
    for instance in local.instance_info : instance
    if instance.detected_os != "unknown" &&
       contains(keys(var.os_patch_configs), instance.detected_os) &&
       instance.detection_confidence != "undetectable"
  ]

  # Instances not SSM-managed or with unresolvable OS
  review_instances = [
    for instance in local.instance_info : instance
    if instance.detected_os == "unknown" ||
       !contains(keys(var.os_patch_configs), instance.detected_os) ||
       instance.detection_confidence == "undetectable"
  ]
}

# Tag: PatchGroup
resource "aws_ec2_tag" "patch_group_tag" {
  count       = length(local.valid_instances)
  resource_id = local.valid_instances[count.index].id
  key         = "PatchGroup"
  value       = "${local.valid_instances[count.index].detected_os}-Production-PatchGroup"
}

# Tag: AutoPatch
resource "aws_ec2_tag" "auto_patch_tag" {
  count       = length(local.valid_instances)
  resource_id = local.valid_instances[count.index].id
  key         = "AutoPatch"
  value       = "true"
}

# Tag: OS
resource "aws_ec2_tag" "os_tag" {
  count       = length(local.valid_instances)
  resource_id = local.valid_instances[count.index].id
  key         = "OS"
  value       = local.valid_instances[count.index].detected_os
}

# Tag: OSDetectionConfidence
resource "aws_ec2_tag" "detection_confidence_tag" {
  count       = length(local.valid_instances)
  resource_id = local.valid_instances[count.index].id
  key         = "OSDetectionConfidence"
  value       = local.valid_instances[count.index].detection_confidence
}

# Tags: SSM platform details (all valid instances are SSM-managed or manually tagged)
resource "aws_ec2_tag" "ssm_platform_type_tag" {
  count       = length([for i in local.valid_instances : i if i.ssm_managed])
  resource_id = [for i in local.valid_instances : i if i.ssm_managed][count.index].id
  key         = "SSMPlatformType"
  value       = [for i in local.valid_instances : i if i.ssm_managed][count.index].ssm_platform_type
}

resource "aws_ec2_tag" "ssm_platform_name_tag" {
  count       = length([for i in local.valid_instances : i if i.ssm_managed])
  resource_id = [for i in local.valid_instances : i if i.ssm_managed][count.index].id
  key         = "SSMPlatformName"
  value       = [for i in local.valid_instances : i if i.ssm_managed][count.index].ssm_platform_name
}

resource "aws_ec2_tag" "ssm_platform_version_tag" {
  count       = length([for i in local.valid_instances : i if i.ssm_managed])
  resource_id = [for i in local.valid_instances : i if i.ssm_managed][count.index].id
  key         = "SSMPlatformVersion"
  value       = [for i in local.valid_instances : i if i.ssm_managed][count.index].ssm_platform_version
}

# Outputs
output "instances_needing_review" {
  description = "Instances skipped due to missing SSM management or unsupported OS"
  value = [
    for instance in local.review_instances : {
      id                   = instance.id
      name                 = instance.name
      detected_os          = instance.detected_os
      detection_confidence = instance.detection_confidence
      ssm_managed          = instance.ssm_managed
      ssm_platform_type    = instance.ssm_platform_type
      ssm_platform_name    = instance.ssm_platform_name
      ssm_platform_version = instance.ssm_platform_version
      reason = (
        !instance.ssm_managed                                              ? "Instance not managed by SSM — install and register the SSM agent" :
        instance.detected_os == "unknown"                                  ? "OS could not be identified from SSM inventory data"               :
        !contains(keys(var.os_patch_configs), instance.detected_os)        ? "OS type '${instance.detected_os}' is not in var.os_patch_configs"  :
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
    ssm_managed_count      = length([for i in local.instance_info : i if i.ssm_managed])
    ssm_managed_percentage = length(local.instance_info) > 0 ? (length([for i in local.instance_info : i if i.ssm_managed]) * 100 / length(local.instance_info)) : 0

    by_os = {
      for os in distinct([for i in local.valid_instances : i.detected_os]) :
      os => length([for i in local.valid_instances : i if i.detected_os == os])
    }

    by_confidence = {
      for conf in distinct([for i in local.instance_info : i.detection_confidence]) :
      conf => length([for i in local.instance_info : i if i.detection_confidence == conf])
    }
  }
}

output "ssm_inventory_details" {
  description = "SSM inventory details for all instances"
  value = {
    for instance in local.instance_info : instance.id => {
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
    for instance in local.valid_instances : instance.id => {
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