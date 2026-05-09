# Data source to find existing EC2 instances with Production environment tag
data "aws_instances" "production_instances" {
  filter {
    name   = "tag:Environment"
    values = [var.target_environment]
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

# Local values to process instance information
locals {
  instance_info = [
    for instance in data.aws_instance.production_details : {
      id          = instance.id
      name        = lookup(instance.tags, "Name", "Unnamed")
      private_ip  = instance.private_ip
      public_ip   = instance.public_ip
      az          = instance.availability_zone
      os          = lookup(instance.tags, "OS", "unknown")
      patch_group = "${lookup(instance.tags, "OS", "unknown")}-Production-PatchGroup"
    }
  ]
}

# Add PatchGroup tag to instances based on their OS tag
resource "aws_ec2_tag" "patch_group_tag" {
  count       = length(data.aws_instances.production_instances.ids)
  resource_id = data.aws_instances.production_instances.ids[count.index]
  key         = "PatchGroup"
  value = "${lookup(
    data.aws_instance.production_details[count.index].tags,
    "OS",
    "unknown"
  )}-Production-PatchGroup"
}

# Add AutoPatch tag to enable automatic patching
resource "aws_ec2_tag" "auto_patch_tag" {
  count       = length(data.aws_instances.production_instances.ids)
  resource_id = data.aws_instances.production_instances.ids[count.index]
  key         = "AutoPatch"
  value       = "true"
}

# Output instance information for verification
output "managed_instances" {
  description = "Information about managed instances"
  value = {
    for i, instance in local.instance_info : instance.id => {
      name        = instance.name
      os          = instance.os
      patch_group = instance.patch_group
      private_ip  = instance.private_ip
    }
  }
}
