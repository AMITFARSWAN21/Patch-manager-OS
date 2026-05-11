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

# Get AMI details for OS detection
data "aws_ami" "instance_amis" {
  count  = length(data.aws_instances.production_instances.ids)
  owners = ["self", "amazon", "099720109477", "309956199498"] # self, amazon, canonical, redhat

  filter {
    name   = "image-id"
    values = [data.aws_instance.production_details[count.index].ami]
  }
}

# Local values to process instance information with OS detection
locals {
  instance_info = [
    for i, instance in data.aws_instance.production_details : {
      id          = instance.id
      name        = lookup(instance.tags, "Name", "Unnamed")
      private_ip  = instance.private_ip
      public_ip   = instance.public_ip
      az          = instance.availability_zone
      ami_id      = instance.ami
      ami_name    = length(data.aws_ami.instance_amis) > i ? data.aws_ami.instance_amis[i].name : ""
      platform    = try(instance.platform, "")
      
      # Multi-step OS Detection Logic
      detected_os = (
        # Step 1: Check existing OS tag first
        lookup(instance.tags, "OS", "") != "" ? lower(lookup(instance.tags, "OS", "")) :
        
        # Step 2: Check platform field (only set for Windows instances)
        try(instance.platform, "") == "windows" ? "windows" :
        
        # Step 3: Check AMI name patterns
        length(data.aws_ami.instance_amis) > i ? (
          # Ubuntu detection
          can(regex("(?i)(ubuntu)", data.aws_ami.instance_amis[i].name)) ? "ubuntu" :
          can(regex("(?i)(canonical)", data.aws_ami.instance_amis[i].name)) ? "ubuntu" :
          
          # Windows detection
          can(regex("(?i)(windows)", data.aws_ami.instance_amis[i].name)) ? "windows" :
          can(regex("(?i)(microsoft)", data.aws_ami.instance_amis[i].name)) ? "windows" :
          can(regex("(?i)(win)", data.aws_ami.instance_amis[i].name)) ? "windows" :
          
          # Amazon Linux detection
          can(regex("(?i)(amzn)", data.aws_ami.instance_amis[i].name)) ? "amazonlinux" :
          can(regex("(?i)(amazon-linux)", data.aws_ami.instance_amis[i].name)) ? "amazonlinux" :
          can(regex("(?i)(al2023)", data.aws_ami.instance_amis[i].name)) ? "amazonlinux" :
          
          # RHEL detection
          can(regex("(?i)(rhel)", data.aws_ami.instance_amis[i].name)) ? "rhel" :
          can(regex("(?i)(red.?hat)", data.aws_ami.instance_amis[i].name)) ? "rhel" :
          
          # CentOS detection
          can(regex("(?i)(centos)", data.aws_ami.instance_amis[i].name)) ? "centos" :
          
          # Step 4: Check instance name patterns as fallback
          can(regex("(?i)(ubuntu|web|app|nginx)", lookup(instance.tags, "Name", ""))) ? "ubuntu" :
          can(regex("(?i)(win|windows|iis|sql|ad)", lookup(instance.tags, "Name", ""))) ? "windows" :
          can(regex("(?i)(amzn|amazon|linux|nat|bastion)", lookup(instance.tags, "Name", ""))) ? "amazonlinux" :
          can(regex("(?i)(rhel|red-hat)", lookup(instance.tags, "Name", ""))) ? "rhel" :
          can(regex("(?i)(centos|cent)", lookup(instance.tags, "Name", ""))) ? "centos" :
          
          # Default to unknown if no patterns match
          "unknown"
        ) : "unknown"
      )
      
      environment = lookup(instance.tags, "Environment", "unknown")
      project     = lookup(instance.tags, "Project", "unknown")
      owner       = lookup(instance.tags, "Owner", "unknown")
    }
  ]

  # Filter instances with valid OS detection and supported OS types
  valid_instances = [
    for instance in local.instance_info : instance
    if instance.detected_os != "unknown" && contains(keys(var.os_patch_configs), instance.detected_os)
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
