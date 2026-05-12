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
      # Get SSM inventory data using AWS CLI
      $inventoryJson = aws ssm list-inventory-entries --instance-id $instanceId --type-name "AWS:InstanceInformation" --output json 2>$null
      
      if ($LASTEXITCODE -eq 0 -and $inventoryJson) {
        $inventory = $inventoryJson | ConvertFrom-Json
        
        if ($inventory.Entries -and $inventory.Entries.Count -gt 0) {
          $entry = $inventory.Entries[0]
          $result = @{
            platform_type = if ($entry.PlatformType) { $entry.PlatformType } else { "unknown" }
            platform_name = if ($entry.PlatformName) { $entry.PlatformName } else { "unknown" }
            platform_version = if ($entry.PlatformVersion) { $entry.PlatformVersion } else { "unknown" }
            computer_name = if ($entry.ComputerName) { $entry.ComputerName } else { "unknown" }
            agent_version = if ($entry.AgentVersion) { $entry.AgentVersion } else { "unknown" }
            ssm_managed = "true"
          }
        } else {
          $result = @{
            platform_type = "unknown"
            platform_name = "unknown"
            platform_version = "unknown"
            computer_name = "unknown"
            agent_version = "unknown"
            ssm_managed = "false"
          }
        }
      } else {
        $result = @{
          platform_type = "unknown"
          platform_name = "unknown"
          platform_version = "unknown"
          computer_name = "unknown"
          agent_version = "unknown"
          ssm_managed = "false"
        }
      }
    } catch {
      $result = @{
        platform_type = "unknown"
        platform_name = "unknown"
        platform_version = "unknown"
        computer_name = "unknown"
        agent_version = "unknown"
        ssm_managed = "false"
      }
    }
    
    # Output as JSON
    $result | ConvertTo-Json -Compress
  EOT
  ]
}

# Get AMI details for fallback OS detection
data "aws_ami" "instance_amis" {
  count  = length(data.aws_instances.production_instances.ids)
  owners = ["self", "amazon", "099720109477", "309956199498"] # self, amazon, canonical, redhat

  filter {
    name   = "image-id"
    values = [data.aws_instance.production_details[count.index].ami]
  }
}

# Local values to process instance information with SSM inventory-based OS detection
locals {
  instance_info = [
    for i, instance in data.aws_instance.production_details : {
      id         = instance.id
      name       = lookup(instance.tags, "Name", "Unnamed")
      private_ip = instance.private_ip
      public_ip  = instance.public_ip
      az         = instance.availability_zone
      ami_id     = instance.ami
      ami_name   = length(data.aws_ami.instance_amis) > i ? data.aws_ami.instance_amis[i].name : ""
      ami_owner  = length(data.aws_ami.instance_amis) > i ? data.aws_ami.instance_amis[i].owner_id : ""
      platform   = try(instance.platform, "")

      # SSM Inventory data from external data source
      ssm_managed          = data.external.ssm_inventory[i].result.ssm_managed == "true"
      ssm_platform_type    = data.external.ssm_inventory[i].result.platform_type
      ssm_platform_name    = data.external.ssm_inventory[i].result.platform_name
      ssm_platform_version = data.external.ssm_inventory[i].result.platform_version
      ssm_computer_name    = data.external.ssm_inventory[i].result.computer_name
      ssm_agent_version    = data.external.ssm_inventory[i].result.agent_version

      # Enhanced OS Detection Logic with SSM Inventory priority
      detected_os = (
        # Priority 1: Check existing OS tag first (manual override)
        lookup(instance.tags, "OS", "") != "" ? lower(lookup(instance.tags, "OS", "")) :

        # Priority 2: Use SSM Inventory data (most reliable for SSM managed instances)
        data.external.ssm_inventory[i].result.ssm_managed == "true" ? (
          # Windows detection from SSM
          lower(data.external.ssm_inventory[i].result.platform_type) == "windows" ? "windows" :

          # Linux variants detection from SSM platform name
          lower(data.external.ssm_inventory[i].result.platform_type) == "linux" ? (
            can(regex("(?i)(amazon.*linux|amzn)", data.external.ssm_inventory[i].result.platform_name)) ? "amazonlinux" :
            can(regex("(?i)(ubuntu)", data.external.ssm_inventory[i].result.platform_name)) ? "ubuntu" :
            can(regex("(?i)(red.*hat|rhel)", data.external.ssm_inventory[i].result.platform_name)) ? "rhel" :
            can(regex("(?i)(centos)", data.external.ssm_inventory[i].result.platform_name)) ? "centos" :
            can(regex("(?i)(debian)", data.external.ssm_inventory[i].result.platform_name)) ? "debian" :
            can(regex("(?i)(suse|sles)", data.external.ssm_inventory[i].result.platform_name)) ? "suse" :
            can(regex("(?i)(oracle)", data.external.ssm_inventory[i].result.platform_name)) ? "oracle" :
            can(regex("(?i)(rocky)", data.external.ssm_inventory[i].result.platform_name)) ? "rocky" :
            can(regex("(?i)(alma)", data.external.ssm_inventory[i].result.platform_name)) ? "alma" :
            "linux"
          ) :

          # macOS detection from SSM
          lower(data.external.ssm_inventory[i].result.platform_type) == "macos" ? "macos" :
          "unknown"
        ) :

        # Priority 3: Fallback to instance platform field
        try(instance.platform, "") == "windows" ? "windows" :

        # Priority 4: AMI owner-based detection
        length(data.aws_ami.instance_amis) > i ? (
          data.aws_ami.instance_amis[i].owner_id == "137112412989" ? "amazonlinux" :
          data.aws_ami.instance_amis[i].owner_id == "099720109477" ? "ubuntu" :
          data.aws_ami.instance_amis[i].owner_id == "309956199498" ? "rhel" :
          data.aws_ami.instance_amis[i].owner_id == "801119661308" ? "windows" :
          data.aws_ami.instance_amis[i].owner_id == "136693071363" ? "debian" :
          data.aws_ami.instance_amis[i].owner_id == "013907871322" ? "suse" :
          data.aws_ami.instance_amis[i].owner_id == "125523088429" ? "centos" :
          data.aws_ami.instance_amis[i].owner_id == "131827586825" ? "oracle" :

          # Priority 5: AMI name pattern matching
          can(regex("(?i)(amzn2023|al2023)", data.aws_ami.instance_amis[i].name)) ? "amazonlinux" :
          can(regex("(?i)(amzn2|amazon-linux-2)", data.aws_ami.instance_amis[i].name)) ? "amazonlinux" :
          can(regex("(?i)(amzn|amazon-linux)", data.aws_ami.instance_amis[i].name)) ? "amazonlinux" :
          can(regex("(?i)(ubuntu)", data.aws_ami.instance_amis[i].name)) ? "ubuntu" :
          can(regex("(?i)(windows|win)", data.aws_ami.instance_amis[i].name)) ? "windows" :
          can(regex("(?i)(rhel|red.*hat)", data.aws_ami.instance_amis[i].name)) ? "rhel" :
          can(regex("(?i)(centos)", data.aws_ami.instance_amis[i].name)) ? "centos" :
          can(regex("(?i)(debian)", data.aws_ami.instance_amis[i].name)) ? "debian" :
          can(regex("(?i)(suse|sles)", data.aws_ami.instance_amis[i].name)) ? "suse" :
          can(regex("(?i)(oracle)", data.aws_ami.instance_amis[i].name)) ? "oracle" :
          "unknown"
        ) : "unknown"
      )

      # Confidence level based on detection method
      detection_confidence = (
        lookup(instance.tags, "OS", "") != "" ? "manual" :
        data.external.ssm_inventory[i].result.ssm_managed == "true" ? "high" :
        try(instance.platform, "") == "windows" ? "medium" :
        length(data.aws_ami.instance_amis) > i && contains([
          "137112412989", "099720109477", "309956199498", "801119661308",
          "136693071363", "013907871322", "125523088429", "131827586825"
        ], data.aws_ami.instance_amis[i].owner_id) ? "medium" :
        "low"
      )

      environment = lookup(instance.tags, "Environment", "unknown")
      project     = lookup(instance.tags, "Project", "unknown")
      owner       = lookup(instance.tags, "Owner", "unknown")
    }
  ]

  # Filter instances with valid OS detection and supported OS types
  valid_instances = [
    for instance in local.instance_info : instance
    if instance.detected_os != "unknown" &&
    contains(keys(var.os_patch_configs), instance.detected_os) &&
    instance.detection_confidence != "low"
  ]

  # Instances that need manual review
  review_instances = [
    for instance in local.instance_info : instance
    if instance.detected_os == "unknown" ||
    !contains(keys(var.os_patch_configs), instance.detected_os) ||
    instance.detection_confidence == "low"
  ]
}

# Add PatchGroup tag to instances based on detected OS
resource "aws_ec2_tag" "patch_group_tag" {
  count       = length(local.valid_instances)
  resource_id = local.valid_instances[count.index].id
  key         = "PatchGroup"
  value       = "${local.valid_instances[count.index].detected_os}-Production-PatchGroup"
}

# Add AutoPatch tag to enable automatic patching
resource "aws_ec2_tag" "auto_patch_tag" {
  count       = length(local.valid_instances)
  resource_id = local.valid_instances[count.index].id
  key         = "AutoPatch"
  value       = "true"
}

# Add detected OS tag for future reference
resource "aws_ec2_tag" "os_tag" {
  count       = length(local.valid_instances)
  resource_id = local.valid_instances[count.index].id
  key         = "OS"
  value       = local.valid_instances[count.index].detected_os
}

# Add detection confidence tag for monitoring
resource "aws_ec2_tag" "detection_confidence_tag" {
  count       = length(local.valid_instances)
  resource_id = local.valid_instances[count.index].id
  key         = "OSDetectionConfidence"
  value       = local.valid_instances[count.index].detection_confidence
}

# Add SSM platform information tags for reference (only for SSM managed instances)
resource "aws_ec2_tag" "ssm_platform_type_tag" {
  count       = length([for instance in local.valid_instances : instance if instance.ssm_managed])
  resource_id = [for instance in local.valid_instances : instance if instance.ssm_managed][count.index].id
  key         = "SSMPlatformType"
  value       = [for instance in local.valid_instances : instance if instance.ssm_managed][count.index].ssm_platform_type
}

resource "aws_ec2_tag" "ssm_platform_name_tag" {
  count       = length([for instance in local.valid_instances : instance if instance.ssm_managed])
  resource_id = [for instance in local.valid_instances : instance if instance.ssm_managed][count.index].id
  key         = "SSMPlatformName"
  value       = [for instance in local.valid_instances : instance if instance.ssm_managed][count.index].ssm_platform_name
}

resource "aws_ec2_tag" "ssm_platform_version_tag" {
  count       = length([for instance in local.valid_instances : instance if instance.ssm_managed])
  resource_id = [for instance in local.valid_instances : instance if instance.ssm_managed][count.index].id
  key         = "SSMPlatformVersion"
  value       = [for instance in local.valid_instances : instance if instance.ssm_managed][count.index].ssm_platform_version
}

# Output instances that need manual review
output "instances_needing_review" {
  description = "Instances that could not be reliably detected or are not supported"
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
      ami_name             = instance.ami_name
      ami_owner            = instance.ami_owner
      reason = (
        !instance.ssm_managed ? "Instance not managed by SSM - no inventory data available" :
        instance.detected_os == "unknown" ? "OS could not be detected from SSM inventory data" :
        !contains(keys(var.os_patch_configs), instance.detected_os) ? "OS not supported in patch configs" :
        "Low detection confidence"
      )
    }
  ]
}

# Output summary statistics
output "os_detection_summary" {
  description = "Summary of OS detection results"
  value = {
    total_instances = length(local.instance_info)
    valid_instances = length(local.valid_instances)
    review_needed   = length(local.review_instances)

    by_os = {
      for os in distinct([for i in local.valid_instances : i.detected_os]) :
      os => length([for i in local.valid_instances : i if i.detected_os == os])
    }

    by_confidence = {
      for conf in distinct([for i in local.instance_info : i.detection_confidence]) :
      conf => length([for i in local.instance_info : i if i.detection_confidence == conf])
    }

    ssm_managed_count      = length([for i in local.instance_info : i if i.ssm_managed])
    ssm_managed_percentage = length(local.instance_info) > 0 ? (length([for i in local.instance_info : i if i.ssm_managed]) * 100 / length(local.instance_info)) : 0
  }
}

# Output detailed SSM inventory information for debugging
output "ssm_inventory_details" {
  description = "Detailed SSM inventory information for all instances"
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

# Output instances by OS type with SSM details
output "instances_by_os" {
  description = "Instances grouped by detected OS type with SSM inventory details"
  value = {
    for os_type in distinct([for i in local.valid_instances : i.detected_os]) :
    os_type => [
      for instance in local.valid_instances : {
        id                   = instance.id
        name                 = instance.name
        ssm_platform_name    = instance.ssm_platform_name
        ssm_platform_version = instance.ssm_platform_version
        detection_confidence = instance.detection_confidence
      }
      if instance.detected_os == os_type
    ]
  }
}

# Output patch group assignments with SSM details
output "patch_group_assignments" {
  description = "Patch group assignments for valid instances with SSM inventory details"
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
