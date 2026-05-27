# ============================================================
# INSTANCE DISCOVERY
# ============================================================

# Single call — fetches all matching instance IDs
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

# Deduplicated local so toset() is never repeated
locals {
  instance_ids = toset(data.aws_instances.production_instances.ids)
}

# Per-instance EC2 detail — one call per instance (unavoidable)
data "aws_instance" "production_details" {
  for_each    = local.instance_ids
  instance_id = each.value
}

# ============================================================
# SSM INVENTORY — ONE CALL FOR ALL INSTANCES
# Replaces N per-instance PowerShell spawns with a single
# cross-platform AWS CLI call. Works on Linux, Mac, Windows.
# ============================================================

data "external" "ssm_inventory_all" {
  program = ["powershell", "-ExecutionPolicy", "Bypass", "-Command", <<-EOT
    try {
      $raw = (aws ssm describe-instance-information `
        --output json `
        --query "InstanceInformationList[*].{id:InstanceId,platform_type:PlatformType,platform_name:PlatformName,platform_version:PlatformVersion,computer_name:ComputerName,agent_version:AgentVersion}" `
        2>$null) | Out-String

      $trimmed = $raw.Trim()

      if (-not $trimmed -or $trimmed -eq "null" -or $trimmed -eq "") {
        $trimmed = "[]"
      }

      @{ instances = $trimmed } | ConvertTo-Json -Compress
    } catch {
      @{ instances = "[]" } | ConvertTo-Json -Compress
    }
  EOT
  ]
}

# ============================================================
# LOCALS
# ============================================================

locals {
  # ----------------------------------------------------------
  # Parse the single SSM response into a map keyed by instance ID
  # Result shape: { "i-xxx" => { platform_type, platform_name, ... } }
  # ----------------------------------------------------------
  ssm_inventory_map = {
   for entry in jsondecode(data.external.ssm_inventory_all.result.instances) :
    entry.id => {
     platform_type    = coalesce(try(entry.platform_type, ""), "unknown")
platform_name    = coalesce(try(entry.platform_name, ""), "unknown")
platform_version = coalesce(try(entry.platform_version, ""), "unknown")
computer_name    = coalesce(try(entry.computer_name, ""), "unknown")
agent_version    = coalesce(try(entry.agent_version, ""), "unknown")
      ssm_managed      = true
    }
  }

  # Sentinel returned for instances not in SSM inventory
  ssm_not_managed = {
    platform_type    = "unknown"
    platform_name    = "unknown"
    platform_version = "unknown"
    computer_name    = "unknown"
    agent_version    = "unknown"
    ssm_managed      = false
  }

  # ----------------------------------------------------------
  # OS detection pattern map — add a new OS by adding one line
  # Evaluated in order; first match wins
  # ----------------------------------------------------------
  os_patterns = [
    { os = "amazonlinux",  pattern = "(?i)(amazon.*linux.*2023|al2023)" },
    { os = "amazonlinux2", pattern = "(?i)(amazon.*linux|amzn)"         },
    { os = "ubuntu",       pattern = "(?i)(ubuntu)"                     },
  ]

  # ----------------------------------------------------------
  # Core instance info — single source of truth
  # ----------------------------------------------------------
  instance_info = {
    for id in data.aws_instances.production_instances.ids :
    id => {
      id         = id
      name       = lookup(data.aws_instance.production_details[id].tags, "Name", "Unnamed")
      private_ip = data.aws_instance.production_details[id].private_ip
      public_ip  = data.aws_instance.production_details[id].public_ip
      az         = data.aws_instance.production_details[id].availability_zone
      ami_id     = data.aws_instance.production_details[id].ami
      environment = lookup(data.aws_instance.production_details[id].tags, "Environment", "unknown")
      project     = lookup(data.aws_instance.production_details[id].tags, "Project", "unknown")
      owner       = lookup(data.aws_instance.production_details[id].tags, "Owner", "unknown")

      # Merge SSM data — falls back to ssm_not_managed sentinel if instance not in SSM
      ssm_managed          = lookup(local.ssm_inventory_map, id, local.ssm_not_managed).ssm_managed
      ssm_platform_type    = lookup(local.ssm_inventory_map, id, local.ssm_not_managed).platform_type
      ssm_platform_name    = lookup(local.ssm_inventory_map, id, local.ssm_not_managed).platform_name
      ssm_platform_version = lookup(local.ssm_inventory_map, id, local.ssm_not_managed).platform_version
      ssm_computer_name    = lookup(local.ssm_inventory_map, id, local.ssm_not_managed).computer_name
      ssm_agent_version    = lookup(local.ssm_inventory_map, id, local.ssm_not_managed).agent_version

      # ----------------------------------------------------------
      # OS detection:
      # 1. Manual tag wins (highest confidence)
      # 2. SSM platform_type + pattern matching (high confidence)
      # 3. Unknown (undetectable)
      # ----------------------------------------------------------
      detected_os = (
        # Step 1 — manual OS tag on the instance
        lookup(data.aws_instance.production_details[id].tags, "OS", "") != ""
        ? lower(lookup(data.aws_instance.production_details[id].tags, "OS", ""))

        # Step 2 — SSM inventory available
        : lookup(local.ssm_inventory_map, id, local.ssm_not_managed).ssm_managed ? (

          lower(lookup(local.ssm_inventory_map, id, local.ssm_not_managed).platform_type) == "windows"
          ? "windows"

          : lower(lookup(local.ssm_inventory_map, id, local.ssm_not_managed).platform_type) == "linux"
? coalesce(concat(
    [for p in local.os_patterns :
      p.os
      if can(regex(p.pattern,
        "${lookup(local.ssm_inventory_map, id, local.ssm_not_managed).platform_name} ${lookup(local.ssm_inventory_map, id, local.ssm_not_managed).platform_version}"))
    ],
    ["linux"]
  )...)

          : lower(lookup(local.ssm_inventory_map, id, local.ssm_not_managed).platform_type) == "macos"
          ? "macos"

          : "unknown"
        )

        # Step 3 — nothing worked
        : "unknown"
      )

      detection_confidence = (
        lookup(data.aws_instance.production_details[id].tags, "OS", "") != "" ? "manual" :
        lookup(local.ssm_inventory_map, id, local.ssm_not_managed).ssm_managed  ? "high"   :
        "undetectable"
      )
    }
  }

  # ----------------------------------------------------------
  # Valid instances — known OS, in patch configs, SSM managed
  # ----------------------------------------------------------
  valid_instances = {
    for id, instance in local.instance_info :
    id => instance
    if instance.detected_os != "unknown" &&
       contains(keys(var.os_patch_configs), instance.detected_os) &&
       instance.detection_confidence != "undetectable"
  }

  # ----------------------------------------------------------
  # Instances that need manual review
  # ----------------------------------------------------------
  review_instances = {
    for id, instance in local.instance_info :
    id => instance
    if instance.detected_os == "unknown" ||
       !contains(keys(var.os_patch_configs), instance.detected_os) ||
       instance.detection_confidence == "undetectable"
  }

  # ----------------------------------------------------------
  # Flat tag map — one resource block handles all tags for all
  # instances instead of 6 separate aws_ec2_tag resources
  # ----------------------------------------------------------
  instance_tags_flat = merge([
    for id, instance in local.valid_instances : {
      for k, v in merge(
        {
          PatchGroup            = "${instance.detected_os}-Production-PatchGroup"
          AutoPatch             = "true"
          OS                    = instance.detected_os
          OSDetectionConfidence = instance.detection_confidence
        },
        instance.ssm_managed ? {
          SSMPlatformType    = instance.ssm_platform_type
          SSMPlatformName    = instance.ssm_platform_name
          SSMPlatformVersion = instance.ssm_platform_version
        } : {}
      ) : "${id}|${k}" => { resource_id = id, key = k, value = v }
    }
  ]...)
}

# ============================================================
# TAGS — single resource block replaces 6 separate ones
# 100 instances × 7 tags = 700 state entries, but only
# ONE resource type to manage instead of six
# ============================================================

resource "aws_ec2_tag" "instance_tags" {
  for_each    = local.instance_tags_flat
  resource_id = each.value.resource_id
  key         = each.value.key
  value       = each.value.value
}

# ============================================================
# ZERO-INSTANCE GUARD
# Surfaces clearly when no instances are found instead of
# silently succeeding with nothing patched
# ============================================================

output "instance_discovery_status" {
  description = "Confirms how many instances were found — alerts if zero"
  value = (
    length(data.aws_instances.production_instances.ids) == 0
    ? "WARNING: No running instances found matching environment patterns ${jsonencode(var.environment_patterns)}. Nothing will be patched."
    : "OK: ${length(data.aws_instances.production_instances.ids)} instances found. ${length(local.valid_instances)} valid, ${length(local.review_instances)} need review."
  )
}

# ============================================================
# OUTPUTS — consolidated, no overlapping fields
# ============================================================

output "patch_group_assignments" {
  description = "Final patch group assignments for all valid instances"
  value = {
    for id, instance in local.valid_instances : id => {
      name                 = instance.name
      os                   = instance.detected_os
      patch_group          = "${instance.detected_os}-Production-PatchGroup"
      confidence           = instance.detection_confidence
      ssm_managed          = instance.ssm_managed
      ssm_platform_name    = instance.ssm_platform_name
      ssm_platform_version = instance.ssm_platform_version
      ssm_agent_version    = instance.ssm_agent_version
      ssm_computer_name    = instance.ssm_computer_name
    }
  }
}

output "instances_needing_review" {
  description = "Instances skipped — missing SSM, unknown OS, or unsupported OS type"
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
        !instance.ssm_managed
        ? "Instance not managed by SSM — install and register the SSM agent"
        : instance.detected_os == "unknown"
        ? "OS could not be identified from SSM inventory data"
        : !contains(keys(var.os_patch_configs), instance.detected_os)
        ? "OS type '${instance.detected_os}' is not in var.os_patch_configs"
        : "Undetectable — no SSM inventory and no manual OS tag"
      )
    }
  ]
}

output "os_detection_summary" {
  description = "Summary counts by OS type, confidence level, and SSM coverage"
  value = {
    total_instances        = length(local.instance_info)
    valid_instances        = length(local.valid_instances)
    review_needed          = length(local.review_instances)
    ssm_managed_count      = length([for id, i in local.instance_info : i if i.ssm_managed])
    ssm_managed_percentage = (
      length(local.instance_info) > 0
      ? length([for id, i in local.instance_info : i if i.ssm_managed]) * 100 / length(local.instance_info)
      : 0
    )
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
