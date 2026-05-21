# ============================================================
# WSUS SECURITY GROUP
# ============================================================

resource "aws_security_group" "wsus_sg" {
  name        = "wsus-sg-${random_string.suffix.result}"
  description = "WSUS server - HTTP 8530 and HTTPS 8531 for Windows patch clients"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "WSUS HTTP from private subnet"
    from_port   = 8530
    to_port     = 8530
    protocol    = "tcp"
    cidr_blocks = [var.private_subnet_cidr]
  }

  ingress {
    description = "WSUS HTTPS from private subnet"
    from_port   = 8531
    to_port     = 8531
    protocol    = "tcp"
    cidr_blocks = [var.private_subnet_cidr]
  }

  egress {
    description = "All outbound for Microsoft sync and SSM"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "wsus-sg"
    Environment = "Production"
  }
}

# ============================================================
# WSUS SERVER
# Windows Server 2022 in public subnet
# Syncs Server 2022 and 2025 patches from Microsoft
# Serves patches to private Windows instances on port 8530
# ============================================================

resource "aws_instance" "wsus_server" {
  ami                    = "ami-038b0fc52513087d0"
  instance_type          = "t3.large"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [
    aws_security_group.wsus_sg.id,
    data.aws_security_group.default_sg.id
  ]
  iam_instance_profile = aws_iam_instance_profile.ec2_ssm_profile.name

  user_data = <<-EOF
    <powershell>
    # Step 1 - Start SSM Agent
    Start-Service AmazonSSMAgent -ErrorAction SilentlyContinue
    Set-Service AmazonSSMAgent -StartupType Automatic
    Write-Output "SSM Agent started at $(Get-Date)" | Out-File C:\wsus-init.log

    # Step 2 - Install WSUS role
    Write-Output "Installing WSUS role at $(Get-Date)" | Out-File C:\wsus-init.log -Append
    Install-WindowsFeature -Name UpdateServices -IncludeManagementTools

    $feature = Get-WindowsFeature -Name UpdateServices
    $attempts = 0
    while ($feature.InstallState -ne "Installed" -and $attempts -lt 20) {
      Write-Output "Waiting for WSUS feature... attempt $attempts" | Out-File C:\wsus-init.log -Append
      Start-Sleep -Seconds 30
      $feature = Get-WindowsFeature -Name UpdateServices
      $attempts++
    }
    Write-Output "WSUS feature installed at $(Get-Date)" | Out-File C:\wsus-init.log -Append

    # Step 3 - Post-install configuration
    New-Item -Path C:\WSUS -ItemType Directory -Force
    Write-Output "Running WsusUtil postinstall at $(Get-Date)" | Out-File C:\wsus-init.log -Append
    & "C:\Program Files\Update Services\Tools\WsusUtil.exe" postinstall CONTENT_DIR=C:\WSUS
    Write-Output "WsusUtil postinstall complete at $(Get-Date)" | Out-File C:\wsus-init.log -Append

    # Start WSUS service explicitly
    Start-Service WsusService -ErrorAction SilentlyContinue
    Set-Service WsusService -StartupType Automatic
    Write-Output "WSUS service started at $(Get-Date)" | Out-File C:\wsus-init.log -Append

    # Step 4 - Wait for port 8530
    $wsusReady = $false
    $attempts = 0
    while (-not $wsusReady -and $attempts -lt 20) {
      try {
        $connection = Test-NetConnection -ComputerName localhost -Port 8530 -WarningAction SilentlyContinue
        if ($connection.TcpTestSucceeded) {
          $wsusReady = $true
          Write-Output "WSUS port 8530 ready at $(Get-Date)" | Out-File C:\wsus-init.log -Append
        }
      } catch {}
      if (-not $wsusReady) {
        Write-Output "Waiting for port 8530... attempt $attempts" | Out-File C:\wsus-init.log -Append
        Start-Sleep -Seconds 30
        $attempts++
      }
    }

    # Load WSUS assembly using direct path (more reliable than LoadWithPartialName)
    Add-Type -Path "C:\Program Files\Update Services\Api\Microsoft.UpdateServices.Administration.dll"
    $wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer('localhost', $false, 8530)

    # Step 5 - Configure sync source
    $config = $wsus.GetConfiguration()
    $config.SyncFromMicrosoftUpdate = $true
    $config.Save()
    Write-Output "Sync source configured at $(Get-Date)" | Out-File C:\wsus-init.log -Append

    # Step 6 - Set classifications
    # These cover all update types for Server 2022 and 2025
    $subscription = $wsus.GetSubscription()
    $allClassifications = $wsus.GetUpdateClassifications()
    $classificationCollection = New-Object Microsoft.UpdateServices.Administration.UpdateClassificationCollection
    $allClassifications | Where-Object {
      $_.Title -eq "Critical Updates" -or
      $_.Title -eq "Security Updates" -or
      $_.Title -eq "Updates" -or
      $_.Title -eq "Update Rollups" -or
      $_.Title -eq "Service Packs"
    } | ForEach-Object {
      $classificationCollection.Add($_) | Out-Null
      Write-Output "Added classification: $($_.Title)" | Out-File C:\wsus-init.log -Append
    }
    $subscription.SetUpdateClassifications($classificationCollection)
    $subscription.Save()
    Write-Output "Classifications configured at $(Get-Date)" | Out-File C:\wsus-init.log -Append

    # Step 7 - Category sync FIRST before setting products
    # GetUpdateCategories() returns empty before this runs
    # Increased to 180 attempts (90 mins) to avoid timeout
    Write-Output "Starting category sync at $(Get-Date)" | Out-File C:\wsus-init.log -Append
    $subscription.StartSynchronizationForCategoryOnly()

    $attempts = 0
    do {
      Start-Sleep -Seconds 30
      $syncStatus = $subscription.GetSynchronizationStatus()
      Write-Output "Category sync: $syncStatus at $(Get-Date)" | Out-File C:\wsus-init.log -Append
      $attempts++
    } while ($syncStatus -eq "Running" -and $attempts -lt 180)
    Write-Output "Category sync finished at $(Get-Date)" | Out-File C:\wsus-init.log -Append

    # Step 8 - Set products AFTER category sync
    # Only Server 2022 and 2025 — nothing else
    # These exact titles confirmed from Server 2022 WSUS
    $allCategories = $wsus.GetUpdateCategories()
    Write-Output "Total available categories: $($allCategories.Count)" | Out-File C:\wsus-init.log -Append

    $categoryCollection = New-Object Microsoft.UpdateServices.Administration.UpdateCategoryCollection
    $allCategories | Where-Object {
      $_.Title -eq "Microsoft Server operating system-21H2" -or
      $_.Title -eq "Microsoft Server Operating System-22H2" -or
      $_.Title -eq "Microsoft Server Operating System-23H2" -or
      $_.Title -eq "Microsoft Server Operating System-24H2" -or
      $_.Title -eq "Server 2022 Hotpatch Category" -or
      $_.Title -eq "Windows - Server, version 21H2 and later, Servicing Drivers" -or
      $_.Title -eq "Windows - Server, version 21H2 and later, Upgrade & Servicing Drivers" -or
      $_.Title -eq "Windows - Server, version 24H2 and later, Upgrade & Servicing Drivers"
    } | ForEach-Object {
      $categoryCollection.Add($_) | Out-Null
      Write-Output "Added product: $($_.Title)" | Out-File C:\wsus-init.log -Append
    }
    $subscription.SetUpdateCategories($categoryCollection)
    $subscription.Save()
    Write-Output "Products set at $(Get-Date)" | Out-File C:\wsus-init.log -Append

    # Step 9 - Full sync with correct products
    # Increased to 240 attempts (8 hours) for large sync
    Write-Output "Starting full sync at $(Get-Date)" | Out-File C:\wsus-init.log -Append
    $subscription.StartSynchronization()

    $attempts = 0
    do {
      Start-Sleep -Seconds 120
      $syncStatus = $subscription.GetSynchronizationStatus()
      $updateCount = $wsus.GetUpdateCount()
      Write-Output "Full sync: $syncStatus - Updates: $updateCount at $(Get-Date)" | Out-File C:\wsus-init.log -Append
      $attempts++
    } while ($syncStatus -eq "Running" -and $attempts -lt 240)
    Write-Output "Full sync completed at $(Get-Date)" | Out-File C:\wsus-init.log -Append
    Write-Output "Total updates: $($wsus.GetUpdateCount())" | Out-File C:\wsus-init.log -Append

    # Step 10 - Approve ALL non-declined updates
    # Removed IsLatestRevision filter to include hotpatches
    # Products already filtered to Server 2022 and 2025 only
    Write-Output "Approving updates at $(Get-Date)" | Out-File C:\wsus-init.log -Append
    $allGroups = $wsus.GetComputerTargetGroups()
    $allComputersGroup = $allGroups | Where-Object {$_.Name -eq "All Computers"}

    $updateScope = New-Object Microsoft.UpdateServices.Administration.UpdateScope
    $updateScope.ApprovedStates = [Microsoft.UpdateServices.Administration.ApprovedStates]::NotApproved
    $pendingUpdates = $wsus.GetUpdates($updateScope)

    $approved = 0
    $pendingUpdates | Where-Object {
      -not $_.IsDeclined
    } | ForEach-Object {
      try {
        $_.Approve(
          [Microsoft.UpdateServices.Administration.UpdateApprovalAction]::Install,
          $allComputersGroup
        )
        $approved++
      } catch {}
    }
    Write-Output "Approved $approved updates at $(Get-Date)" | Out-File C:\wsus-init.log -Append

    # Step 11 - Wait for ALL content to download
    # Ensures no NotReady patches remain after approval
    Write-Output "Waiting for all content to download at $(Get-Date)" | Out-File C:\wsus-init.log -Append
    $attempts = 0
    do {
      Start-Sleep -Seconds 120
      $notReady = ($wsus.GetUpdates() | Where-Object {
        $_.IsApproved -and $_.State -eq 'NotReady'
      }).Count
      Write-Output "NotReady: $notReady at $(Get-Date)" | Out-File C:\wsus-init.log -Append
      $attempts++
    } while ($notReady -gt 0 -and $attempts -lt 120)
    Write-Output "All content downloaded at $(Get-Date)" | Out-File C:\wsus-init.log -Append

    Write-Output "WSUS ready for Windows Server 2022 and 2025" | Out-File C:\wsus-init.log -Append
    Write-Output "WSUS setup complete at $(Get-Date)" | Out-File C:\wsus-init.log -Append
    </powershell>
  EOF

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 200
    delete_on_termination = true
    encrypted             = true

    tags = {
      Name        = "wsus-server-root"
      Environment = "Production"
    }
  }

  tags = {
    Name = "WSUS-Server"
    Role = "PatchManagement"
  }

  lifecycle {
    ignore_changes = [tags]
  }

  depends_on = [
    aws_iam_instance_profile.ec2_ssm_profile,
    aws_internet_gateway.main
  ]
}

# ============================================================
# APT CACHE SERVER SECURITY GROUP -- NOT REQUIRED
# ============================================================

# resource "aws_security_group" "apt_cache_sg" {
#   name        = "apt-cache-sg-${random_string.suffix.result}"
#   description = "apt-cacher-ng server for Ubuntu patch caching"
#   vpc_id      = aws_vpc.main.id
#
#   ingress {
#     description = "apt-cacher-ng from private subnet"
#     from_port   = 3142
#     to_port     = 3142
#     protocol    = "tcp"
#     cidr_blocks = [var.private_subnet_cidr]
#   }
#
#   egress {
#     description = "All outbound for Canonical sync"
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }
#
#   tags = {
#     Name        = "apt-cache-sg"
#     Environment = "Production"
#   }
# }

# ============================================================
# APT CACHE SERVER -- NOT REQUIRED
# ============================================================

# resource "aws_instance" "apt_cache_server" {
#   ami                    = "ami-0e267a9919cdf778f"
#   instance_type          = "t3.medium"
#   subnet_id              = aws_subnet.public.id
#   vpc_security_group_ids = [
#     aws_security_group.apt_cache_sg.id,
#     data.aws_security_group.default_sg.id
#   ]
#   iam_instance_profile = aws_iam_instance_profile.ec2_ssm_profile.name
#
#   user_data = <<-EOF
#     #!/bin/bash
#     systemctl enable amazon-ssm-agent
#     systemctl start amazon-ssm-agent
#     echo "SSM Agent started at $(date)" > /var/log/apt-cache-init.log
#
#     yum install -y docker
#     systemctl enable docker
#     systemctl start docker
#     echo "Docker installed at $(date)" >> /var/log/apt-cache-init.log
#
#     docker run -d \
#       --name apt-cacher-ng \
#       --restart always \
#       -p 3142:3142 \
#       -v /var/cache/apt-cacher-ng:/var/cache/apt-cacher-ng \
#       sameersbn/apt-cacher-ng
#
#     echo "apt-cacher-ng started at $(date)" >> /var/log/apt-cache-init.log
#   EOF
#
#   root_block_device {
#     volume_type           = "gp3"
#     volume_size           = 100
#     delete_on_termination = true
#     encrypted             = true
#
#     tags = {
#       Name        = "apt-cache-server-root"
#       Environment = "Production"
#     }
#   }
#
#   tags = {
#     Name = "APT-Cache-Server"
#     Role = "PatchManagement"
#   }
#
#   lifecycle {
#     ignore_changes = [tags]
#   }
#
#   depends_on = [
#     aws_iam_instance_profile.ec2_ssm_profile,
#     aws_internet_gateway.main
#   ]
# }

# ============================================================
# OUTPUTS
# ============================================================

output "wsus_server_id" {
  description = "WSUS server instance ID"
  value       = aws_instance.wsus_server.id
}

output "wsus_server_private_ip" {
  description = "WSUS server private IP - Windows instances point to this on port 8530"
  value       = aws_instance.wsus_server.private_ip
}

output "wsus_server_public_ip" {
  description = "WSUS server public IP - for management only"
  value       = aws_instance.wsus_server.public_ip
}

output "wsus_sync_check_command" {
  description = "Command to check if WSUS sync completed before patching"
  value       = "aws ssm start-session --target ${aws_instance.wsus_server.id} --region ${var.aws_region}"
}

# output "apt_cache_server_id" {
#   value = aws_instance.apt_cache_server.id
# }
#
# output "apt_cache_server_private_ip" {
#   description = "apt-cacher-ng private IP - Ubuntu instances point here on port 3142"
#   value       = aws_instance.apt_cache_server.private_ip
# }
