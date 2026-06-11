# ============================================================
# LATEST WINDOWS SERVER 2022 AMI
# ============================================================

data "aws_ami" "windows_2022" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Windows_Server-2022-English-Full-Base-*"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# ============================================================
# WSUS SECURITY GROUP
# ============================================================

resource "aws_security_group" "wsus_sg" {
  name        = "wsus-sg-${random_string.suffix.result}"
  description = "WSUS server - inbound 8530 from private subnet, outbound to Microsoft"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "WSUS HTTP from private subnet"
    from_port   = 8530
    to_port     = 8530
    protocol    = "tcp"
    cidr_blocks = [var.private_subnet_cidr]
  }

  egress {
    description = "HTTPS to Microsoft Update"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "HTTP fallback to Microsoft Update"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "wsus-sg"
    Environment = var.target_environment
  }
}

# ============================================================
# WSUS SERVER
# Changes from previous version:
# 1. DownloadUpdateBinariesAsNeeded = $true  (was $false)
#    Prevents downloading all 203 update binaries (~47 GB)
#    Only downloads binaries for explicitly approved updates
# 2. Step 11 explicitly triggers DownloadContentFiles()
#    for approved updates before waiting — prevents race condition
# 3. Removed 22H2 and 23H2 from categories
#    These pulled in large .wim OS upgrade images (~20 GB)
#    Only needed if you have 22H2/23H2 instances
# Result: ~1.6 GB downloaded instead of 47+ GB
# ============================================================

resource "aws_instance" "wsus_server" {
  ami                         = data.aws_ami.windows_2022.id
  instance_type               = "t3.large"
  subnet_id                   = aws_subnet.public.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.wsus_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_ssm_profile.name

  user_data = <<-EOF
  <powershell>
  Start-Service AmazonSSMAgent -ErrorAction SilentlyContinue
  Set-Service AmazonSSMAgent -StartupType Automatic
  $attempts = 0
  while ((Get-Service AmazonSSMAgent).Status -ne "Running" -and $attempts -lt 30) {
    Start-Sleep -Seconds 10
    $attempts++
  }

  $wsusScript = @'
  Write-Output "WSUS setup started at $(Get-Date)" | Out-File C:\wsus-init.log

  Install-WindowsFeature -Name UpdateServices -IncludeManagementTools | Out-Null
  $attempts = 0
  do {
    Start-Sleep -Seconds 30
    $feature = Get-WindowsFeature -Name UpdateServices
    $attempts++
    Write-Output "WSUS install: $($feature.InstallState) (attempt $attempts)" | Out-File C:\wsus-init.log -Append
  } while ($feature.InstallState -ne "Installed" -and $attempts -lt 20)
  if ($feature.InstallState -ne "Installed") {
    Write-Output "ERROR: WSUS install failed" | Out-File C:\wsus-init.log -Append
    exit 1
  }

  New-Item -Path C:\WSUS -ItemType Directory -Force | Out-Null
  & "C:\Program Files\Update Services\Tools\WsusUtil.exe" postinstall CONTENT_DIR=C:\WSUS
  Start-Service WsusService -ErrorAction SilentlyContinue
  Set-Service WsusService -StartupType Automatic
  Start-Sleep -Seconds 15

  $wsusReady = $false
  $attempts = 0
  while (-not $wsusReady -and $attempts -lt 20) {
    try {
      $conn = Test-NetConnection -ComputerName localhost -Port 8530 -WarningAction SilentlyContinue
      if ($conn.TcpTestSucceeded) { $wsusReady = $true }
    } catch {}
    if (-not $wsusReady) { Start-Sleep -Seconds 30; $attempts++ }
  }
  if (-not $wsusReady) {
    Write-Output "ERROR: Port 8530 never ready" | Out-File C:\wsus-init.log -Append
    exit 1
  }
  Write-Output "Port 8530 ready at $(Get-Date)" | Out-File C:\wsus-init.log -Append

  Add-Type -Path "C:\Program Files\Update Services\Api\Microsoft.UpdateServices.Administration.dll"
  $wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer('localhost', $false, 8530)

  $config = $wsus.GetConfiguration()
  $config.SyncFromMicrosoftUpdate        = $true
  $config.DownloadUpdateBinariesAsNeeded = $true
  $config.GetContentFromMU               = $true
  $config.Save()
  Write-Output "Sync configured at $(Get-Date)" | Out-File C:\wsus-init.log -Append

  $subscription       = $wsus.GetSubscription()
  $allClassifications = $wsus.GetUpdateClassifications()
  $classCollection    = New-Object Microsoft.UpdateServices.Administration.UpdateClassificationCollection
  $allClassifications | Where-Object {
    $_.Title -eq "Critical Updates" -or $_.Title -eq "Security Updates"
  } | ForEach-Object { $classCollection.Add($_) | Out-Null }
  $subscription.SetUpdateClassifications($classCollection)
  $subscription.Save()
  Write-Output "Classifications set at $(Get-Date)" | Out-File C:\wsus-init.log -Append

  Write-Output "Starting category sync at $(Get-Date)" | Out-File C:\wsus-init.log -Append
  $subscription.StartSynchronizationForCategoryOnly()
  $attempts = 0
  do {
    Start-Sleep -Seconds 30
    $syncStatus = $subscription.GetSynchronizationStatus()
    if ($attempts % 20 -eq 0) {
      Write-Output "Category sync: $syncStatus at $(Get-Date) ($attempts/720)" | Out-File C:\wsus-init.log -Append
    }
    $attempts++
  } while ($syncStatus -eq "Running" -and $attempts -lt 720)
  Write-Output "Category sync done: $($subscription.GetSynchronizationStatus()) at $(Get-Date)" | Out-File C:\wsus-init.log -Append

  $allCategories = $wsus.GetUpdateCategories()
  $targetCategories = @(
    "Microsoft Server operating system-21H2",
    "Microsoft Server Operating System-24H2",
    ".NET Framework 3.5"
  )
  $catCollection = New-Object Microsoft.UpdateServices.Administration.UpdateCategoryCollection
  $foundNames    = @()
  $allCategories | Where-Object { $targetCategories -contains $_.Title } | ForEach-Object {
    $catCollection.Add($_) | Out-Null
    $foundNames += $_.Title
    Write-Output "MATCHED: $($_.Title)" | Out-File C:\wsus-init.log -Append
  }
  if ($catCollection.Count -eq 0) {
    Write-Output "ERROR: No categories matched" | Out-File C:\wsus-init.log -Append
    exit 1
  }
  $subscription.SetUpdateCategories($catCollection)
  $subscription.Save()
  Write-Output "Products saved at $(Get-Date)" | Out-File C:\wsus-init.log -Append

  Write-Output "Starting full sync at $(Get-Date)" | Out-File C:\wsus-init.log -Append
  $subscription.StartSynchronization()
  $attempts = 0
  do {
    Start-Sleep -Seconds 120
    $syncStatus  = $subscription.GetSynchronizationStatus()
    $countScope  = New-Object Microsoft.UpdateServices.Administration.UpdateScope
    $updateCount = $wsus.GetUpdateCount($countScope)
    Write-Output "Full sync: $syncStatus - $updateCount updates at $(Get-Date)" | Out-File C:\wsus-init.log -Append
    $attempts++
  } while ($syncStatus -eq "Running" -and $attempts -lt 240)
  Write-Output "Full sync done at $(Get-Date)" | Out-File C:\wsus-init.log -Append

  Write-Output "Approving latest cumulative updates at $(Get-Date)" | Out-File C:\wsus-init.log -Append
  $allGroups    = $wsus.GetComputerTargetGroups()
  $allComputers = $allGroups | Where-Object { $_.Name -eq "All Computers" }
  $scope        = New-Object Microsoft.UpdateServices.Administration.UpdateScope
  $allUpdates   = $wsus.GetUpdates($scope)
  $cumulatives  = $allUpdates | Where-Object {
    $_.Title -ilike "*Cumulative Update*" -and
    -not $_.IsDeclined -and
    -not $_.IsSuperseded
  }
  $latest2022 = $cumulatives | Where-Object {
    $_.Title -ilike "*server operating system*21H2*" -and
    $_.Title -notlike "*.NET*" -and
    $_.Title -notlike "*Framework*" -and
    $_.Title -notlike "*arm64*"
  } | Sort-Object CreationDate -Descending | Select-Object -First 1
  $latest2025 = $cumulatives | Where-Object {
    ($_.Title -ilike "*server operating system*24H2*" -or
     $_.Title -ilike "*Windows Server 2025*") -and
    $_.Title -notlike "*.NET*" -and
    $_.Title -notlike "*Framework*"
  } | Sort-Object CreationDate -Descending | Select-Object -First 1
  $approved = 0
  foreach ($update in @($latest2022, $latest2025)) {
    if ($null -eq $update) {
      Write-Output "WARNING: No update found for one OS" | Out-File C:\wsus-init.log -Append
      continue
    }
    try {
      $update.Approve([Microsoft.UpdateServices.Administration.UpdateApprovalAction]::Install, $allComputers)
      $approved++
      Write-Output "APPROVED: $($update.Title)" | Out-File C:\wsus-init.log -Append
    } catch {
      Write-Output "FAILED: $($update.Title) - $_" | Out-File C:\wsus-init.log -Append
    }
  }
  if ($approved -eq 0) {
    Write-Output "ERROR: No updates approved" | Out-File C:\wsus-init.log -Append
    exit 1
  }

  $latestDotNet2022 = $allUpdates | Where-Object {
    $_.Title -ilike "*Cumulative Update*.NET Framework*21H2*" -and
    $_.Title -notlike "*arm64*" -and
    -not $_.IsDeclined -and
    -not $_.IsSuperseded
  } | Sort-Object CreationDate -Descending | Select-Object -First 1

  $latestDotNet2025 = $allUpdates | Where-Object {
    $_.Title -ilike "*Cumulative Update*.NET Framework*24H2*" -and
    $_.Title -notlike "*arm64*" -and
    -not $_.IsDeclined -and
    -not $_.IsSuperseded
  } | Sort-Object CreationDate -Descending | Select-Object -First 1

  foreach ($update in @($latestDotNet2022, $latestDotNet2025)) {
    if ($null -eq $update) {
      Write-Output "WARNING: No .NET update found for one OS" | Out-File C:\wsus-init.log -Append
      continue
    }
    try {
      $update.Approve([Microsoft.UpdateServices.Administration.UpdateApprovalAction]::Install, $allComputers)
      $approved++
      Write-Output "APPROVED .NET: $($update.Title)" | Out-File C:\wsus-init.log -Append
    } catch {
      Write-Output "FAILED .NET: $($update.Title) - $_" | Out-File C:\wsus-init.log -Append
    }
  }
  Write-Output "Approved $approved updates at $(Get-Date)" | Out-File C:\wsus-init.log -Append

  Write-Output "Triggering download for approved updates only at $(Get-Date)" | Out-File C:\wsus-init.log -Append
  $approvedScope = New-Object Microsoft.UpdateServices.Administration.UpdateScope
  $approvedScope.ApprovedStates = [Microsoft.UpdateServices.Administration.ApprovedStates]::LatestRevisionApproved

  $wsus.GetUpdates($approvedScope) | ForEach-Object {
    try {
      $_.DownloadContentFiles()
      Write-Output "Triggered download: $($_.Title)" | Out-File C:\wsus-init.log -Append
    } catch {
      Write-Output "Trigger failed: $($_.Title) - $_" | Out-File C:\wsus-init.log -Append
    }
  }

  $attempts = 0
  do {
    Start-Sleep -Seconds 120
    $notReady = ($wsus.GetUpdates($approvedScope) | Where-Object { $_.State -eq "NotReady" }).Count
    $ready    = ($wsus.GetUpdates($approvedScope) | Where-Object { $_.State -eq "Ready"    }).Count
    Write-Output "Ready=$ready Pending=$notReady at $(Get-Date)" | Out-File C:\wsus-init.log -Append
    $attempts++
  } while ($notReady -gt 0 -and $attempts -lt 60)
  Write-Output "WSUS SETUP COMPLETE at $(Get-Date)" | Out-File C:\wsus-init.log -Append
'@

  $wsusScript | Out-File C:\wsus-setup.ps1 -Encoding UTF8

  $action    = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -NonInteractive -File C:\wsus-setup.ps1"
  $trigger   = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(30)
  $settings  = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::FromHours(24))
  $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
  Register-ScheduledTask -TaskName "WSUS-Setup" -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force
  Write-Output "WSUS-Setup task registered at $(Get-Date)" | Out-File C:\wsus-task-registered.log
  </powershell>
EOF

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 200
    delete_on_termination = true
    encrypted             = true
    tags = {
      Name        = "wsus-server-root"
      Environment = var.target_environment
    }
  }

  tags = {
    Name        = "WSUS-Server"
    Role        = "PatchManagement"
    Environment = var.target_environment
    AutoPatch   = "false"
    OS          = "windows"
  }

  lifecycle {
    ignore_changes = [user_data, ami, tags]
  }

  depends_on = [
    aws_iam_instance_profile.ec2_ssm_profile,
    aws_internet_gateway.main
  ]
}

# ============================================================
# OUTPUTS
# ============================================================

output "wsus_server_id" {
  description = "WSUS server instance ID"
  value       = aws_instance.wsus_server.id
}

output "wsus_server_private_ip" {
  description = "WSUS server private IP - Windows clients point here on port 8530"
  value       = aws_instance.wsus_server.private_ip
}

output "wsus_server_public_ip" {
  description = "WSUS server public IP - management only"
  value       = aws_instance.wsus_server.public_ip
}

output "wsus_sync_check_command" {
  description = "Connect to WSUS server via SSM"
  value       = "aws ssm start-session --target ${aws_instance.wsus_server.id} --region ${var.aws_region}"
}
