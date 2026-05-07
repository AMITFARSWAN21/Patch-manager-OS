
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

# Data source to get detailed information about each instance
data "aws_instance" "production_details" {
  count       = length(data.aws_instances.production_instances.ids)
  instance_id = data.aws_instances.production_instances.ids[count.index]
}

# Add PatchGroup tag to existing instances
resource "aws_ec2_tag" "patch_group_tag" {
  count       = length(data.aws_instances.production_instances.ids)
  resource_id = data.aws_instances.production_instances.ids[count.index]
  key         = "PatchGroup"
  value       = var.patch_group_name
}

# Add AutoPatch tag to existing instances
resource "aws_ec2_tag" "auto_patch_tag" {
  count       = length(data.aws_instances.production_instances.ids)
  resource_id = data.aws_instances.production_instances.ids[count.index]
  key         = "AutoPatch"
  value       = "true"
}

# Output existing instance information
locals {
  instance_info = [
    for i, instance in data.aws_instance.production_details : {
      id         = instance.id
      name       = lookup(instance.tags, "Name", "Unnamed")
      private_ip = instance.private_ip
      public_ip  = instance.public_ip
      az         = instance.availability_zone
    }
  ]
}